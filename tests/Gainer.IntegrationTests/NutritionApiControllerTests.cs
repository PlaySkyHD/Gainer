using Gainer.Api.Controllers;
using Gainer.Contracts.Nutrition;
using Gainer.Core.Nutrition;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
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
using Gainer.Api.Security;
using Gainer.Contracts.Security;

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
        var controller = Controller(new StubNutritionQueries(null, []), StubSmartNutritionQueries.Empty);

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
        var target = NutritionTargetVersionDraft.Create(
            Guid.NewGuid(), date, 500m, 150m, 250m, 60m,
            NutritionTargetOrigin.Manual, null, null);
        var controller = Controller(
            new StubNutritionQueries(day, [entry]),
            new StubSmartNutritionQueries([], null, null, target));

        NutritionDayResponse response = Value(await controller.Day(date));
        RecentNutritionEntriesResponse recent = Value(await controller.Recent(10));

        Assert.AreEqual("Breakfast", response.Entries.Single().Meal);
        Assert.IsNull(response.Entries.Single().Totals.CarbohydrateGrams);
        Assert.AreEqual("Open Food Facts", response.Entries.Single().Source?.Provider);
        Assert.AreEqual(entry.EntryId, recent.Entries.Single().EntryId);
        Assert.AreEqual(-55m, response.Progress?.Kilocalories.RemainingOrOver);
        Assert.IsTrue(response.Progress?.Kilocalories.IsComplete);
        Assert.IsFalse(response.Progress?.Carbohydrates.IsComplete);
    }

    [TestMethod]
    public async Task SmartNutritionQueriesReturnStableEmptyStatesAndOrderedSnapshots()
    {
        Guid mealId = Guid.NewGuid();
        var component = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 0, "Oats", 100m,
            new NutritionPer100Grams(370m, 13m, 60m, 7m));
        var meal = new ReusableMealSnapshot(
            mealId, "Breakfast", null, 1m, ReusableMealStatus.Active, [component],
            DateTime.UtcNow, DateTime.UtcNow, 1);
        var target = NutritionTargetVersionDraft.Create(
            Guid.NewGuid(), new DateOnly(2026, 8, 1), 2500m, 180m, 300m, 65m,
            NutritionTargetOrigin.Manual, null, null);
        var smart = new StubSmartNutritionQueries([meal], meal, null, target);
        var controller = Controller(new StubNutritionQueries(null, []), smart);

        ReusableMealsResponse meals = Value(await controller.ReusableMeals());
        ReusableMealResponse detail = Value(await controller.ReusableMealById(mealId));
        NutritionTargetScheduleResponse schedule = Value(await controller.TargetSchedule());
        EffectiveNutritionTargetResponse effective = Value(await controller.EffectiveTarget(new DateOnly(2026, 8, 19)));

        Assert.AreEqual("Breakfast", meals.Meals.Single().Name);
        Assert.AreEqual("Oats", detail.Components.Single().Name);
        Assert.IsNull(schedule.NutritionTargetScheduleId);
        Assert.HasCount(0, schedule.Versions);
        Assert.AreEqual(2500m, effective.Target?.Kilocalories);
        Assert.IsFalse(typeof(ReusableMealResponse).GetProperties().Any(property => property.Name == "UserId"));
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

    [TestMethod]
    public async Task MealEstimateHttpEndpointRequiresAuthenticationConsentAndBoundedSingleImage()
    {
        var estimator = new StubMealEstimator();
        await using WebApplication app = await CreateApplicationAsync(estimator);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri("https://localhost");
        using var anonymous = new MultipartFormDataContent { { new StringContent("oats"), "text" } };
        using var anonymousRequest = MealEstimateRequest(anonymous);
        Assert.AreEqual(HttpStatusCode.Unauthorized, (await client.SendAsync(anonymousRequest)).StatusCode);

        client.DefaultRequestHeaders.Add("X-Test-User", Guid.NewGuid().ToString());
        using var textOnly = new MultipartFormDataContent { { new StringContent("oats"), "text" } };
        using HttpResponseMessage success = await client.SendAsync(MealEstimateRequest(textOnly));
        Assert.AreEqual(HttpStatusCode.OK, success.StatusCode, await success.Content.ReadAsStringAsync());
        Assert.IsTrue(success.Headers.CacheControl?.NoStore);
        Assert.IsTrue(success.Headers.CacheControl?.Private);
        Assert.AreEqual(1, estimator.Calls);

        using var missingConsent = new MultipartFormDataContent();
        missingConsent.Add(new ByteArrayContent([0x89, 0x50, 0x4E, 0x47]), "image", "meal.png");
        using HttpResponseMessage consentFailure = await client.SendAsync(MealEstimateRequest(missingConsent));
        Assert.AreEqual(HttpStatusCode.BadRequest, consentFailure.StatusCode);
        Assert.AreEqual("image_consent_required", (await consentFailure.Content.ReadFromJsonAsync<ProblemDetails>())!.Extensions["code"]?.ToString());
        Assert.AreEqual(1, estimator.Calls);

        using var multipleImages = new MultipartFormDataContent();
        multipleImages.Add(new ByteArrayContent([1]), "image", "first.png");
        multipleImages.Add(new ByteArrayContent([2]), "otherImage", "second.png");
        multipleImages.Add(new StringContent("true"), "imageConsent");
        using HttpResponseMessage multipleFailure = await client.SendAsync(MealEstimateRequest(multipleImages));
        Assert.AreEqual(HttpStatusCode.BadRequest, multipleFailure.StatusCode);
        Assert.AreEqual("too_many_images", (await multipleFailure.Content.ReadFromJsonAsync<ProblemDetails>())!.Extensions["code"]?.ToString());

        using var oversized = new MultipartFormDataContent();
        oversized.Add(new ByteArrayContent(new byte[(8 * 1024 * 1024) + 1]), "image", "large.png");
        oversized.Add(new StringContent("true"), "imageConsent");
        using HttpResponseMessage sizeFailure = await client.SendAsync(MealEstimateRequest(oversized));
        Assert.AreEqual(HttpStatusCode.RequestEntityTooLarge, sizeFailure.StatusCode);
        Assert.AreEqual(1, estimator.Calls, "Rejected requests and returned drafts must not create persisted estimate state.");
    }

    private static HttpRequestMessage MealEstimateRequest(HttpContent content) =>
        new(HttpMethod.Post, "/api/v1/nutrition/meal-estimates") { Content = content };

    private static T Value<T>(ActionResult<T> action) => (T)((OkObjectResult)action.Result!).Value!;

    private static T WithHttpContext<T>(T controller) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private static async Task<WebApplication> CreateApplicationAsync(IMealEstimator? estimator = null)
    {
        WebApplicationBuilder builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.AddGainerApi();
        builder.Services.AddDataProtection().UseEphemeralDataProtectionProvider();
        builder.Services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = "test";
            options.DefaultChallengeScheme = "test";
        }).AddScheme<AuthenticationSchemeOptions, HeaderAuthenticationHandler>("test", _ => { });
        builder.Services.AddSingleton<INutritionQueries, RequestUserNutritionQueries>();
        builder.Services.AddSingleton<ISmartNutritionQueries>(StubSmartNutritionQueries.Empty);
        builder.Services.AddSingleton<IMealEstimator>(estimator ?? new StubMealEstimator());
        builder.Services.AddSingleton<IExternalFoodCatalog>(new StubCatalog(new FoodCatalogException("unused", "unused", false)));
        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private static NutritionController Controller(
        INutritionQueries queries,
        ISmartNutritionQueries smart,
        IMealEstimator? estimator = null) => WithHttpContext(new NutritionController(
            queries, smart, estimator ?? new StubMealEstimator()));

    private sealed class StubMealEstimator : IMealEstimator
    {
        public int Calls { get; private set; }

        public Task<MealEstimateDraft> EstimateAsync(MealEstimationInput input, CancellationToken cancellationToken = default)
        {
            Calls++;
            return Task.FromResult(MealEstimateDraft.Create(
                [MealEstimateComponentDraft.Create("Oats", 100m, 370m, 13m, 60m, 7m, MealEstimateConfidence.Medium, [])],
                "test", "v1", DateTime.SpecifyKind(new DateTime(2026, 8, 19), DateTimeKind.Utc)));
        }
    }

    private sealed class StubSmartNutritionQueries(
        IReadOnlyList<ReusableMealSnapshot> meals,
        ReusableMealSnapshot? meal,
        NutritionTargetScheduleSnapshot? schedule,
        NutritionTargetVersionDraft? effective) : ISmartNutritionQueries
    {
        public static StubSmartNutritionQueries Empty { get; } = new([], null, null, null);

        public Task<IReadOnlyList<ReusableMealSnapshot>> GetReusableMealsAsync(bool includeArchived, CancellationToken cancellationToken = default) =>
            Task.FromResult(meals);

        public Task<ReusableMealSnapshot?> GetReusableMealAsync(Guid reusableMealId, CancellationToken cancellationToken = default) =>
            Task.FromResult(meal?.ReusableMealId == reusableMealId ? meal : null);

        public Task<NutritionTargetScheduleSnapshot?> GetNutritionTargetScheduleAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(schedule);

        public Task<NutritionTargetVersionDraft?> GetEffectiveNutritionTargetAsync(DateOnly localDate, CancellationToken cancellationToken = default) =>
            Task.FromResult(effective);
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
