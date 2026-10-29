using Aspire.Hosting;
using Aspire.Hosting.ApplicationModel;

namespace Project.TestFramework.Aspire;

internal static class DistributedApplicationBuilderExtensions
{
    internal static void AddProjectTestDependencies(this IDistributedApplicationBuilder builder)
    {
        var postgresPassword = builder.AddParameter(
            "postgres-password",
            ProjectTestEnvironment.PostgresPassword,
            secret: true);

        builder.AddPostgresDependency(postgresPassword);
        builder.AddRedisDependency();
        builder.AddWireMockDependency();
    }

    private static void AddPostgresDependency(
        this IDistributedApplicationBuilder builder,
        IResourceBuilder<ParameterResource> postgresPassword)
    {
        var postgres = builder.AddPostgres("postgres", password: postgresPassword, port: ProjectTestEnvironment.PostgresPort)
            .WithContainerName(ProjectTestEnvironment.PostgresContainerName)
            .WithContainerRuntimeArgs(
                "--label", $"com.docker.compose.project={ProjectTestEnvironment.DockerDesktopGroupName}",
                "--label", $"com.docker.compose.service={ProjectTestEnvironment.PostgresContainerName}")
            .WithLifetime(ContainerLifetime.Persistent);

        postgres.AddDatabase("app-component");
        postgres.AddDatabase("app-integration");
        postgres.AddDatabase("infra-component");
        postgres.AddDatabase("infra-integration");
        postgres.AddDatabase("host-integration");
    }

    private static void AddRedisDependency(this IDistributedApplicationBuilder builder)
    {
        builder.AddRedis("redis", port: ProjectTestEnvironment.RedisPort)
            .WithContainerName(ProjectTestEnvironment.RedisContainerName)
            .WithContainerRuntimeArgs(
                "--label", $"com.docker.compose.project={ProjectTestEnvironment.DockerDesktopGroupName}",
                "--label", $"com.docker.compose.service={ProjectTestEnvironment.RedisContainerName}")
            .WithLifetime(ContainerLifetime.Persistent);
    }

    private static void AddWireMockDependency(this IDistributedApplicationBuilder builder)
    {
        builder.AddContainer("wiremock", "wiremock/wiremock")
            .WithHttpEndpoint(port: ProjectTestEnvironment.WireMockPort, targetPort: 8080)
            .WithContainerName(ProjectTestEnvironment.WireMockContainerName)
            .WithContainerRuntimeArgs(
                "--label", $"com.docker.compose.project={ProjectTestEnvironment.DockerDesktopGroupName}",
                "--label", $"com.docker.compose.service={ProjectTestEnvironment.WireMockContainerName}")
            .WithLifetime(ContainerLifetime.Persistent);
    }
}
