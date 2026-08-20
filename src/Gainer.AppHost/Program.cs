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
    builder.Build().Run();
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

var web = builder
    .AddJavaScriptApp("web", "../../apps/web", "dev")
    .WithHttpEndpoint(targetPort: 3000, env: "PORT");

var api = builder
    .AddProject<Projects.Gainer_Api>("api")
    .WithReference(database)
    .WithEnvironment("OpenFoodFacts__ContactEmail", openFoodFactsContactEmail)
    .WithEnvironment("MealEstimation__DailyRequestsPerUser", "20")
    .WithEnvironment("MealEstimation__MaximumConcurrentRequests", "2")
    .WithEnvironment("Security__FrontendOrigin", web.GetEndpoint("http"))
    .WaitFor(database);

_ = backupBlobs;

web
    .WithReference(api)
    .WithEnvironment("NEXT_PUBLIC_API_BASE_URL", api.GetEndpoint("http"))
    .WaitFor(api)
    .WithExternalHttpEndpoints();

builder.Build().Run();
