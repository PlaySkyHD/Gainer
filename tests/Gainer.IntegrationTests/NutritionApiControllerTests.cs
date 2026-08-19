using Gainer.Api.Controllers;
using Gainer.Contracts.Nutrition;
using Gainer.Core.Nutrition;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using Gainer.Api.Composition;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class NutritionApiControllerTests
{
    [TestMethod]
    public async Task FoodEndpointsAreAuthenticatedBoundedAndReturnStableProviderErrors()
    {
        Assert.IsNotNull(typeof(FoodCatalogController).GetCustomAttributes(typeof(AuthorizeAttribute), true).SingleOrDefault());
        var catalog = new StubCatalog(new FoodCatalogProduct(
            "12345678", "Oats", "Brand", 100m, new NutritionPer100Grams(370m, 13m, 60m, 7m),
            [], new DateTime(2026, 8, 19, 12, 0, 0, DateTimeKind.Utc), false));
        var controller = WithHttpContext(new FoodCatalogController(catalog));

        FoodCatalogProductResponse product = Value(await controller.Barcode("12345678"));
        Assert.AreEqual("Oats", product.ProductName);
        Assert.AreEqual(370m, product.KilocaloriesPer100Grams);
        Assert.IsNull(catalog.LastSearch);

        ActionResult<FoodCatalogSearchResponse> invalid = await controller.Search("x", 1, 10);
        ValidationProblemDetails validation = (ValidationProblemDetails)((ObjectResult)invalid.Result!).Value!;
        Assert.IsTrue(validation.Errors.ContainsKey("query"));

        var failureController = WithHttpContext(new FoodCatalogController(
            new StubCatalog(new FoodCatalogException("provider_rate_limited", "later", true, 429))));
        ObjectResult failure = (ObjectResult)(await failureController.Search("oats", 1, 10)).Result!;
        Assert.AreEqual(StatusCodes.Status429TooManyRequests, failure.StatusCode);
        Assert.AreEqual("provider_rate_limited", ((ProblemDetails)failure.Value!).Extensions["code"]);
    }

    [TestMethod]
    public async Task NutritionDayAndRecentContractsContainNoUserIdentifierAndRepresentEmptyDay()
    {
        Assert.IsNotNull(typeof(NutritionController).GetCustomAttributes(typeof(AuthorizeAttribute), true).SingleOrDefault());
        DateOnly date = new(2026, 8, 19);
        var controller = new NutritionController(new StubNutritionQueries(null, []));

        NutritionDayResponse empty = Value(await controller.Day(date));

        Assert.IsNull(empty.NutritionDayId);
        Assert.AreEqual(date, empty.LocalDate);
        Assert.AreEqual(0m, empty.Totals.Kilocalories);
        Assert.HasCount(0, empty.Entries);
        Assert.IsFalse(typeof(NutritionDayResponse).GetProperties().Any(property => property.Name == "UserId"));
        Assert.IsFalse(typeof(FoodCatalogProductResponse).GetProperties().Any(property => property.Name == "UserId"));
    }

    [TestMethod]
    public async Task NutritionResponsesPreserveMealSnapshotSourceAndMissingMacros()
    {
        DateOnly date = new(2026, 8, 19);
        var entry = new NutritionEntrySnapshot(
            Guid.NewGuid(), MealType.Breakfast, 0, "Oats", null, 150m,
            new NutritionTotals(555m, 19.5m, null, 10.5m),
            new NutritionPer100Grams(370m, 13m, null, 7m),
            new NutritionSourceSnapshot("Open Food Facts", "12345678", DateTime.UtcNow, 100m));
        var day = new NutritionDaySnapshot(
            Guid.NewGuid(), date, [entry], entry.Totals, DateTime.UtcNow, DateTime.UtcNow, 1);
        var controller = new NutritionController(new StubNutritionQueries(day, [entry]));

        NutritionDayResponse response = Value(await controller.Day(date));
        RecentNutritionEntriesResponse recent = Value(await controller.Recent(10));

        Assert.AreEqual("Breakfast", response.Entries.Single().Meal);
        Assert.IsNull(response.Entries.Single().Totals.CarbohydrateGrams);
        Assert.AreEqual("Open Food Facts", response.Entries.Single().Source?.Provider);
        Assert.AreEqual(entry.EntryId, recent.Entries.Single().EntryId);
    }

    [TestMethod]
    public async Task HttpPipelineRequiresAuthenticationAndKeepsTwoUsersIsolated()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.GetTestClient();
        Assert.AreEqual(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/nutrition/days/2026-08-19")).StatusCode);

        Guid firstUser = Guid.NewGuid();
        Guid secondUser = Guid.NewGuid();
        client.DefaultRequestHeaders.Add("X-Test-User", firstUser.ToString());
        NutritionDayResponse first = (await client.GetFromJsonAsync<NutritionDayResponse>(
            $"/api/v1/nutrition/days/2026-08-19?userId={secondUser}"))!;
        client.DefaultRequestHeaders.Remove("X-Test-User");
        client.DefaultRequestHeaders.Add("X-Test-User", secondUser.ToString());
        NutritionDayResponse second = (await client.GetFromJsonAsync<NutritionDayResponse>(
            $"/api/v1/nutrition/days/2026-08-19?userId={firstUser}"))!;

        Assert.AreEqual(firstUser.ToString(), first.Entries.Single().ProductName);
        Assert.AreEqual(secondUser.ToString(), second.Entries.Single().ProductName);
    }

    private static T Value<T>(ActionResult<T> action) => (T)((OkObjectResult)action.Result!).Value!;

    private static T WithHttpContext<T>(T controller) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private static async Task<WebApplication> CreateApplicationAsync()
    {
        WebApplicationBuilder builder = WebApplication.CreateBuilder();
        builder.WebHost.UseTestServer();
        builder.AddGainerApi();
        builder.Services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = "test";
            options.DefaultChallengeScheme = "test";
        }).AddScheme<AuthenticationSchemeOptions, HeaderAuthenticationHandler>("test", _ => { });
        builder.Services.AddSingleton<INutritionQueries, RequestUserNutritionQueries>();
        builder.Services.AddSingleton<IExternalFoodCatalog>(new StubCatalog(new FoodCatalogException("unused", "unused", false)));
        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private sealed class StubCatalog : IExternalFoodCatalog
    {
        private readonly FoodCatalogProduct? product;
        private readonly Exception? exception;
        public StubCatalog(FoodCatalogProduct product) => this.product = product;
        public StubCatalog(Exception exception) => this.exception = exception;
        public string? LastSearch { get; private set; }
        public Task<FoodCatalogProduct> GetByBarcodeAsync(string barcode, CancellationToken cancellationToken = default) =>
            exception is null ? Task.FromResult(product!) : Task.FromException<FoodCatalogProduct>(exception);
        public Task<FoodCatalogSearchResult> SearchAsync(string query, int page, int pageSize, CancellationToken cancellationToken = default)
        {
            LastSearch = query;
            return exception is null
                ? Task.FromResult(new FoodCatalogSearchResult([product!], page, false))
                : Task.FromException<FoodCatalogSearchResult>(exception);
        }
    }

    private sealed class StubNutritionQueries(NutritionDaySnapshot? day, IReadOnlyList<NutritionEntrySnapshot> recent)
        : INutritionQueries
    {
        public Task<NutritionDaySnapshot?> GetDayAsync(DateOnly localDate, CancellationToken cancellationToken = default) => Task.FromResult(day);
        public Task<IReadOnlyList<NutritionEntrySnapshot>> GetRecentEntriesAsync(int limit, CancellationToken cancellationToken = default) => Task.FromResult(recent);
    }

    private sealed class RequestUserNutritionQueries(IHttpContextAccessor accessor) : INutritionQueries
    {
        public Task<NutritionDaySnapshot?> GetDayAsync(DateOnly localDate, CancellationToken cancellationToken = default)
        {
            string user = accessor.HttpContext?.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "missing";
            var entry = new NutritionEntrySnapshot(
                Guid.NewGuid(), MealType.Breakfast, 0, user, null, 100m,
                new NutritionTotals(100m, null, null, null),
                new NutritionPer100Grams(100m, null, null, null), null);
            return Task.FromResult<NutritionDaySnapshot?>(new NutritionDaySnapshot(
                Guid.NewGuid(), localDate, [entry], entry.Totals, DateTime.UtcNow, DateTime.UtcNow, 1));
        }

        public Task<IReadOnlyList<NutritionEntrySnapshot>> GetRecentEntriesAsync(int limit, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<NutritionEntrySnapshot>>([]);
    }

    private sealed class HeaderAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            if (!Request.Headers.TryGetValue("X-Test-User", out var values) ||
                !Guid.TryParse(values.SingleOrDefault(), out Guid userId))
            {
                return Task.FromResult(AuthenticateResult.NoResult());
            }
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, userId.ToString())], Scheme.Name);
            return Task.FromResult(AuthenticateResult.Success(
                new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name)));
        }
    }
}
