---
description: 'Guidelines for building C# applications'
applyTo: '**/*.cs'
---

# C# Development

## C# Instructions
- Always use the latest version of C#, currently C# 14 features.
- Prefer self-explanatory code and intention-revealing names over routine comments.

## General Instructions
- Make only high-confidence suggestions when reviewing code changes.
- Write code with good maintainability practices.
- Handle edge cases and write clear exception handling.

## Naming Conventions

- Follow PascalCase for component names, method names, and public members.
- Use camelCase for private fields and local variables.
- Prefix interface names with "I" (e.g., `IUserService`).

## Formatting

- Apply code-formatting style defined in `.editorconfig`.
- Prefer file-scoped namespace declarations and single-line using directives.
- Insert a newline before the opening curly brace of any code block (e.g., after `if`, `for`, `while`, `foreach`, `using`, `try`, etc.).
- Ensure that the final return statement of a method is on its own line.
- Use pattern matching and switch expressions wherever possible.
- Use `nameof` instead of string literals when referring to member names.
- Ensure that XML doc comments are created for any public APIs. When applicable, include `<example>` and `<code>` documentation in the comments.

## Project Setup and Structure

- Guide users through creating a new .NET project with the appropriate templates.
- Explain the purpose of each generated file and folder to build understanding of the project structure.
- Demonstrate how to organize code using feature folders or domain-driven design principles.
- Show proper separation of concerns with models, services, and data access layers.
- Explain the Program.cs and configuration system in ASP.NET Core 10 including environment-specific settings.

## Nullable Reference Types

- Declare variables non-nullable, and check for `null` at entry points.
- Always use `is null` or `is not null` instead of `== null` or `!= null`.
- Trust the C# null annotations and don't add null checks when the type system says a value cannot be null.

## Data Access

- Do not use Entity Framework Core, Dapper, or other ORMs — they are not part of this stack.
- Always use SDKs or ADO.NET with parameterized queries for data access.
- Use `using` statements or `await using` for proper disposal of database connections and commands.
- For SQL Server, use `SqlConnection`, `SqlCommand`, and `SqlDataReader` with parameterized queries to prevent SQL injection.
- For Azure Table Storage, use `TableServiceClient` and `TableClient` from the Azure SDK, and follow best practices for query construction and pagination.

## Azure SDKs

The team uses Azure SDKs extensively.

Register Azure SDK clients using Aspire integration extensions if Aspire is used, otherwise through `AddAzureClients` or manual `new` instantiation:

```csharp
builder.AddAzureTableServiceClient(connectionName: "TableConnection");
builder.AddAzureServiceBusClient("ServiceBusConnection");
builder.AddAzureKeyVaultClient("KeyVaultConnection", configureSettings: settings => settings.DisableHealthChecks = true);
builder.AddAzureBlobServiceClient("BlobConnection");
```

Inject the SDK clients directly via constructor injection (`TableServiceClient`, `ServiceBusClient`, `BlobServiceClient`, `SecretClient`).

## Dependency Injection

- Use constructor injection exclusively. Prefer C# primary constructors where applicable.
- Register services with the appropriate lifetime:
  - `AddSingleton` for stateless services, factories, and SDK clients.
  - `AddScoped` for per-request services (repositories, domain services).
  - `AddHostedService<T>` for background workers.
- Group related registrations in `IServiceCollection` or `IHostApplicationBuilder` extension methods to keep `Program.cs` focused.
- Use the Options pattern for configuration binding:

```csharp
builder.Services.AddOptions<MssqlOptions>()
    .BindConfiguration(MssqlOptions.MssqlOptionsSection)
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

- Inject `IOptions<T>` (or `IOptionsMonitor<T>` for reloadable config) into consuming classes.

## HttpClient

- Register `IHttpClientFactory` via `AddHttpClient()` in `Program.cs`.
- Configure default resilience and service discovery through Aspire service defaults:

```csharp
builder.Services.ConfigureHttpClientDefaults(http =>
{
    http.AddStandardResilienceHandler();
    http.AddServiceDiscovery();
});
```

- Use `Microsoft.Extensions.Http.Resilience` (`AddStandardResilienceHandler`) for automatic retries, circuit breakers, and timeouts on all HTTP clients.
- Do not create `HttpClient` instances manually with `new HttpClient()`.
- Use typed or named HTTP clients when targeting specific downstream services.

## gRPC

- Use `Grpc.AspNetCore` for hosting gRPC services.
- Define service contracts in `.proto` files under a `Protos/` folder.
- Register gRPC in `Program.cs` with `AddGrpc()` and map services with `MapGrpcService<T>()`.
- Use `AddGrpcHealthChecks()` and `MapGrpcHealthChecksService()` for gRPC health monitoring.
- gRPC service implementations must be `sealed` classes inheriting from the generated base class.

## Authentication and Authorization

- Use `Microsoft.Identity.Web` for Azure AD / Microsoft Entra ID integration.
- Configure authentication in `Program.cs`:

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration, "AzureAd");
```

- Use `AddAuthorizationBuilder()` with named policies:

```csharp
builder.Services.AddAuthorizationBuilder()
    .SetDefaultPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build())
    .AddPolicy(ApiConstants.AdminPolicy, policy => policy.RequireRole("Admin"));
```

- Apply `[Authorize]` attributes and policy-based authorization on controllers.
- Do not reference JWT Bearer setup directly — `Microsoft.Identity.Web` handles this.

## Health Checks

- Register health checks via `AddHealthChecks()` with a self-check tagged `"live"`.
- Expose readiness (`/api/health/isready`) and liveness (`/api/health/isalive`) endpoints.
- Worker services use `FileHealthCheckPublisher` via `AddFileBasedHealthCheckPublisher()` for Kubernetes probe integration.

## Background Services

- Implement long-running workers by inheriting from `BackgroundService`.
- Worker classes must be `sealed`.
- Register with `AddHostedService<T>()`.
- Accept `CancellationToken` in `ExecuteAsync` and respect cancellation throughout.

## Resilience

- Use `Microsoft.Extensions.Http.Resilience` (`AddStandardResilienceHandler`) for HTTP-level resilience applied globally via `ConfigureHttpClientDefaults`. Make sure to use Aspire Service Defaults to apply it to all HTTP clients, if useful in your project.
- Use `SqlConfigurableRetryFactory.CreateExponentialRetryProvider` for SQL Server retry logic.
- Do not add Polly directly — use the `Microsoft.Extensions.Http.Resilience` abstraction instead.

## Validation and Error Handling

- Use `DataAnnotations` for model validation on request DTOs.
- Do not use FluentValidation — it is not part of this stack.
- Use `IExceptionHandler` implementations with `ProblemDetails` (RFC 9457) for global error handling.
- Exception handlers should be `sealed` classes.

## API Design

- Use MVC controller-based APIs with `[ApiController]` attribute.
- Do not use Minimal APIs — this codebase uses controllers exclusively.
- Use `ApiConstants` and centralized message constants for response messages.

## Logging

- Use `ILogger<T>` with `LoggerMessage` source generation for high-performance structured logging.
- Do not use Serilog, NLog, or other third-party logging providers — the built-in provider is the standard.
- Define log messages using `[LoggerMessage]` partial methods.

## Testing

- Use MSTest (`[TestClass]`, `[TestMethod]`) as the test framework.
- Do not use xUnit or NUnit — they are not part of this stack.
- Use NSubstitute for mocking — do not use Moq.
- Do not emit "Act", "Arrange", or "Assert" comments.
- Copy existing style in nearby files for test method names and capitalization.

## Serialization

- Use `System.Text.Json` for all JSON serialization.
- Do not use `Newtonsoft.Json` — it is not part of this stack.

## Deployment

- Use multi-stage Dockerfiles with `mcr.microsoft.com/dotnet/sdk` for build and `mcr.microsoft.com/dotnet/aspnet` for runtime.
- The application is deployed via Helm charts to Kubernetes.
