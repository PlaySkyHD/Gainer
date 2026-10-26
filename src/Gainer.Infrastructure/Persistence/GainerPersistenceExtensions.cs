using Microsoft.EntityFrameworkCore;
using Gainer.Core.Access;
using Gainer.Core.BodyTracking;
using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Training;
using Gainer.Core.Sync;
using Gainer.Core.Insights;
using Gainer.Core.Coach;
using Gainer.Infrastructure.Coach;
using Gainer.Infrastructure.Integrations;
using Gainer.Core.Integrations;
using Gainer.Infrastructure.Training;
using Gainer.Infrastructure.Catalog;
using Gainer.Infrastructure.Nutrition;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Registers PostgreSQL persistence for the application.</summary>
public static class GainerPersistenceExtensions
{
    private const string DefaultConnectionName = "gainer-db";
    private const string OpenAiBaseAddress = "https://api.openai.com/";

    /// <summary>Adds the shared application database context.</summary>
    public static IHostApplicationBuilder AddGainerPersistence(
        this IHostApplicationBuilder builder,
        string connectionName = DefaultConnectionName)
    {
        builder.Services.AddSingleton<UtcTimestampInterceptor>();
        builder.Services.AddScoped<UserOwnershipInterceptor>();
        builder.Services.AddScoped<IAccountInvitationService, AccountInvitationService>();
        builder.Services.Configure<DeviceSessionOptions>(
            builder.Configuration.GetSection(DeviceSessionOptions.SectionName));
        builder.Services.AddScoped<IDeviceSessionService, DeviceSessionService>();
        builder.Services.AddScoped<IAccountStatusService, AccountStatusService>();
        builder.Services.AddScoped<IAccountDirectoryService, AccountDirectoryService>();
        builder.Services.AddScoped<IBodyGoalMutationHandler, BodyGoalMutationHandler>();
        builder.Services.AddScoped<IDailyCheckInMutationHandler, DailyCheckInMutationHandler>();
        builder.Services.AddScoped<IBodyTrackingQueries, BodyTrackingQueries>();
        builder.Services.AddScoped<INutritionDayMutationHandler, NutritionDayMutationHandler>();
        builder.Services.AddScoped<INutritionQueries, NutritionQueries>();
        builder.Services.AddScoped<ISmartNutritionQueries, SmartNutritionQueries>();
        builder.Services.AddScoped<IReusableMealMutationHandler, ReusableMealMutationHandler>();
        builder.Services.AddScoped<INutritionDayTemplateMutationHandler, NutritionDayTemplateMutationHandler>();
        builder.Services.AddScoped<IWaterIntakeMutationHandler, WaterIntakeMutationHandler>();
        builder.Services.AddScoped<INutritionTargetScheduleMutationHandler, NutritionTargetScheduleMutationHandler>();
        builder.Services.AddScoped<IExerciseCatalogQueries, ExerciseCatalogQueries>();
        builder.Services.AddScoped<IExerciseResolver, ExerciseCatalogQueries>();
        builder.Services.AddScoped<ICustomExerciseMutationHandler, CustomExerciseMutationHandler>();
        builder.Services.AddScoped<ITrainingPlanMutationHandler, TrainingPlanMutationHandler>();
        builder.Services.AddScoped<ITrainingScheduleMutationHandler, TrainingScheduleMutationHandler>();
        builder.Services.AddScoped<IWorkoutMutationHandler, WorkoutMutationHandler>();
        builder.Services.AddScoped<ICardioSessionMutationHandler, CardioSessionMutationHandler>();
        builder.Services.AddScoped<IWorkoutHistoryQueries, WorkoutHistoryQueries>();
        builder.Services.AddScoped<ISyncMutationExecutor, SyncMutationExecutor>();
        builder.Services.AddScoped<ISyncMutationProcessor, SyncMutationProcessor>();
        builder.Services.AddScoped<ISyncChangeFeed, SyncChangeFeed>();
        builder.Services.AddScoped<IAccountDataExport, AccountDataExportQuery>();
        builder.Services.AddScoped<ISyncClientRegistry, SyncClientRegistry>();
        builder.Services.AddScoped<ISyncHandoverService, SyncHandoverService>();
        builder.Services.AddScoped<IInsightQueries, InsightQueries>();
        builder.Services.Configure<OpenAiProviderOptions>(builder.Configuration.GetSection(OpenAiProviderOptions.SectionName));
        builder.Services.AddHttpClient<IOpenAiResponsesProvider, OpenAiResponsesProvider>(client =>
            client.BaseAddress = new Uri(OpenAiBaseAddress))
            .AddProviderResilience(static services => services.GetRequiredService<IOptions<OpenAiProviderOptions>>().Value.TimeoutSeconds);
        builder.Services.AddScoped<ICoachMemoryStore, CoachMemoryStore>();
        builder.Services.AddScoped<ICoachMemoryQueries>(services => services.GetRequiredService<ICoachMemoryStore>());
        builder.Services.AddScoped<ICoachService, CoachService>();
        builder.Services.Configure<MealEstimationOptions>(builder.Configuration.GetSection(MealEstimationOptions.SectionName));
        builder.Services.Configure<MealImageOptions>(builder.Configuration.GetSection(MealImageOptions.SectionName));
        builder.Services.AddSingleton<IMealEstimationQuota, MealEstimationQuota>();
        builder.Services.AddScoped<IMealImageSanitizer, MealImageSanitizer>();
        builder.Services.AddScoped<IMealEstimator, OpenAiMealEstimator>();
        builder.Services.AddScoped<INutritionLabelScanner, OpenAiNutritionLabelScanner>();
        builder.Services.Configure<MuscleSuggestionOptions>(builder.Configuration.GetSection(MuscleSuggestionOptions.SectionName));
        builder.Services.AddSingleton<IMuscleSuggestionQuota, MuscleSuggestionQuota>();
        builder.Services.AddScoped<IMuscleSuggester, OpenAiMuscleSuggester>();
        builder.Services.Configure<OpenFoodFactsOptions>(builder.Configuration.GetSection(OpenFoodFactsOptions.SectionName));
        builder.Services.TryAddSingleton<OpenFoodFactsCatalogState>();
        builder.Services.AddHttpClient<IExternalFoodCatalog, OpenFoodFactsCatalog>();
        builder.Services.AddScoped<IChangeCollector, ChangeCollector>();
        builder.Services.TryAddScoped<BackgroundUserScope>();
        builder.Services.Configure<StravaOptions>(builder.Configuration.GetSection(StravaOptions.SectionName));
        builder.Services.AddHttpClient<IStravaApiClient, StravaApiClient>()
            .AddProviderResilience(static services => services.GetRequiredService<IOptions<StravaOptions>>().Value.TimeoutSeconds);
        builder.Services.TryAddSingleton<StravaExportSignal>();
        builder.Services.AddScoped<StravaTokenVault>();
        builder.Services.AddScoped<IStravaIntegrationService, StravaIntegrationService>();
        builder.Services.AddScoped<StravaExportProcessor>();
        builder.Services.AddDbContext<AppDbContext>((serviceProvider, options) =>
        {
            string connectionString = ResolveConnectionString(builder.Configuration, connectionName)
                ?? throw new InvalidOperationException(
                    $"The database connection is not configured. Set ConnectionStrings:{connectionName}, or make Database:PasswordFile point to a readable, non-empty file.");
            options.UseNpgsql(connectionString, npgsql => npgsql.MigrationsHistoryTable(
                DatabaseSchemaVersion.MigrationHistoryTable,
                DatabaseSchemaVersion.MigrationHistorySchema));
            options.AddInterceptors(
                serviceProvider.GetRequiredService<UtcTimestampInterceptor>(),
                serviceProvider.GetRequiredService<UserOwnershipInterceptor>());
        });

        return builder;
    }

    /// <summary>
    /// Resolves the connection string from configuration or from the configured password file.
    /// Returns <see langword="null"/> when no usable connection is configured, that is when the password file is missing, unreadable or empty.
    /// </summary>
    internal static string? ResolveConnectionString(IConfiguration configuration, string connectionName)
    {
        string? direct = configuration.GetConnectionString(connectionName);
        string? passwordFile = configuration["Database:PasswordFile"];
        if (string.IsNullOrWhiteSpace(passwordFile)) return direct;
        string password;
        try
        {
            password = File.ReadAllText(passwordFile).Trim();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }

        if (string.IsNullOrWhiteSpace(password)) return null;
        return new Npgsql.NpgsqlConnectionStringBuilder
        {
            Host = configuration["Database:Host"] ?? "postgres",
            Port = configuration.GetValue("Database:Port", 5432),
            Database = configuration["Database:Name"] ?? "gainer",
            Username = configuration["Database:Username"] ?? "gainer",
            Password = password,
            Pooling = true,
        }.ConnectionString;
    }
}
