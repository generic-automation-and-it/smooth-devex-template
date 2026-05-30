using Aspire.Hosting;
using Aspire.Hosting.ApplicationModel;
using Aspire.Hosting.Testing;
using Npgsql;
using Project.TestFramework.Aspire;
using System.Diagnostics;
using System.Net.Http;
using Xunit.v3;

namespace Project.TestFramework.Fixtures;

public sealed class AspireFixture : IAsyncLifetime
{
    private static readonly TimeSpan _timeout = TimeSpan.FromMinutes(5);
    private const string MaintenanceDatabaseName = "postgres";
    private const string PostgresResourceName = "postgres";
    private const string WireMockResourceName = "wiremock";
    private const string PostgresContainerName = "project-test-postgres";
    private const string WireMockContainerName = "project-test-wiremock";
    private const string PostgresPassword = "LocalMachineAccessNoInterestingDataTestDev#Passw0rd!FirewallNotExposed";
    private const int PostgresPort = 15432;
    private const int WireMockPort = 19091;
    private const int MaxEndpointCheckAttempts = 3;

    private static readonly SemaphoreSlim _initSemaphore = new(1, 1);
    private static DistributedApplication? _sharedApp;
    private static string? _sharedPostgresBaseConnectionString;
    private static string _sharedWireMockBaseUrl = string.Empty;

    private bool _ownsSharedApp;
    private string? _postgresBaseConnectionString;
    private ITestOutputHelper? _output;

    public void SetOutput(ITestOutputHelper? output) => _output = output;

    public string WireMockBaseUrl { get; private set; } = string.Empty;

    public WireMockAdminClient CreateWireMockAdminClient() => WireMockAdminClient.Create(WireMockBaseUrl);

    public string CreateDatabaseConnectionString(string databaseName)
    {
        string baseConnectionString = _postgresBaseConnectionString
            ?? throw new InvalidOperationException("Aspire fixture has not been initialized.");

        var builder = new NpgsqlConnectionStringBuilder(baseConnectionString)
        {
            Database = databaseName
        };

        return builder.ConnectionString;
    }

    public async ValueTask InitializeAsync()
    {
        await _initSemaphore.WaitAsync();
        try
        {
            if (_sharedPostgresBaseConnectionString is not null)
            {
                _postgresBaseConnectionString = _sharedPostgresBaseConnectionString;
                WireMockBaseUrl = _sharedWireMockBaseUrl;
                Log($"Reusing shared postgres connection: {LogPostgresAddress(_postgresBaseConnectionString)}");
                return;
            }

            Log("Attempting to use fixed well-known endpoints (pre-warmed containers)...");
            if (await TryUseFixedEndpointsAsync())
            {
                Log($"Using fixed endpoints — postgres=127.0.0.1:{PostgresPort} wiremock=127.0.0.1:{WireMockPort}");
                _sharedPostgresBaseConnectionString = _postgresBaseConnectionString;
                _sharedWireMockBaseUrl = WireMockBaseUrl;
                return;
            }

            Log("Fixed endpoints not available. Querying Docker for persistent container ports...");
            if (await TryUsePersistentContainerEndpointsAsync())
            {
                Log($"Using persistent container endpoints — postgres={LogPostgresAddress(_postgresBaseConnectionString)} wiremock={WireMockBaseUrl}");
                _sharedPostgresBaseConnectionString = _postgresBaseConnectionString;
                _sharedWireMockBaseUrl = WireMockBaseUrl;
                return;
            }

            Log("No pre-existing containers reachable. Starting Aspire host to provision containers...");
            using var cts = new CancellationTokenSource(_timeout);

            try
            {
                var appHost = await DistributedApplicationTestingBuilder
                    .CreateAsync<Projects.Project_TestFramework_Aspire>(["--no-dashboard"], cts.Token);

                DistributedApplication app = await appHost.BuildAsync(cts.Token);
                await app.StartAsync(cts.Token);

                await app.ResourceNotifications
                    .WaitForResourceHealthyAsync(PostgresResourceName, cts.Token);

                _postgresBaseConnectionString = await app.GetConnectionStringAsync(PostgresResourceName, cts.Token);
                WireMockBaseUrl = app.GetEndpoint(WireMockResourceName).AbsoluteUri.TrimEnd('/');

                Log($"Aspire host provisioned — postgres={LogPostgresAddress(_postgresBaseConnectionString)} wiremock={WireMockBaseUrl}");

                await WaitUntilPostgresAcceptsConnectionsAsync(cts.Token);

                await app.ResourceNotifications
                    .WaitForResourceHealthyAsync(WireMockResourceName, cts.Token);

                _sharedApp = app;
                _sharedPostgresBaseConnectionString = _postgresBaseConnectionString;
                _sharedWireMockBaseUrl = WireMockBaseUrl;
                _ownsSharedApp = true;
            }
            catch (Exception aspireEx)
            {
                // When multiple test assemblies start in parallel, several processes race to provision
                // the same persistent containers. Only one wins; the others get here because the
                // container name/port is already in use. Retry the endpoint checks — by now the
                // winning process should have the containers up.
                Log($"Aspire host failed ({aspireEx.GetType().Name}: {aspireEx.Message}). Checking whether another process started the containers...");

                for (int retry = 1; retry <= 10; retry++)
                {
                    await Task.Delay(TimeSpan.FromSeconds(3), CancellationToken.None);

                    if (await TryUseFixedEndpointsAsync())
                    {
                        Log($"Retry {retry}/10: Fixed endpoints now reachable — containers started by another process.");
                        _sharedPostgresBaseConnectionString = _postgresBaseConnectionString;
                        _sharedWireMockBaseUrl = WireMockBaseUrl;
                        return;
                    }

                    if (await TryUsePersistentContainerEndpointsAsync())
                    {
                        Log($"Retry {retry}/10: Persistent container endpoints now reachable.");
                        _sharedPostgresBaseConnectionString = _postgresBaseConnectionString;
                        _sharedWireMockBaseUrl = WireMockBaseUrl;
                        return;
                    }

                    Log($"Retry {retry}/10: Containers not yet reachable.");
                }

                System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(aspireEx).Throw();
                throw; // unreachable — satisfies compiler flow analysis
            }
        }
        finally
        {
            _initSemaphore.Release();
        }
    }

    public ValueTask DisposeAsync()
    {
        // The Aspire DistributedApplication is shared across all fixtures in this test process.
        // Containers use ContainerLifetime.Persistent and outlive any individual fixture instance,
        // so disposal is intentionally a no-op here.
        Log("DisposeAsync called — shared Aspire containers are persistent and will not be stopped.");
        _ = _ownsSharedApp;
        return ValueTask.CompletedTask;
    }

    private async Task<bool> TryPostgresAsync()
    {
        string maintenanceConnectionString;
        try
        {
            maintenanceConnectionString = CreateDatabaseConnectionString(MaintenanceDatabaseName);
        }
        catch (InvalidOperationException)
        {
            return false;
        }

        try
        {
            // Disable SSL to avoid negotiation hangs against the plain test postgres container.
            await using var connection = new NpgsqlConnection(
                $"{maintenanceConnectionString};Timeout=5;Command Timeout=5;SSL Mode=Disable");
            await connection.OpenAsync();
            return true;
        }
        catch (Exception ex)
        {
            Log($"Postgres probe failed: {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    private async Task<bool> TryUseFixedEndpointsAsync()
    {
        for (int attempt = 1; attempt <= MaxEndpointCheckAttempts; attempt++)
        {
            if (attempt > 1)
            {
                Log($"Retrying fixed endpoint check (attempt {attempt}/{MaxEndpointCheckAttempts})...");
                await Task.Delay(TimeSpan.FromSeconds(2));
            }

            _postgresBaseConnectionString = BuildConnectionString(PostgresPort, MaintenanceDatabaseName);
            WireMockBaseUrl = $"http://127.0.0.1:{WireMockPort}";

            bool[] results = await Task.WhenAll(
                TryPostgresAsync(),
                TryWireMockAsync());

            bool postgresOk = results[0];
            bool wireMockOk = results[1];

            Log($"Fixed endpoint check (attempt {attempt}/{MaxEndpointCheckAttempts}): postgres={postgresOk} wiremock={wireMockOk}");

            if (postgresOk && wireMockOk)
            {
                return true;
            }
        }

        _postgresBaseConnectionString = null;
        WireMockBaseUrl = string.Empty;
        return false;
    }

    private async Task<bool> TryUsePersistentContainerEndpointsAsync()
    {
        int? mappedPostgresPort = TryGetPublishedPort(PostgresContainerName, "5432/tcp");
        int? mappedWireMockPort = TryGetPublishedPort(WireMockContainerName, "8080/tcp");

        Log($"Persistent container port discovery — postgres={mappedPostgresPort?.ToString() ?? "not found"} wiremock={mappedWireMockPort?.ToString() ?? "not found"}");

        if (mappedPostgresPort is null || mappedWireMockPort is null)
        {
            return false;
        }

        _postgresBaseConnectionString = BuildConnectionString(mappedPostgresPort.Value, MaintenanceDatabaseName);
        WireMockBaseUrl = $"http://127.0.0.1:{mappedWireMockPort.Value}";

        bool[] results = await Task.WhenAll(
            TryPostgresAsync(),
            TryWireMockAsync());

        bool postgresOk = results[0];
        bool wireMockOk = results[1];

        Log($"Persistent container endpoint check: postgres={postgresOk} wiremock={wireMockOk}");

        if (postgresOk && wireMockOk)
        {
            return true;
        }

        _postgresBaseConnectionString = null;
        WireMockBaseUrl = string.Empty;
        return false;
    }

    private async Task WaitUntilPostgresAcceptsConnectionsAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (await TryPostgresAsync())
            {
                return;
            }

            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
        }
    }

    private async Task<bool> TryWireMockAsync()
    {
        if (string.IsNullOrWhiteSpace(WireMockBaseUrl))
        {
            return false;
        }

        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            using HttpResponseMessage response = await http.GetAsync($"{WireMockBaseUrl}/__admin/health");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private static string BuildConnectionString(int port, string databaseName)
    {
        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = "127.0.0.1",
            Port = port,
            Database = databaseName,
            Username = "postgres",
            Password = PostgresPassword,
            IncludeErrorDetail = true,
            // Disable SSL to avoid negotiation hangs against the plain test postgres container.
            SslMode = SslMode.Disable
        };

        return builder.ConnectionString;
    }

    private static int? TryGetPublishedPort(string containerName, string containerPort)
    {
        foreach (string containerRuntime in new[] { "podman", "docker" })
        {
            string? output = TryRunCommand(containerRuntime, "port", containerName, containerPort);
            if (string.IsNullOrWhiteSpace(output))
            {
                continue;
            }

            string line = output
                .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .FirstOrDefault() ?? string.Empty;

            int separatorIndex = line.LastIndexOf(':');
            if (separatorIndex < 0)
            {
                continue;
            }

            string portValue = line[(separatorIndex + 1)..];
            if (int.TryParse(portValue, out int parsedPort))
            {
                return parsedPort;
            }
        }

        return null;
    }

    private static string? TryRunCommand(string fileName, params string[] arguments)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            foreach (string argument in arguments)
            {
                process.StartInfo.ArgumentList.Add(argument);
            }

            if (!process.Start())
            {
                return null;
            }

            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(2000);

            return process.ExitCode == 0 ? output.Trim() : null;
        }
        catch
        {
            return null;
        }
    }

    private void Log(string message)
    {
        try
        {
            _output?.WriteLine($"[AspireFixture {DateTime.UtcNow:HH:mm:ss.fff}] {message}");
        }
        catch (InvalidOperationException)
        {
            // Output helper is no longer active (test has ended).
        }
    }

    private static string LogPostgresAddress(string? connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return "(none)";
        }

        try
        {
            var b = new NpgsqlConnectionStringBuilder(connectionString);
            return $"{b.Host}:{b.Port}/{b.Database}";
        }
        catch
        {
            return "(unparseable)";
        }
    }
}

[CollectionDefinition("Aspire")]
public sealed class AspireCollection : ICollectionFixture<AspireFixture>;
