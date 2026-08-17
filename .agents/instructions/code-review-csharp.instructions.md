---
description: 'C# and .NET 10 specific code review instructions. Supplements the generic code review with language-specific checks for MVC APIs, MSTest, NSubstitute, Azure SDKs, and established project patterns.'
applyTo: '**/*.cs'
excludeAgent: ["coding-agent"]
---

# C# / .NET 10 Code Review Instructions

Language-specific code review guidelines for C# projects targeting .NET 10. These instructions supplement the generic code review file with checks tailored to the patterns, frameworks, and conventions verified in our codebase.

## Tech Stack Summary

- **Framework**: .NET 10, C# 14
- **API Style**: ASP.NET Core MVC with `[ApiController]` — **no Minimal APIs**
- **Testing**: MSTest, NSubstitute
- **Data Access**:  Use SDKs, e.g. Azure.Data.Tables, gRPC client, directly and exclusively — **no EF Core, no Dapper**
- **Serialization**: System.Text.Json (primary)
- **Error Handling**: `IExceptionHandler` + `ProblemDetails`
- **DI**: Constructor injection (prefer C# primary constructors where applicable)
- **Logging**: `ILogger<T>` via Microsoft.Extensions.Logging
- **Nullable**: Enabled for production projects (test projects may differ)

## Precedence

These code review instructions take precedence over general C# development instructions (e.g., `csharp.instructions.md`) when reviewing PRs. The development instructions describe broader .NET capabilities; this file describes the patterns actually used in this repository.

---

## ASP.NET Core MVC

When performing a code review, check MVC controller patterns:

- Controllers **must** use `[ApiController]` and `[Route]` attributes
- Use `[HttpGet]`, `[HttpPost]`, `[HttpPut]`, `[HttpDelete]` route attributes on action methods
- Return `ActionResult<T>` or `IActionResult` from action methods
- Use `AddControllers()` and `MapControllers()` in `Program.cs` — **never** `MapGet`/`MapPost` minimal API patterns
- Apply `[FromBody]`, `[FromQuery]`, `[FromRoute]` for explicit model binding

```csharp
// ❌ BAD: Minimal API pattern (not used in our codebase)
app.MapGet("/api/items/{id}", (int id) => Results.Ok(item));

// ✅ GOOD: MVC controller pattern
[ApiController]
[Route("api/[controller]")]
public class ItemsController : ControllerBase
{
    [HttpGet("{id}")]
    public async Task<ActionResult<ItemDto>> GetItem(int id)
    {
        // ...
    }
}
```

---

## Error Handling

When performing a code review, verify error handling follows the established pattern:

- Use typed `IExceptionHandler` implementations registered in DI
- Use `AddProblemDetails()` for standardized error responses
- Call `app.UseExceptionHandler()` in the middleware pipeline
- **Do not** use try-catch in controllers for error-to-response mapping (e.g., catching `NotFoundException` and returning `NotFound()`). The existing pattern of try-catch for logging + rethrow (`catch (Exception ex) { _logger...; throw; }`) is acceptable
- Each exception type should have a dedicated handler (e.g., `BadRequestExceptionHandler`, `NotFoundExceptionHandler`, `ConflictExceptionHandler`)

```csharp
// ❌ BAD: Try-catch in controller for error-to-response mapping
[HttpGet("{id}")]
public async Task<ActionResult<ItemDto>> GetItem(int id)
{
    try
    {
        ItemDto item = await _service.GetItemAsync(id);
        return Ok(item);
    }
    catch (NotFoundException ex)
    {
        return NotFound(ex.Message);
    }
}

// ✅ GOOD: Let IExceptionHandler handle it
[HttpGet("{id}")]
public async Task<ActionResult<ItemDto>> GetItem(int id)
{
    ItemDto item = await _service.GetItemAsync(id);
    return Ok(item);
}
// The registered NotFoundExceptionHandler converts NotFoundException to ProblemDetails
```

---

## Nullable Reference Types

When performing a code review, verify NRT usage:

- `<Nullable>enable</Nullable>` is standard for production projects — test projects may differ
- Annotate return types and parameters correctly with `?` for nullable
- **Do not** abuse the null-forgiving operator (`!`) to suppress warnings
- Use null-conditional (`?.`) and null-coalescing (`??`) operators appropriately
- Prefer guard clauses with `ArgumentNullException.ThrowIfNull()` over manual null checks

```csharp
// ❌ BAD: Suppressing nullable warnings
var name = user.Name!; // Hiding potential null issue

// ✅ GOOD: Proper null handling
ArgumentNullException.ThrowIfNull(user);
string name = user.Name ?? "Unknown";
```

---

## Records for DTOs

When performing a code review, check DTO definitions:

- **Prefer `record` types** for DTOs, models, and value objects — this is the codebase standard
- Use positional records for simple DTOs
- Use `init`-only setters when mutation during construction is needed
- Records provide value equality, immutability, and concise syntax

```csharp
// ❌ BAD: Class-based DTO with mutable properties
public class CustomerDto
{
    public string Name { get; set; }
    public string Email { get; set; }
}

// ✅ GOOD: Record-based DTO (codebase standard)
public record CustomerDto(string Name, string Email);
```

---

## Async/Await Patterns

When performing a code review, check async patterns:

- Use `async Task` for all asynchronous methods — this is the standard pattern
- **Do not** introduce `ValueTask` unless required by a framework interface (e.g., `IExceptionHandler.TryHandleAsync` returns `ValueTask<bool>`). Do not use `IAsyncEnumerable` or `ConfigureAwait(false)` — these are not used in the codebase
- **Never** use `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` — they cause deadlocks
- Suffix async method names with `Async`
- Mark the method `async` only if it uses `await`; otherwise return the `Task` directly

```csharp
// ❌ BAD: Blocking on async
var result = _service.GetItemAsync(id).Result;

// ❌ BAD: Unnecessary async wrapper
public async Task<ItemDto> GetItemAsync(int id)
{
    return await _repository.FindItemAsync(id);
}

// ✅ GOOD: Direct return when no additional await logic
public Task<ItemDto> GetItemAsync(int id)
{
    return _repository.FindItemAsync(id);
}

// ✅ GOOD: async when multiple awaits or logic required
public async Task<ItemDto> GetItemAsync(int id)
{
    Item entity = await _repository.FindItemAsync(id);
    await _auditService.LogAccessAsync(id);
    return entity.ToDto();
}
```

---

## Dependency Injection

When performing a code review, verify DI patterns:

- Use **primary constructor injection** if possible — this is the codebase convention
- Register services with correct lifetimes: `AddScoped`, `AddSingleton`, `AddTransient`
- Keep constructor parameters to a reasonable number (consider splitting if > 5)
- Use `IServiceCollection` extension methods to group registrations

```csharp
// ❌ BAD: Service locator anti-pattern
public class ItemService
{
    public ItemDto GetItem(int id, IServiceProvider provider)
    {
        var repo = provider.GetRequiredService<IItemRepository>();
        return repo.Find(id);
    }
}

// ✅ GOOD: Constructor injection
public class ItemService(IItemRepository repository, ILogger<ItemService> logger)
{
    private readonly IItemRepository _repository = repository;
    private readonly ILogger<ItemService> _logger = logger;
}
```

---

## LINQ

When performing a code review, check LINQ usage:

- Prefer **method syntax** over query syntax — this is the codebase convention
- Do not materialize (`.ToList()`, `.ToArray()`) before filtering — filter first
- Avoid LINQ in hot paths where a simple loop is more performant
- Use collection expressions (`[.. items]`) where appropriate

```csharp
// ❌ BAD: Materializing before filtering
var filtered = items.ToList().Where(x => x.IsActive);

// ✅ GOOD: Filter first, materialize last
IEnumerable<Item> filtered = items.Where(x => x.IsActive).ToList();

// ✅ GOOD: Collection expression (codebase pattern)
return [.. customers.Select(x => x.ConvertToCustomerDto())];
```

---

## gRPC Client Communication

When performing a code review, check non message based communication patterns:

- Prefer gRPC client (via `Grpc.Net.ClientFactory`) to communicate with Java, if available — **no EF Core, no Dapper**
- Use `IHttpClientFactory` for any HTTP-based downstream calls
- Handle gRPC `RpcException` with proper status code mapping
- Use `Microsoft.Identity.Web` for authentication

---

## Azure SDKs

When performing a code review, check data access patterns:

- Use the Microsoft Azure SDKs (e.g., `TableClient` for Azure Table Storage operations) — **no EF Core, no Dapper**; use ADO.NET (`SqlConnection`/`SqlCommand` with explicit `SqlDbType`-typed parameters) for SQL Server access following the established pattern in `Library.Infrastructure/Database/Mssql`
- Use `DefaultAzureCredential` or `ClientSecretCredential` for authentication

### Azure Table Storage access patterns:

- Use proper partition key and row key design for query performance
- Implement paging with `Query<T>()` and continuation tokens for large result sets
- Handle `RequestFailedException` for storage errors

---

## Testing

When performing a code review, verify test quality:

- **Framework**: MSTest — use `[TestClass]`, `[TestMethod]`, `[DataTestMethod]`, `[DataRow]`
- **Mocking**: NSubstitute — use `Substitute.For<T>()` — **not** Moq
- Follow **Arrange-Act-Assert** pattern in all tests
- Test names should describe the scenario and expected outcome
- One assertion concept per test

```csharp
// ❌ BAD: Using Moq (not our standard)
var mock = new Mock<IService>();
mock.Setup(x => x.GetItem(1)).Returns(item);

// ✅ GOOD: Using NSubstitute (codebase standard)
IService service = Substitute.For<IService>();
service.GetItemAsync(1).Returns(item);

// ✅ GOOD: MSTest with clear naming
[TestClass]
public class CustomerServiceTests
{
    [TestMethod]
    public async Task GetCustomer_WithValidId_ReturnsCustomerDto()
    {
        // Arrange
        ICustomerRepository repository = Substitute.For<ICustomerRepository>();
        repository.FindAsync("123").Returns(new CustomerEntity { Id = "123", Name = "Test" });
        CustomerService customerService = new CustomerService(repository);

        // Act
        CustomerDto result = await customerService.GetCustomerAsync("123");

        // Assert
        Assert.IsNotNull(result);
        Assert.AreEqual("Test", result.Name);
    }
}
```

---

## JSON Serialization

When performing a code review, check serialization:

- Use `System.Text.Json` as the primary serializer — **not** Newtonsoft.Json (except existing codebase for legacy reasons)
- Configure `JsonSerializerOptions` via `AddJsonOptions()` in `Program.cs`
- Use `[JsonIgnore]`, `[JsonPropertyName]` attributes from `System.Text.Json.Serialization`
- Use source-generated `JsonSerializerContext` where available

```csharp
// ❌ BAD: Using Newtonsoft.Json in new code
var json = JsonConvert.SerializeObject(dto);

// ✅ GOOD: System.Text.Json
string json = JsonSerializer.Serialize(dto);
```

---

## Logging

When performing a code review, check logging patterns:

- Inject `ILogger<T>` via constructor — do not create loggers manually
- Use structured logging with message templates — **not** string interpolation
- Use appropriate log levels: `Information` for business events, `Warning` for recoverable issues, `Error` for failures
- Use partial methods for high-performance logging where applicable (as in `LogMessages.cs` pattern)

```csharp
// ❌ BAD: String interpolation in log messages (defeats structured logging)
_logger.LogInformation($"Processing item {itemId} for customer {customerId}");

// ✅ GOOD: Source generated structured logging with message templates
_logger.ProcessingItem(itemId, customerId); // Using partial method pattern for structured logging
```

## Validation

When performing a code review, check validation patterns:

- Use `System.ComponentModel.DataAnnotations` attributes on request DTOs (e.g., `[Required]`, `[MaxLength]`, `[Base64String]`) for input validation
- Rely on `[ApiController]` automatic model validation — invalid models return standardized `ProblemDetails` responses
- Validate inputs at service boundaries (controllers, service methods) — do not introduce FluentValidation without team agreement

---

## C# Review Checklist

When performing a code review of C# code, systematically verify:

### API and Architecture
- [ ] Controllers use `[ApiController]` and `[Route]` attributes
- [ ] No minimal API patterns (`MapGet`, `MapPost`, etc.)
- [ ] Error handling uses `IExceptionHandler` + `ProblemDetails`
- [ ] DI uses constructor injection with correct lifetimes, prefer primary constructors

### Language and Types
- [ ] DTOs and models use `record` types
- [ ] Nullable reference types properly annotated (no `!` abuse)
- [ ] Async methods use `async Task` (no `.Result`/`.Wait()`)
- [ ] LINQ uses method syntax, no premature materialization

### Data and Serialization
- [ ] Non message based service-to-service communication uses gRPC client or `IHttpClientFactory`
- [ ] Azure Table Storage access uses `TableClient` with proper patterns
- [ ] JSON uses `System.Text.Json` with message templates
- [ ] Source generated logging patterns used where applicable

### Testing
- [ ] Tests use MSTest (`[TestMethod]`, `[DataTestMethod]`)
- [ ] Mocking uses NSubstitute (`Substitute.For<T>()`)
- [ ] Tests follow Arrange-Act-Assert pattern
- [ ] Descriptive test names

### Security
- [ ] Input validation at service boundaries
- [ ] No hardcoded secrets or connection strings
- [ ] Parameterized queries for any data operations

---

## Repository-Specific Review Patterns

### Datalake Processing and Service Defaults Patterns

When performing a code review in this repository, also verify the following Datalake-specific patterns:

- Logging should preserve the repository's **`LoggerMessage` source-generation model** with shared logging extensions instead of introducing new handwritten message templates in processing paths
- Correlation handling should keep the repository's **middleware plus `ILogEnricher` integration** so correlation IDs appear consistently in traces and structured logs
- Repository code should remain on the established **Azure.Data.Tables-only pattern** with async query iteration and custom exception translation instead of introducing EF Core, Dapper, or direct SQL access
- Background processing should preserve the repository's **sealed `BackgroundService` Service Bus worker pattern** with explicit startup, shutdown, success, and failure logging around message handling
- Service-to-service communication should align with the repository's **service defaults and resilience handler model** so HTTP clients inherit discovery, telemetry, and resilience behavior centrally
- New API exception flows should keep using the repository's **typed sealed `IExceptionHandler` implementations** rather than controller-local error mapping

### Datalake Checklist Additions

- [ ] Processing-path logging uses shared `LoggerMessage` extensions instead of ad-hoc message templates
- [ ] Correlation IDs flow through middleware, `Activity`, and log enrichment consistently
- [ ] Repository implementations remain on Azure Tables with async iteration and translated storage exceptions
- [ ] Service Bus workers follow the repository's sealed background-worker pattern with structured lifecycle logging
- [ ] Service-to-service clients preserve the repository's service-defaults and resilience configuration model
- [ ] API failures continue to use typed sealed exception handlers
