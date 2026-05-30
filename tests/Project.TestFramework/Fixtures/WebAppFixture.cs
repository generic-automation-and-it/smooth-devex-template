using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace Project.TestFramework.Fixtures;

/// <summary>
/// Generic in-process web-host fixture built on <see cref="WebApplicationFactory{TProgram}"/>.
/// Close it for a Host's entry point in an integration test, e.g.
/// <c>public sealed class HostWebAppFixture : WebAppFixture&lt;Program&gt;;</c>
/// Domain-agnostic by design — derive and override the hooks below to add database, cache,
/// or external-service wiring when a project needs it.
/// </summary>
public abstract class WebAppFixture<TProgram> : IAsyncLifetime
    where TProgram : class
{
    private WebApplicationFactory<TProgram>? _factory;

    public HttpClient HttpClient { get; private set; } = default!;

    public IServiceProvider Services { get; private set; } = default!;

    /// <summary>Configuration values layered over appsettings for the test host.</summary>
    protected virtual IReadOnlyDictionary<string, string?> ConfigurationOverrides =>
        new Dictionary<string, string?>();

    /// <summary>When true, hosted/background services are removed so they don't run during tests.</summary>
    protected virtual bool RemoveHostedServices => true;

    public ValueTask InitializeAsync()
    {
        _factory = new WebApplicationFactory<TProgram>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration((_, configuration) =>
                    configuration.AddInMemoryCollection(ConfigurationOverrides));

                builder.ConfigureServices(services =>
                {
                    if (RemoveHostedServices)
                    {
                        services.RemoveAll<IHostedService>();
                    }
                });
            });

        HttpClient = _factory.CreateClient();
        Services = _factory.Services;

        return ValueTask.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        HttpClient?.Dispose();

        if (_factory is not null)
        {
            await _factory.DisposeAsync();
        }
    }
}
