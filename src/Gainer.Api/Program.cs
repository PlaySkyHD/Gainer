using System.Net;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.HealthChecks;
using Gainer.Infrastructure.Persistence;
using Gainer.ServiceDefaults;

if (args.Contains("--health-check", StringComparer.Ordinal))
{
    string defaultHealthCheckUrl = new UriBuilder(Uri.UriSchemeHttp, IPAddress.Loopback.ToString(), 8080, "health/live").Uri.ToString();
    using var healthClient = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };
    using HttpResponseMessage response = await healthClient.GetAsync(
        Environment.GetEnvironmentVariable("GAINER_HEALTHCHECK_URL") ?? defaultHealthCheckUrl);
    Environment.ExitCode = response.IsSuccessStatusCode ? 0 : 1;
    return;
}

var builder = WebApplication.CreateBuilder(args);
builder.AddGainerServiceDefaults();
builder.AddGainerApi();
builder.AddGainerPersistence();
builder.AddGainerIdentity();
builder.Services.AddGainerDatabaseReadiness(GainerHealthCheckTags.Ready);
var app = builder.Build();

if (InitialAccountOperatorProvisioning.IsRequested(args))
{
    await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
    IInitialAccountOperatorProvisioner provisioner = scope.ServiceProvider
        .GetRequiredService<IInitialAccountOperatorProvisioner>();
    InitialAccountOperatorProvisioningResult result = await provisioner.ProvisionAsync();
    if (app.Logger.IsEnabled(LogLevel.Information))
    {
        app.Logger.LogInformation("Initial account-operator provisioning completed with result {Result}.", result);
    }
    return;
}

app.MapGainerApi();
app.MapGainerHealthEndpoints();

await app.RunAsync();
