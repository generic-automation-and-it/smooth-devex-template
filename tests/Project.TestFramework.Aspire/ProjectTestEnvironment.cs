namespace Project.TestFramework.Aspire;

public static class ProjectTestEnvironment
{
    public const string DockerDesktopGroupName = "project";

    public const string PostgresPassword = "LocalMachineAccessNoInterestingDataTestDev#Passw0rd!FirewallNotExposed";

    public const string PostgresContainerName = "project-test-postgres";
    public const string RedisContainerName = "project-test-redis";
    public const string WireMockContainerName = "project-test-wiremock";

    public const int PostgresPort = 15432;
    public const int RedisPort = 16379;
    public const int WireMockPort = 19091;
}
