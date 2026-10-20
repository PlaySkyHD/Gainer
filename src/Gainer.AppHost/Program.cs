var builder = DistributedApplication.CreateBuilder(args);
var openFoodFactsContactEmail = builder.AddParameter("openfoodfacts-contact-email");

if (builder.ExecutionContext.IsPublishMode)
{
    builder.AddDockerComposeEnvironment("compose").WithDashboard(false);
    var productionPostgres = builder
        .AddPostgres("postgres")
        .WithDataVolume("gainer-postgres-data");
    var productionDatabase = productionPostgres.AddDatabase("gainer-db");
    var migrator = builder
        .AddDockerfile("migrator", "../..", "deploy/Dockerfile.migrator")
        .WithReference(productionDatabase)
        .WaitFor(productionDatabase);
    var productionApi = builder
        .AddDockerfile("api", "../..", "deploy/Dockerfile.api")
        .WithHttpEndpoint(targetPort: 8080, name: "http")
        .WithEnvironment("OpenFoodFacts__ContactEmail", openFoodFactsContactEmail)
        .WithEnvironment("MealEstimation__DailyRequestsPerUser", "20")
        .WithEnvironment("MealEstimation__MaximumConcurrentRequests", "2")
        .WithHttpHealthCheck("/health/ready")
        .WithReference(productionDatabase)
        .WaitForCompletion(migrator);
    builder
        .AddDockerfile("edge", "../..", "deploy/Dockerfile.edge")
        .WithHttpEndpoint(targetPort: 80, name: "http")
        .WaitFor(productionApi)
        .WithExternalHttpEndpoints();
    await builder.Build().RunAsync();
    return;
}

var postgres = builder
    .AddPostgres("postgres")
    .WithDataVolume("gainer-postgres-data");

var database = postgres.AddDatabase("gainer-db");

var backupBlobs = builder
    .AddAzureStorage("backup-storage")
    .RunAsEmulator(emulator => emulator
        .WithDataVolume("gainer-azurite-data")
        .WithLifetime(ContainerLifetime.Persistent))
    .AddBlobs("backup-blobs");

builder
    .AddProject<Projects.Gainer_Api>("api")
    .WithReference(database)
    .WithEnvironment("OpenFoodFacts__ContactEmail", openFoodFactsContactEmail)
    .WithEnvironment("MealEstimation__DailyRequestsPerUser", "20")
    .WithEnvironment("MealEstimation__MaximumConcurrentRequests", "2")
    .WaitFor(database)
    .WithExternalHttpEndpoints();

_ = backupBlobs;

await builder.Build().RunAsync();
