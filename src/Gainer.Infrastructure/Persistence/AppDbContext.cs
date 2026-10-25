using System.Linq.Expressions;
using System.Text.Json;
using Gainer.Core.Security;
using Gainer.Core.BodyTracking;
using Gainer.Core.Coach;
using Gainer.Core.Integrations;
using Gainer.Core.Nutrition;
using Gainer.Core.Training;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Catalog;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Provides the single transactional boundary for identity and application data.</summary>
public class AppDbContext(DbContextOptions<AppDbContext> options, IUserContext userContext)
    : IdentityDbContext<AppUser, IdentityRole<Guid>, Guid>(options)
{
    private const string PositionNonNegativeCheck = "\"Position\" >= 0";
    private const string NameNotBlankCheck = "length(trim(\"Name\")) > 0";
    private static readonly JsonSerializerOptions PhaseJsonOptions = new(JsonSerializerDefaults.Web);

    /// <summary>Hash-only metadata for pending account invitations.</summary>
    public DbSet<AccountInvitation> AccountInvitations => Set<AccountInvitation>();

    /// <summary>Signed-in mobile installations and their refresh tokens.</summary>
    public DbSet<DeviceSession> DeviceSessions => Set<DeviceSession>();

    public DbSet<BodyGoal> BodyGoals => Set<BodyGoal>();

    public DbSet<DailyCheckIn> DailyCheckIns => Set<DailyCheckIn>();

    public DbSet<NutritionDay> NutritionDays => Set<NutritionDay>();

    public DbSet<NutritionEntry> NutritionEntries => Set<NutritionEntry>();

    public DbSet<ReusableMeal> ReusableMeals => Set<ReusableMeal>();

    public DbSet<ReusableMealComponent> ReusableMealComponents => Set<ReusableMealComponent>();

    public DbSet<NutritionDayTemplate> NutritionDayTemplates => Set<NutritionDayTemplate>();

    public DbSet<NutritionDayTemplateEntry> NutritionDayTemplateEntries => Set<NutritionDayTemplateEntry>();

    public DbSet<WaterIntakeDay> WaterIntakeDays => Set<WaterIntakeDay>();

    public DbSet<NutritionTargetSchedule> NutritionTargetSchedules => Set<NutritionTargetSchedule>();

    public DbSet<NutritionTargetVersion> NutritionTargetVersions => Set<NutritionTargetVersion>();

    public DbSet<Exercise> Exercises => Set<Exercise>();

    public DbSet<ExerciseCategory> ExerciseCategories => Set<ExerciseCategory>();

    public DbSet<ExerciseCategoryAssignment> ExerciseCategoryAssignments => Set<ExerciseCategoryAssignment>();

    public DbSet<TrainingPlan> TrainingPlans => Set<TrainingPlan>();

    public DbSet<TrainingPlanEntry> TrainingPlanEntries => Set<TrainingPlanEntry>();

    public DbSet<TrainingSchedule> TrainingSchedules => Set<TrainingSchedule>();

    public DbSet<TrainingScheduleSlot> TrainingScheduleSlots => Set<TrainingScheduleSlot>();

    public DbSet<TrainingScheduleShift> TrainingScheduleShifts => Set<TrainingScheduleShift>();

    public DbSet<TrainingScheduleException> TrainingScheduleExceptions => Set<TrainingScheduleException>();

    public DbSet<Workout> Workouts => Set<Workout>();

    public DbSet<CardioSession> CardioSessions => Set<CardioSession>();

    public DbSet<StravaConnection> StravaConnections => Set<StravaConnection>();

    public DbSet<StravaExport> StravaExports => Set<StravaExport>();

    /// <summary>Notes the user confirmed for the coach.</summary>
    public DbSet<CoachMemory> CoachMemories => Set<CoachMemory>();

    public DbSet<WorkoutExercise> WorkoutExercises => Set<WorkoutExercise>();

    public DbSet<WorkoutSet> WorkoutSets => Set<WorkoutSet>();

    public DbSet<SyncClient> SyncClients => Set<SyncClient>();

    public DbSet<SyncHandover> SyncHandovers => Set<SyncHandover>();

    public DbSet<UserSyncState> UserSyncStates => Set<UserSyncState>();

    public DbSet<ProcessedMutation> ProcessedMutations => Set<ProcessedMutation>();

    public DbSet<ChangeBatch> ChangeBatches => Set<ChangeBatch>();

    public DbSet<ChangeItem> ChangeItems => Set<ChangeItem>();

    private Guid CurrentUserId => userContext.UserId ?? Guid.Empty;

    /// <summary>Columns shared by diary entries and day template entries.</summary>
    private static void ConfigureEntryValues<TEntry>(
        EntityTypeBuilder<TEntry> entry)
        where TEntry : NutritionEntryValues
    {
        entry.HasKey(item => item.Id);
        entry.Property(item => item.Meal).HasConversion<string>().HasMaxLength(16);
        entry.Property(item => item.ProductName).HasMaxLength(200).IsRequired();
        entry.Property(item => item.Brand).HasMaxLength(160);
        entry.Property(item => item.Provider).HasMaxLength(64);
        entry.Property(item => item.Barcode).HasMaxLength(64);
        foreach (Expression<Func<TEntry, decimal?>> column in new Expression<Func<TEntry, decimal?>>[]
                 {
                     item => item.ProteinGrams, item => item.CarbohydrateGrams, item => item.FatGrams, item => item.SaltGrams,
                     item => item.ProteinGramsPerBasis, item => item.CarbohydrateGramsPerBasis, item => item.FatGramsPerBasis,
                     item => item.SaltGramsPerBasis, item => item.FiberGrams, item => item.FiberGramsPerBasis, item => item.PieceGrams,
                 })
        {
            entry.Property(column).HasPrecision(9, 2);
        }
        entry.Property(item => item.AmountGrams).HasPrecision(9, 2);
        entry.Property(item => item.Kilocalories).HasPrecision(9, 2);
        entry.Property(item => item.BasisGrams).HasPrecision(9, 2);
        entry.Property(item => item.KilocaloriesPerBasis).HasPrecision(9, 2);
        entry.Property(item => item.PieceCount).HasPrecision(7, 2);
    }

    /// <inheritdoc />
    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        ConfigureIdentity(builder);
        ConfigureBodyTracking(builder);
        ConfigureNutrition(builder);
        ConfigureTraining(builder);
        ConfigureSync(builder);
        ConfigureIntegrations(builder);
        ConfigureCoach(builder);
        ApplyStorageConventions(builder.Model);
        ApplyUserQueryFilters(builder);
    }

    private static void ConfigureCoach(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<CoachMemory>(memory =>
        {
            memory.ToTable("coach_memories", DatabaseSchemas.Ai, table =>
            {
                table.HasCheckConstraint(
                    "CK_coach_memories_category",
                    "\"Category\" IN ('Goal', 'Preference', 'Intolerance', 'Injury', 'Other')");
                table.HasCheckConstraint(
                    "CK_coach_memories_text",
                    $"length(trim(\"Text\")) > 0 AND length(\"Text\") <= {CoachMemoryRules.MaxTextLength}");
            });
            memory.HasKey(item => item.Id);
            memory.Property(item => item.Id).ValueGeneratedNever();
            memory.Property(item => item.Category).HasConversion<string>().HasMaxLength(16);
            memory.Property(item => item.Text).HasMaxLength(CoachMemoryRules.MaxTextLength).IsRequired();
            memory.HasIndex(item => new { item.UserId, item.CreatedAtUtc });
            memory.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureIntegrations(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<StravaConnection>(connection =>
        {
            connection.ToTable("strava_connections", DatabaseSchemas.Integrations, table =>
                table.HasCheckConstraint("CK_strava_connections_athlete", "\"AthleteId\" > 0"));
            connection.HasKey(item => item.UserId);
            connection.Property(item => item.UserId).ValueGeneratedNever();
            connection.Property(item => item.AthleteName).HasMaxLength(200);
            connection.Property(item => item.Scope).HasMaxLength(200).IsRequired();
            connection.Property(item => item.ProtectedAccessToken).HasMaxLength(4_000).IsRequired();
            connection.Property(item => item.ProtectedRefreshToken).HasMaxLength(4_000).IsRequired();
            connection.HasOne<AppUser>()
                .WithOne()
                .HasForeignKey<StravaConnection>(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<StravaExport>(export =>
        {
            export.ToTable("strava_exports", DatabaseSchemas.Integrations, table =>
            {
                table.HasCheckConstraint("CK_strava_exports_kind", "\"Kind\" IN ('Cardio', 'Strength')");
                table.HasCheckConstraint(
                    "CK_strava_exports_status",
                    "\"Status\" IN ('Pending', 'Processing', 'Completed', 'Failed')");
                table.HasCheckConstraint("CK_strava_exports_attempts", "\"Attempts\" >= 0");
            });
            export.HasKey(item => item.Id);
            export.Property(item => item.Id).ValueGeneratedNever();
            export.Property(item => item.UserId).ValueGeneratedNever();
            export.Property(item => item.Kind).HasConversion<string>().HasMaxLength(16);
            export.Property(item => item.Status).HasConversion<string>().HasMaxLength(16);
            export.Property(item => item.LastErrorCode).HasMaxLength(64);
            export.HasIndex(item => new { item.UserId, item.Kind, item.ResourceId, item.AthleteId }).IsUnique();
            export.HasIndex(item => new { item.UserId, item.Status, item.NextAttemptAtUtc });
            export.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureSync(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<SyncClient>(client =>
        {
            client.ToTable("clients", DatabaseSchemas.Sync, table =>
            {
                table.HasCheckConstraint("CK_sync_clients_name", "length(trim(\"DisplayName\")) > 0");
                table.HasCheckConstraint("CK_sync_clients_protocol", "\"ProtocolVersion\" > 0");
            });
            client.HasKey(item => new { item.UserId, item.Id });
            client.Property(item => item.UserId).ValueGeneratedNever();
            client.Property(item => item.Id).ValueGeneratedNever();
            client.Property(item => item.DisplayName).HasMaxLength(100).IsRequired();
            client.HasIndex(item => item.Id);
            client.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserSyncState>(state =>
        {
            state.ToTable("user_state", DatabaseSchemas.Sync, table =>
                table.HasCheckConstraint("CK_sync_user_state_revision", "\"CurrentRevision\" >= 0"));
            state.HasKey(item => item.UserId);
            state.Property(item => item.UserId).ValueGeneratedNever();
            state.Property(item => item.Version).IsConcurrencyToken();
            state.HasOne<AppUser>().WithOne().HasForeignKey<UserSyncState>(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
            state.HasOne<SyncClient>().WithMany()
                .HasForeignKey(item => new { item.UserId, item.ActiveClientId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<SyncHandover>(handover =>
        {
            handover.ToTable("handovers", DatabaseSchemas.Sync, table =>
            {
                table.HasCheckConstraint("CK_sync_handovers_revision", "\"FrozenRevision\" >= 0");
                table.HasCheckConstraint("CK_sync_handovers_code_hash", "octet_length(\"CodeHash\") = 32");
                table.HasCheckConstraint("CK_sync_handovers_status", "\"Status\" IN ('Pending', 'Completed', 'Cancelled', 'Expired')");
            });
            handover.HasKey(item => new { item.UserId, item.Id });
            handover.Property(item => item.UserId).ValueGeneratedNever();
            handover.Property(item => item.Id).ValueGeneratedNever();
            handover.Property(item => item.RequestId).ValueGeneratedNever();
            handover.Property(item => item.CodeHash).HasColumnType("bytea").IsRequired();
            handover.Property(item => item.ProtectedCode).HasMaxLength(4096);
            handover.Property(item => item.Status).HasMaxLength(16).IsRequired();
            handover.HasIndex(item => new { item.UserId, item.RequestId }).IsUnique();
            handover.HasIndex(item => item.UserId).IsUnique().HasFilter("\"Status\" = 'Pending'");
            handover.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
            handover.HasOne<SyncClient>().WithMany()
                .HasForeignKey(item => new { item.UserId, item.SourceClientId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
            handover.HasOne<SyncClient>().WithMany()
                .HasForeignKey(item => new { item.UserId, item.TargetClientId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<ProcessedMutation>(mutation =>
        {
            mutation.ToTable("processed_mutations", DatabaseSchemas.Sync, table =>
            {
                table.HasCheckConstraint("CK_processed_mutations_sequence", "\"ClientSequence\" > 0");
                table.HasCheckConstraint("CK_processed_mutations_hash", "octet_length(\"ContentHash\") = 32");
                table.HasCheckConstraint("CK_processed_mutations_revision", "\"Revision\" > 0");
            });
            mutation.HasKey(item => new { item.UserId, item.MutationId });
            mutation.Property(item => item.UserId).ValueGeneratedNever();
            mutation.Property(item => item.MutationId).ValueGeneratedNever();
            mutation.Property(item => item.ContentHash).HasColumnType("bytea");
            mutation.Property(item => item.ResultJson).HasColumnType("jsonb").IsRequired();
            mutation.HasIndex(item => new { item.UserId, item.ClientId, item.ClientSequence }).IsUnique();
            mutation.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
            mutation.HasOne<SyncClient>().WithMany()
                .HasForeignKey(item => new { item.UserId, item.ClientId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<ChangeBatch>(batch =>
        {
            batch.ToTable("change_batches", DatabaseSchemas.Sync, table =>
                table.HasCheckConstraint("CK_change_batches_revision", "\"Revision\" > 0"));
            batch.HasKey(item => item.Id);
            batch.HasAlternateKey(item => new { item.UserId, item.Id });
            batch.Property(item => item.UserId).ValueGeneratedNever();
            batch.HasIndex(item => new { item.UserId, item.Revision }).IsUnique();
            batch.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
            batch.HasOne<ProcessedMutation>().WithOne()
                .HasForeignKey<ChangeBatch>(item => new { item.UserId, item.MutationId })
                .HasPrincipalKey<ProcessedMutation>(item => new { item.UserId, item.MutationId })
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<ChangeItem>(item =>
        {
            item.ToTable("change_items", DatabaseSchemas.Sync, table =>
            {
                table.HasCheckConstraint("CK_change_items_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_change_items_resource_type", "length(trim(\"ResourceType\")) > 0");
                table.HasCheckConstraint("CK_change_items_resource_version", "\"ResourceVersion\" > 0");
                table.HasCheckConstraint(
                    "CK_change_items_payload",
                    "(\"IsTombstone\" = TRUE AND \"SnapshotJson\" IS NULL) OR " +
                    "(\"IsTombstone\" = FALSE AND \"SnapshotJson\" IS NOT NULL)");
            });
            item.HasKey(value => value.Id);
            item.Property(value => value.UserId).ValueGeneratedNever();
            item.Property(value => value.ResourceType).HasMaxLength(64).IsRequired();
            item.Property(value => value.SnapshotJson).HasColumnType("jsonb");
            item.HasIndex(value => new { value.BatchId, value.Position }).IsUnique();
            item.HasIndex(value => new { value.UserId, value.ResourceType, value.ResourceId });
            item.HasOne<ChangeBatch>().WithMany()
                .HasForeignKey(value => new { value.UserId, value.BatchId })
                .HasPrincipalKey(value => new { value.UserId, value.Id })
                .OnDelete(DeleteBehavior.Cascade);
            item.HasOne<AppUser>().WithMany().HasForeignKey(value => value.UserId).OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureTraining(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Exercise>(exercise =>
        {
            exercise.ToTable("exercises", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_exercises_name", NameNotBlankCheck);
                table.HasCheckConstraint(
                    "CK_exercises_catalog_ownership",
                    "(\"OwnerUserId\" IS NULL AND \"CatalogVersion\" IS NOT NULL AND \"IsArchived\" = FALSE) OR " +
                    "(\"OwnerUserId\" IS NOT NULL AND \"CatalogVersion\" IS NULL)");
                table.HasCheckConstraint(
                    "CK_exercises_type",
                    "\"ExerciseType\" IN ('strength', 'bodyweightLoaded', 'bodyweightOnly', 'assisted')");
                table.HasCheckConstraint(
                    "CK_exercises_bodyweight_factor",
                    "\"BodyweightFactor\" IS NULL OR (\"BodyweightFactor\" >= 0 AND \"BodyweightFactor\" <= 1)");
                table.HasCheckConstraint(
                    "CK_exercises_weight_factor",
                    "\"WeightFactor\" IS NULL OR (\"WeightFactor\" > 0 AND \"WeightFactor\" <= 10)");
            });
            exercise.HasKey(item => item.Id);
            exercise.Property(item => item.Name).HasMaxLength(160).IsRequired();
            exercise.Property(item => item.Description).HasMaxLength(2_000);
            exercise.Property(item => item.TargetMuscle).HasMaxLength(100);
            exercise.Property(item => item.MuscleGroup).HasMaxLength(100);
            exercise.Property(item => item.PrimaryMuscles).HasDefaultValueSql("'{}'::text[]");
            exercise.Property(item => item.SecondaryMuscles).HasDefaultValueSql("'{}'::text[]");
            exercise.Property(item => item.Equipment).HasMaxLength(100);
            exercise.Property(item => item.ExerciseType)
                .HasConversion(new ValueConverter<ExerciseType, string>(
                    value => ExerciseTypes.ToStorageValue(value),
                    value => ExerciseTypes.Parse(value)))
                .HasMaxLength(32)
                .IsRequired();
            exercise.Property(item => item.Notes).HasMaxLength(2_000);
            exercise.Property(item => item.BodyweightFactor).HasPrecision(5, 4);
            exercise.Property(item => item.WeightFactor).HasPrecision(5, 3);
            exercise.Property(item => item.CatalogVersion).HasMaxLength(32);
            exercise.Property(item => item.Version).IsConcurrencyToken();
            exercise.HasIndex(item => new { item.OwnerUserId, item.Name });
            exercise.HasIndex(item => new { item.OwnerUserId, item.TargetMuscle });
            exercise.HasIndex(item => new { item.OwnerUserId, item.MuscleGroup });
            exercise.HasIndex(item => new { item.OwnerUserId, item.Equipment });
            exercise.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.OwnerUserId)
                .OnDelete(DeleteBehavior.Cascade);

            DateTime catalogCreatedAt = new(2026, 8, 18, 0, 0, 0, DateTimeKind.Utc);
            DateTime catalogUpdatedAt = new(2026, 10, 17, 0, 0, 0, DateTimeKind.Utc);
            exercise.HasData(ExerciseCatalogSnapshot.Document.Entries.Select(item => new Exercise
            {
                Id = item.Id,
                Name = item.Name,
                Description = item.Description,
                TargetMuscle = item.TargetMuscle,
                MuscleGroup = item.MuscleGroup,
                PrimaryMuscles = [.. item.PrimaryMuscles],
                SecondaryMuscles = [.. item.SecondaryMuscles],
                Equipment = item.Equipment,
                ExerciseType = ExerciseTypes.Parse(item.ExerciseType),
                BodyweightFactor = item.BodyweightFactor,
                WeightFactor = item.WeightFactor,
                CatalogVersion = ExerciseCatalogSnapshot.Document.CatalogVersion,
                CreatedAtUtc = catalogCreatedAt,
                UpdatedAtUtc = catalogUpdatedAt,
                Version = 1,
            }));
        });

        modelBuilder.Entity<ExerciseCategory>(category =>
        {
            category.ToTable("exercise_categories", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_exercise_categories_name", NameNotBlankCheck);
                table.HasCheckConstraint(
                    "CK_exercise_categories_catalog_ownership",
                    "(\"OwnerUserId\" IS NULL AND \"CatalogVersion\" IS NOT NULL AND \"IsArchived\" = FALSE) OR " +
                    "(\"OwnerUserId\" IS NOT NULL AND \"CatalogVersion\" IS NULL)");
            });
            category.HasKey(item => item.Id);
            category.Property(item => item.Name).HasMaxLength(80).IsRequired();
            category.Property(item => item.CatalogVersion).HasMaxLength(32);
            category.Property(item => item.Version).IsConcurrencyToken();
            category.HasIndex(item => new { item.OwnerUserId, item.Name });
            category.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.OwnerUserId)
                .OnDelete(DeleteBehavior.Cascade);

            DateTime catalogTimestamp = new(2026, 10, 17, 0, 0, 0, DateTimeKind.Utc);
            category.HasData(ExerciseCatalogSnapshot.Document.Categories.Select(item => new ExerciseCategory
            {
                Id = item.Id,
                Name = item.Name,
                CatalogVersion = ExerciseCatalogSnapshot.Document.CatalogVersion,
                CreatedAtUtc = catalogTimestamp,
                UpdatedAtUtc = catalogTimestamp,
                Version = 1,
            }));
        });

        modelBuilder.Entity<ExerciseCategoryAssignment>(assignment =>
        {
            assignment.ToTable("exercise_category_assignments", DatabaseSchemas.Training);
            assignment.HasKey(item => new { item.ExerciseId, item.CategoryId });
            assignment.HasIndex(item => item.CategoryId);
            assignment.HasOne<Exercise>()
                .WithMany()
                .HasForeignKey(item => item.ExerciseId)
                .OnDelete(DeleteBehavior.Cascade);
            assignment.HasOne<ExerciseCategory>()
                .WithMany()
                .HasForeignKey(item => item.CategoryId)
                .OnDelete(DeleteBehavior.Restrict);

            ExerciseCatalogDocument document = ExerciseCatalogSnapshot.Document;
            assignment.HasData(document.Entries.SelectMany(entry => entry.CategoryKeys.Select(key =>
                new ExerciseCategoryAssignment
                {
                    ExerciseId = entry.Id,
                    CategoryId = document.CategoryId(key),
                })));
        });

        modelBuilder.Entity<TrainingPlan>(plan =>
        {
            plan.ToTable("training_plans", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_training_plans_name", NameNotBlankCheck);
                table.HasCheckConstraint("CK_training_plans_sort_order", PositionNonNegativeCheck.Replace("Position", "SortOrder"));
                table.HasCheckConstraint(
                    "CK_training_plans_previous_value_source",
                    "\"PreviousValueSource\" IN ('exercise', 'plan', 'workout')");
            });
            plan.HasKey(item => item.Id);
            plan.HasAlternateKey(item => new { item.UserId, item.Id });
            plan.Property(item => item.UserId).ValueGeneratedNever();
            plan.Property(item => item.Name).HasMaxLength(160).IsRequired();
            plan.Property(item => item.Notes).HasMaxLength(2_000);
            plan.Property(item => item.PreviousValueSource)
                .HasConversion(new ValueConverter<PreviousValueSource, string>(
                    value => PreviousValueSources.ToStorageValue(value),
                    value => PreviousValueSources.Parse(value)))
                .HasMaxLength(16)
                .IsRequired();
            plan.Property(item => item.Version).IsConcurrencyToken();
            plan.HasIndex(item => new { item.UserId, item.SortOrder });
            plan.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TrainingPlanEntry>(entry =>
        {
            entry.ToTable("training_plan_entries", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_training_plan_entries_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_training_plan_entries_warmup_sets", "\"WarmupSets\" BETWEEN 0 AND 20");
                table.HasCheckConstraint("CK_training_plan_entries_working_sets", "\"WorkingSets\" BETWEEN 0 AND 50");
                table.HasCheckConstraint(
                    "CK_training_plan_entries_sets",
                    "\"WarmupSets\" + \"WorkingSets\" BETWEEN 1 AND 50");
            });
            entry.HasKey(item => item.Id);
            entry.Property(item => item.UserId).ValueGeneratedNever();
            entry.Property(item => item.Notes).HasMaxLength(2_000);
            entry.HasIndex(item => new { item.PlanId, item.Position }).IsUnique();
            entry.HasIndex(item => new { item.UserId, item.PlanId });
            entry.HasOne<TrainingPlan>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.PlanId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Cascade);
            entry.HasOne<Exercise>()
                .WithMany()
                .HasForeignKey(item => item.ExerciseId)
                .OnDelete(DeleteBehavior.Restrict);
            entry.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        ConfigureTrainingSchedule(modelBuilder);

        modelBuilder.Entity<Workout>(workout =>
        {
            workout.ToTable("workouts", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workouts_title", NameNotBlankCheck.Replace("Name", "Title"));
                table.HasCheckConstraint(
                    "CK_workouts_end_after_start",
                    "\"EndedAtUtc\" IS NULL OR \"EndedAtUtc\" > \"StartedAtUtc\"");
                table.HasCheckConstraint(
                    "CK_workouts_previous_value_source",
                    "\"PreviousValueSource\" IN ('exercise', 'plan', 'workout')");
            });
            workout.HasKey(item => item.Id);
            workout.HasAlternateKey(item => new { item.UserId, item.Id });
            workout.Property(item => item.UserId).ValueGeneratedNever();
            workout.Property(item => item.Title).HasMaxLength(160).IsRequired();
            workout.Property(item => item.Notes).HasMaxLength(2_000);
            workout.Property(item => item.PreviousValueSource)
                .HasConversion(new ValueConverter<PreviousValueSource, string>(
                    value => PreviousValueSources.ToStorageValue(value),
                    value => PreviousValueSources.Parse(value)))
                .HasMaxLength(16)
                .IsRequired();
            workout.Property(item => item.Version).IsConcurrencyToken();
            workout.HasIndex(item => item.UserId)
                .IsUnique()
                .HasDatabaseName("UX_workouts_one_active_per_user")
                .HasFilter("\"EndedAtUtc\" IS NULL AND \"DeletedAtUtc\" IS NULL");
            workout.HasIndex(item => new { item.UserId, item.EndedAtUtc }).IsDescending(false, true);
            workout.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            workout.HasOne<TrainingPlan>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.SourcePlanId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
            workout.HasOne<Workout>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.SourceWorkoutId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<CardioSession>(session =>
        {
            session.ToTable("cardio_sessions", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_cardio_sessions_end_after_start", "\"EndedAtUtc\" > \"StartedAtUtc\"");
                table.HasCheckConstraint("CK_cardio_sessions_activity_type", "\"ActivityType\" IN ('IndoorCycling')");
                table.HasCheckConstraint(
                    "CK_cardio_sessions_target_zone",
                    "(\"TargetZoneLowBpm\" IS NULL AND \"TargetZoneHighBpm\" IS NULL) OR (\"TargetZoneLowBpm\" >= 40 AND \"TargetZoneHighBpm\" <= 230 AND \"TargetZoneLowBpm\" < \"TargetZoneHighBpm\")");
                table.HasCheckConstraint(
                    "CK_cardio_sessions_sample_interval",
                    "\"SampleIntervalSeconds\" BETWEEN 1 AND 60");
                table.HasCheckConstraint(
                    "CK_cardio_sessions_recovery",
                    "(\"RecoveryStartBpm\" IS NULL AND \"RecoveryEndBpm\" IS NULL) OR (\"RecoveryStartBpm\" BETWEEN 25 AND 250 AND \"RecoveryEndBpm\" BETWEEN 25 AND 250)");
            });
            session.HasKey(item => item.Id);
            session.HasAlternateKey(item => new { item.UserId, item.Id });
            session.Property(item => item.UserId).ValueGeneratedNever();
            session.Property(item => item.ActivityType).HasMaxLength(32).IsRequired();
            session.Property(item => item.HeartRateBpm).HasColumnType("integer[]").IsRequired();
            session.Property(item => item.RrIntervalsMs).HasColumnType("integer[]").IsRequired();
            session.Property(item => item.SensorName).HasMaxLength(100);
            session.Property(item => item.DistanceKm).HasPrecision(8, 3);
            session.Property(item => item.AveragePowerWatts).HasPrecision(7, 2);
            session.Property(item => item.EnergyKcal).HasPrecision(8, 2);
            session.Property(item => item.Notes).HasMaxLength(2_000);
            session.Property(item => item.TemplateName).HasMaxLength(100);
            session.Property(item => item.Phases)
                .HasColumnType("jsonb")
                .HasConversion(
                    phases => phases == null ? null : JsonSerializer.Serialize(phases, PhaseJsonOptions),
                    json => json == null ? null : (IReadOnlyList<CardioPhaseValues>?)JsonSerializer.Deserialize<CardioPhaseValues[]>(json, PhaseJsonOptions),
                    new ValueComparer<IReadOnlyList<CardioPhaseValues>?>(
                        (left, right) => left == null ? right == null : right != null && left.SequenceEqual(right),
                        phases => phases == null ? 0 : phases.Aggregate(0, (hash, phase) => HashCode.Combine(hash, phase)),
                        phases => phases == null ? null : phases.ToArray()));
            session.Property(item => item.Version).IsConcurrencyToken();
            session.HasIndex(item => new { item.UserId, item.StartedAtUtc })
                .IsDescending(false, true);
            session.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WorkoutExercise>(exercise =>
        {
            exercise.ToTable("workout_exercises", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workout_exercises_name", "length(trim(\"ExerciseNameSnapshot\")) > 0");
                table.HasCheckConstraint("CK_workout_exercises_position", PositionNonNegativeCheck);
            });
            exercise.HasKey(item => item.Id);
            exercise.HasAlternateKey(item => new { item.UserId, item.Id });
            exercise.Property(item => item.UserId).ValueGeneratedNever();
            exercise.Property(item => item.ExerciseNameSnapshot).HasMaxLength(160).IsRequired();
            exercise.Property(item => item.ExerciseTypeSnapshot)
                .HasConversion(new ValueConverter<ExerciseType, string>(
                    value => ExerciseTypes.ToStorageValue(value),
                    value => ExerciseTypes.Parse(value)))
                .HasMaxLength(32)
                .IsRequired();
            exercise.Property(item => item.Notes).HasMaxLength(2_000);
            exercise.HasIndex(item => new { item.WorkoutId, item.Position }).IsUnique();
            exercise.HasIndex(item => new { item.UserId, item.SourceExerciseId });
            exercise.HasOne<Workout>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.WorkoutId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Cascade);
            exercise.HasOne<Exercise>()
                .WithMany()
                .HasForeignKey(item => item.SourceExerciseId)
                .OnDelete(DeleteBehavior.Restrict);
            exercise.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WorkoutSet>(set =>
        {
            set.ToTable("workout_sets", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workout_sets_position", PositionNonNegativeCheck);
                table.HasCheckConstraint(
                    "CK_workout_sets_type",
                    "\"SetType\" IN ('normal', 'warmup', 'dropset')");
                table.HasCheckConstraint(
                    "CK_workout_sets_weight",
                    "\"WeightKg\" IS NULL OR (\"WeightKg\" >= 0 AND \"WeightKg\" <= 10000)");
                table.HasCheckConstraint(
                    "CK_workout_sets_repetitions",
                    "\"Repetitions\" IS NULL OR (\"Repetitions\" >= 0 AND \"Repetitions\" <= 10000)");
                table.HasCheckConstraint("CK_workout_sets_rir", "\"Rir\" IS NULL OR (\"Rir\" >= 0 AND \"Rir\" <= 10)");
            });
            set.HasKey(item => item.Id);
            set.Property(item => item.UserId).ValueGeneratedNever();
            set.Property(item => item.SetType)
                .HasConversion(new ValueConverter<WorkoutSetType, string>(
                    value => WorkoutSetTypes.ToStorageValue(value),
                    value => WorkoutSetTypes.ParseOrNormal(value)))
                .HasMaxLength(16)
                .IsRequired();
            set.Property(item => item.WeightKg).HasPrecision(7, 2);
            set.Property(item => item.Rir).HasPrecision(4, 2);
            set.Property(item => item.Notes).HasMaxLength(2_000);
            set.HasIndex(item => new { item.WorkoutExerciseId, item.Position }).IsUnique();
            set.HasIndex(item => new { item.UserId, item.WorkoutId });
            set.HasOne<Workout>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.WorkoutId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Cascade);
            set.HasOne<WorkoutExercise>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.WorkoutExerciseId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Cascade);
            set.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureBodyTracking(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<BodyGoal>(goal =>
        {
            goal.ToTable("body_goals", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_body_goals_start_weight", "\"StartWeightKg\" > 0");
                table.HasCheckConstraint("CK_body_goals_target_weight", "\"TargetWeightKg\" > 0");
                table.HasCheckConstraint(
                    "CK_body_goals_target_date",
                    "\"TargetDate\" IS NULL OR \"TargetDate\" >= \"StartDate\"");
                table.HasCheckConstraint(
                    "CK_body_goals_kind",
                    "\"Kind\" IN ('Bulk', 'Maintain', 'Cut')");
            });
            goal.HasKey(item => item.Id);
            goal.Property(item => item.Kind).HasConversion<string>().HasMaxLength(16);
            goal.Property(item => item.StartWeightKg).HasPrecision(6, 2);
            goal.Property(item => item.TargetWeightKg).HasPrecision(6, 2);
            goal.Property(item => item.Version).IsConcurrencyToken();
            goal.HasIndex(item => item.UserId)
                .IsUnique()
                .HasFilter("\"EndedAtUtc\" IS NULL");
            goal.HasIndex(item => new { item.UserId, item.StartDate });
            goal.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<DailyCheckIn>(checkIn =>
        {
            checkIn.ToTable("daily_check_ins", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_daily_check_ins_weight", "\"WeightKg\" > 0");
                table.HasCheckConstraint("CK_daily_check_ins_calories", "\"CaloriesKcal\" IS NULL OR \"CaloriesKcal\" >= 0");
                table.HasCheckConstraint("CK_daily_check_ins_protein", "\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0");
                table.HasCheckConstraint("CK_daily_check_ins_carbohydrate", "\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0");
                table.HasCheckConstraint("CK_daily_check_ins_fat", "\"FatGrams\" IS NULL OR \"FatGrams\" >= 0");
                table.HasCheckConstraint("CK_daily_check_ins_steps", "\"Steps\" IS NULL OR \"Steps\" >= 0");
                table.HasCheckConstraint("CK_daily_check_ins_resting_hr", "\"RestingHeartRateBpm\" IS NULL OR (\"RestingHeartRateBpm\" >= 25 AND \"RestingHeartRateBpm\" <= 150)");
                table.HasCheckConstraint("CK_daily_check_ins_resting_hrv", "\"RestingHrvMs\" IS NULL OR (\"RestingHrvMs\" >= 1 AND \"RestingHrvMs\" <= 300)");
                table.HasCheckConstraint("CK_daily_check_ins_sleep", "\"SleepMinutes\" IS NULL OR (\"SleepMinutes\" >= 0 AND \"SleepMinutes\" <= 1440)");
            });
            checkIn.HasKey(item => item.Id);
            checkIn.Property(item => item.WeightKg).HasPrecision(6, 2);
            checkIn.Property(item => item.CaloriesKcal).HasPrecision(8, 2);
            checkIn.Property(item => item.ProteinGrams).HasPrecision(7, 2);
            checkIn.Property(item => item.CarbohydrateGrams).HasPrecision(7, 2);
            checkIn.Property(item => item.FatGrams).HasPrecision(7, 2);
            checkIn.Property(item => item.Version).IsConcurrencyToken();
            checkIn.HasIndex(item => new { item.UserId, item.LocalDate }).IsUnique();
            checkIn.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureNutrition(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<NutritionDay>(day =>
        {
            day.ToTable("nutrition_days", DatabaseSchemas.Tracking, table =>
                table.HasCheckConstraint("CK_nutrition_days_day_kind", "\"DayKind\" IS NULL OR \"DayKind\" IN ('Training', 'Rest')"));
            day.HasKey(item => item.Id);
            day.Property(item => item.DayKind).HasConversion<string>().HasMaxLength(16);
            day.HasAlternateKey(item => new { item.UserId, item.Id });
            day.Property(item => item.Version).IsConcurrencyToken();
            day.HasIndex(item => new { item.UserId, item.LocalDate }).IsUnique();
            day.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NutritionEntry>(entry =>
        {
            entry.ToTable("nutrition_entries", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_nutrition_entries_meal", "\"Meal\" IN ('Breakfast', 'Lunch', 'Dinner', 'Snacks')");
                table.HasCheckConstraint("CK_nutrition_entries_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_nutrition_entries_name", "length(trim(\"ProductName\")) > 0");
                table.HasCheckConstraint("CK_nutrition_entries_amount", "\"AmountGrams\" > 0");
                table.HasCheckConstraint("CK_nutrition_entries_kcal", "\"Kilocalories\" >= 0");
                table.HasCheckConstraint("CK_nutrition_entries_macros", "(\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0) AND (\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0) AND (\"FatGrams\" IS NULL OR \"FatGrams\" >= 0)");
                table.HasCheckConstraint("CK_nutrition_entries_basis", "\"BasisGrams\" > 0 AND \"KilocaloriesPerBasis\" >= 0");
                table.HasCheckConstraint("CK_nutrition_entries_basis_macros", "(\"ProteinGramsPerBasis\" IS NULL OR \"ProteinGramsPerBasis\" >= 0) AND (\"CarbohydrateGramsPerBasis\" IS NULL OR \"CarbohydrateGramsPerBasis\" >= 0) AND (\"FatGramsPerBasis\" IS NULL OR \"FatGramsPerBasis\" >= 0)");
                table.HasCheckConstraint("CK_nutrition_entries_salt", "(\"SaltGrams\" IS NULL OR \"SaltGrams\" >= 0) AND (\"SaltGramsPerBasis\" IS NULL OR \"SaltGramsPerBasis\" >= 0)");
                table.HasCheckConstraint("CK_nutrition_entries_fiber", "(\"FiberGrams\" IS NULL OR \"FiberGrams\" >= 0) AND (\"FiberGramsPerBasis\" IS NULL OR \"FiberGramsPerBasis\" >= 0)");
                table.HasCheckConstraint("CK_nutrition_entries_pieces", "(\"PieceGrams\" IS NULL OR \"PieceGrams\" > 0) AND (\"PieceCount\" IS NULL OR (\"PieceCount\" > 0 AND \"PieceGrams\" IS NOT NULL))");
            });
            ConfigureEntryValues(entry);
            entry.Property(item => item.AmountUnit).HasMaxLength(16).IsRequired();
            entry.HasIndex(item => new { item.UserId, item.NutritionDayId, item.Meal, item.Position }).IsUnique();
            entry.HasIndex(item => new { item.UserId, item.Barcode });
            entry.HasOne(item => item.NutritionDay)
                .WithMany(day => day.Entries)
                .HasForeignKey(item => new { item.UserId, item.NutritionDayId })
                .HasPrincipalKey(day => new { day.UserId, day.Id })
                .OnDelete(DeleteBehavior.Cascade);
            entry.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ReusableMeal>(meal =>
        {
            meal.ToTable("reusable_meals", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_reusable_meals_name", NameNotBlankCheck);
                table.HasCheckConstraint("CK_reusable_meals_portion", "\"StandardPortion\" >= 0.01 AND \"StandardPortion\" <= 100");
                table.HasCheckConstraint("CK_reusable_meals_status", "\"Status\" IN ('Active', 'Archived')");
            });
            meal.HasKey(item => item.Id);
            meal.HasAlternateKey(item => new { item.UserId, item.Id });
            meal.Property(item => item.Name).HasMaxLength(NutritionLimits.MaxReusableMealNameLength).IsRequired();
            meal.Property(item => item.Description).HasMaxLength(NutritionLimits.MaxReusableMealDescriptionLength);
            meal.Property(item => item.StandardPortion).HasPrecision(8, 2);
            meal.Property(item => item.Status).HasConversion<string>().HasMaxLength(16);
            meal.Property(item => item.Version).IsConcurrencyToken();
            meal.HasIndex(item => new { item.UserId, item.Status, item.Name });
            meal.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ReusableMealComponent>(component =>
        {
            component.ToTable("reusable_meal_components", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_reusable_meal_components_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_reusable_meal_components_name", NameNotBlankCheck);
                table.HasCheckConstraint("CK_reusable_meal_components_amount", "\"AmountGrams\" >= 0.01 AND \"AmountGrams\" <= 100000");
                table.HasCheckConstraint("CK_reusable_meal_components_kcal", "\"Kilocalories\" >= 0 AND \"KilocaloriesPer100Grams\" >= 0");
                table.HasCheckConstraint("CK_reusable_meal_components_basis", "\"BasisGrams\" > 0");
                table.HasCheckConstraint("CK_reusable_meal_components_macros", "(\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0) AND (\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0) AND (\"FatGrams\" IS NULL OR \"FatGrams\" >= 0)");
                table.HasCheckConstraint("CK_reusable_meal_components_per100_macros", "(\"ProteinGramsPer100Grams\" IS NULL OR \"ProteinGramsPer100Grams\" >= 0) AND (\"CarbohydrateGramsPer100Grams\" IS NULL OR \"CarbohydrateGramsPer100Grams\" >= 0) AND (\"FatGramsPer100Grams\" IS NULL OR \"FatGramsPer100Grams\" >= 0)");
                table.HasCheckConstraint("CK_reusable_meal_components_salt", "(\"SaltGrams\" IS NULL OR \"SaltGrams\" >= 0) AND (\"SaltGramsPer100Grams\" IS NULL OR (\"SaltGramsPer100Grams\" >= 0 AND \"SaltGramsPer100Grams\" <= 100))");
                table.HasCheckConstraint("CK_reusable_meal_components_fiber", "(\"FiberGrams\" IS NULL OR \"FiberGrams\" >= 0) AND (\"FiberGramsPer100Grams\" IS NULL OR (\"FiberGramsPer100Grams\" >= 0 AND \"FiberGramsPer100Grams\" <= 100))");
                table.HasCheckConstraint("CK_reusable_meal_components_pieces", "(\"PieceGrams\" IS NULL OR \"PieceGrams\" > 0) AND (\"PieceCount\" IS NULL OR (\"PieceCount\" > 0 AND \"PieceGrams\" IS NOT NULL))");
            });
            component.HasKey(item => item.Id);
            component.Property(item => item.Name).HasMaxLength(NutritionLimits.MaxComponentNameLength).IsRequired();
            component.Property(item => item.Brand).HasMaxLength(160);
            component.Property(item => item.Provider).HasMaxLength(64);
            component.Property(item => item.Barcode).HasMaxLength(64);
            component.Property(item => item.AmountGrams).HasPrecision(10, 2);
            component.Property(item => item.Kilocalories).HasPrecision(10, 2);
            component.Property(item => item.ProteinGrams).HasPrecision(10, 2);
            component.Property(item => item.CarbohydrateGrams).HasPrecision(10, 2);
            component.Property(item => item.FatGrams).HasPrecision(10, 2);
            component.Property(item => item.KilocaloriesPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.ProteinGramsPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.CarbohydrateGramsPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.FatGramsPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.SaltGrams).HasPrecision(10, 2);
            component.Property(item => item.SaltGramsPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.FiberGrams).HasPrecision(10, 2);
            component.Property(item => item.FiberGramsPer100Grams).HasPrecision(10, 2);
            component.Property(item => item.PieceGrams).HasPrecision(9, 2);
            component.Property(item => item.PieceCount).HasPrecision(7, 2);
            component.Property(item => item.BasisGrams).HasPrecision(10, 2);
            component.HasIndex(item => new { item.UserId, item.ReusableMealId, item.Position }).IsUnique();
            component.HasOne(item => item.ReusableMeal)
                .WithMany(meal => meal.Components)
                .HasForeignKey(item => new { item.UserId, item.ReusableMealId })
                .HasPrincipalKey(meal => new { meal.UserId, meal.Id })
                .OnDelete(DeleteBehavior.Cascade);
            component.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NutritionDayTemplate>(template =>
        {
            template.ToTable("nutrition_day_templates", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_nutrition_day_templates_name", NameNotBlankCheck);
                table.HasCheckConstraint("CK_nutrition_day_templates_day_kind", "\"DayKind\" IS NULL OR \"DayKind\" IN ('Training', 'Rest')");
            });
            template.HasKey(item => item.Id);
            template.HasAlternateKey(item => new { item.UserId, item.Id });
            template.Property(item => item.Name).HasMaxLength(NutritionLimits.MaxDayTemplateNameLength).IsRequired();
            template.Property(item => item.DayKind).HasConversion<string>().HasMaxLength(16);
            template.Property(item => item.Version).IsConcurrencyToken();
            template.HasIndex(item => new { item.UserId, item.UpdatedAtUtc });
            template.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NutritionDayTemplateEntry>(entry =>
        {
            entry.ToTable("nutrition_day_template_entries", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_nutrition_day_template_entries_meal", "\"Meal\" IN ('Breakfast', 'Lunch', 'Dinner', 'Snacks')");
                table.HasCheckConstraint("CK_nutrition_day_template_entries_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_nutrition_day_template_entries_name", "length(trim(\"ProductName\")) > 0");
                table.HasCheckConstraint("CK_nutrition_day_template_entries_amount", "\"AmountGrams\" > 0");
                table.HasCheckConstraint("CK_nutrition_day_template_entries_basis", "\"BasisGrams\" > 0 AND \"KilocaloriesPerBasis\" >= 0");
            });
            ConfigureEntryValues(entry);
            entry.HasIndex(item => new { item.UserId, item.NutritionDayTemplateId, item.Meal, item.Position }).IsUnique();
            entry.HasOne(item => item.NutritionDayTemplate)
                .WithMany(template => template.Entries)
                .HasForeignKey(item => new { item.UserId, item.NutritionDayTemplateId })
                .HasPrincipalKey(template => new { template.UserId, template.Id })
                .OnDelete(DeleteBehavior.Cascade);
            entry.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WaterIntakeDay>(day =>
        {
            day.ToTable("water_intake_days", DatabaseSchemas.Tracking, table =>
                table.HasCheckConstraint(
                    "CK_water_intake_days_amount",
                    $"\"AmountMl\" >= {WaterIntakeLimits.MinDailyMl} AND \"AmountMl\" <= {WaterIntakeLimits.MaxDailyMl}"));
            day.HasKey(item => item.Id);
            day.Property(item => item.Version).IsConcurrencyToken();
            day.HasIndex(item => new { item.UserId, item.LocalDate }).IsUnique();
            day.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NutritionTargetSchedule>(schedule =>
        {
            schedule.ToTable("nutrition_target_schedules", DatabaseSchemas.Tracking);
            schedule.HasKey(item => item.Id);
            schedule.HasAlternateKey(item => new { item.UserId, item.Id });
            schedule.Property(item => item.Version).IsConcurrencyToken();
            schedule.HasIndex(item => item.UserId).IsUnique();
            schedule.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<NutritionTargetVersion>(version =>
        {
            version.ToTable("nutrition_target_versions", DatabaseSchemas.Tracking, table =>
            {
                table.HasCheckConstraint("CK_nutrition_target_versions_kcal", "\"Kilocalories\" > 0 AND \"Kilocalories\" <= 20000");
                table.HasCheckConstraint("CK_nutrition_target_versions_macros", "\"ProteinGrams\" > 0 AND \"ProteinGrams\" <= 2000 AND \"CarbohydrateGrams\" > 0 AND \"CarbohydrateGrams\" <= 2000 AND \"FatGrams\" > 0 AND \"FatGrams\" <= 2000");
                table.HasCheckConstraint("CK_nutrition_target_versions_salt", "\"SaltGrams\" IS NULL OR (\"SaltGrams\" > 0 AND \"SaltGrams\" <= 100)");
                table.HasCheckConstraint("CK_nutrition_target_versions_fiber", "\"FiberGrams\" IS NULL OR (\"FiberGrams\" > 0 AND \"FiberGrams\" <= 100)");
                table.HasCheckConstraint("CK_nutrition_target_versions_origin", "\"Origin\" = 'Manual'");
                table.HasCheckConstraint("CK_nutrition_target_versions_name", NameNotBlankCheck);
                table.HasCheckConstraint("CK_nutrition_target_versions_category", "\"Category\" IN ('Custom', 'Cut', 'Maintenance', 'Bulk')");
                table.HasCheckConstraint("CK_nutrition_target_versions_dates", "\"EffectiveUntil\" IS NULL OR \"EffectiveUntil\" >= \"EffectiveFrom\"");
                table.HasCheckConstraint("CK_nutrition_target_versions_input", "(\"InputMode\" = 'Grams' AND \"ProteinPercent\" IS NULL AND \"CarbohydratePercent\" IS NULL AND \"FatPercent\" IS NULL) OR (\"InputMode\" = 'Percent' AND \"ProteinPercent\" > 0 AND \"CarbohydratePercent\" > 0 AND \"FatPercent\" > 0 AND \"ProteinPercent\" + \"CarbohydratePercent\" + \"FatPercent\" = 100)");
                table.HasCheckConstraint("CK_nutrition_target_versions_rest", "(\"RestKilocalories\" IS NULL AND \"RestInputMode\" IS NULL AND \"RestProteinGrams\" IS NULL AND \"RestCarbohydrateGrams\" IS NULL AND \"RestFatGrams\" IS NULL AND \"RestProteinPercent\" IS NULL AND \"RestCarbohydratePercent\" IS NULL AND \"RestFatPercent\" IS NULL) OR (\"RestKilocalories\" > 0 AND \"RestKilocalories\" <= 20000 AND \"RestProteinGrams\" > 0 AND \"RestProteinGrams\" <= 2000 AND \"RestCarbohydrateGrams\" > 0 AND \"RestCarbohydrateGrams\" <= 2000 AND \"RestFatGrams\" > 0 AND \"RestFatGrams\" <= 2000 AND ((\"RestInputMode\" = 'Grams' AND \"RestProteinPercent\" IS NULL AND \"RestCarbohydratePercent\" IS NULL AND \"RestFatPercent\" IS NULL) OR (\"RestInputMode\" = 'Percent' AND \"RestProteinPercent\" > 0 AND \"RestCarbohydratePercent\" > 0 AND \"RestFatPercent\" > 0 AND \"RestProteinPercent\" + \"RestCarbohydratePercent\" + \"RestFatPercent\" = 100)))");
            });
            version.HasKey(item => item.Id);
            version.Property(item => item.Name).HasMaxLength(NutritionLimits.MaxTargetPhaseNameLength).HasDefaultValue("Ziel");
            version.Property(item => item.Category).HasConversion<string>().HasMaxLength(24).HasDefaultValue(NutritionGoalCategory.Custom).HasSentinel((NutritionGoalCategory)(-1));
            version.Property(item => item.InputMode).HasConversion<string>().HasMaxLength(16).HasDefaultValue(NutritionTargetInputMode.Grams).HasSentinel((NutritionTargetInputMode)(-1));
            version.Property(item => item.Kilocalories).HasPrecision(10, 2);
            version.Property(item => item.ProteinGrams).HasPrecision(10, 2);
            version.Property(item => item.CarbohydrateGrams).HasPrecision(10, 2);
            version.Property(item => item.FatGrams).HasPrecision(10, 2);
            version.Property(item => item.SaltGrams).HasPrecision(10, 2);
            version.Property(item => item.FiberGrams).HasPrecision(10, 2);
            version.Property(item => item.ProteinPercent).HasPrecision(5, 2);
            version.Property(item => item.CarbohydratePercent).HasPrecision(5, 2);
            version.Property(item => item.FatPercent).HasPrecision(5, 2);
            version.Property(item => item.RestInputMode).HasConversion<string>().HasMaxLength(16);
            version.Property(item => item.RestKilocalories).HasPrecision(10, 2);
            version.Property(item => item.RestProteinGrams).HasPrecision(10, 2);
            version.Property(item => item.RestCarbohydrateGrams).HasPrecision(10, 2);
            version.Property(item => item.RestFatGrams).HasPrecision(10, 2);
            version.Property(item => item.RestProteinPercent).HasPrecision(5, 2);
            version.Property(item => item.RestCarbohydratePercent).HasPrecision(5, 2);
            version.Property(item => item.RestFatPercent).HasPrecision(5, 2);
            version.Property(item => item.Origin).HasConversion<string>().HasMaxLength(24);
            version.Property(item => item.AlgorithmVersion).HasMaxLength(80);
            version.Property(item => item.Reason).HasMaxLength(500);
            version.HasIndex(item => new { item.UserId, item.NutritionTargetScheduleId, item.EffectiveFrom }).IsUnique();
            version.HasOne(item => item.NutritionTargetSchedule)
                .WithMany(schedule => schedule.Versions)
                .HasForeignKey(item => new { item.UserId, item.NutritionTargetScheduleId })
                .HasPrincipalKey(schedule => new { schedule.UserId, schedule.Id })
                .OnDelete(DeleteBehavior.Cascade);
            version.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureIdentity(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(DatabaseSchemas.Identity);
        modelBuilder.Entity<AppUser>(user =>
        {
            user.ToTable("users", DatabaseSchemas.Identity);
            user.Property(item => item.IsActive).HasDefaultValue(true);
        });
        modelBuilder.Entity<IdentityRole<Guid>>().ToTable("roles", DatabaseSchemas.Identity);
        modelBuilder.Entity<IdentityUserClaim<Guid>>().ToTable("user_claims", DatabaseSchemas.Identity);
        modelBuilder.Entity<IdentityUserLogin<Guid>>().ToTable("user_logins", DatabaseSchemas.Identity);
        modelBuilder.Entity<IdentityUserToken<Guid>>().ToTable("user_tokens", DatabaseSchemas.Identity);
        modelBuilder.Entity<IdentityRoleClaim<Guid>>().ToTable("role_claims", DatabaseSchemas.Identity);
        modelBuilder.Entity<IdentityUserRole<Guid>>().ToTable("user_roles", DatabaseSchemas.Identity);
        // Identity maps passkeys only when its store options request schema version 3, and
        // design-time tooling has no options. The mapping mirrors Identity's own version 3.
        modelBuilder.Entity<IdentityUserPasskey<Guid>>(passkey =>
        {
            passkey.ToTable("user_passkeys", DatabaseSchemas.Identity);
            passkey.HasKey(item => item.CredentialId);
            passkey.Property(item => item.CredentialId).HasMaxLength(1024);
            passkey.HasOne<AppUser>().WithMany().HasForeignKey(item => item.UserId).OnDelete(DeleteBehavior.Cascade);
            passkey.OwnsOne(item => item.Data).ToJson();
        });
        modelBuilder.Entity<AccountInvitation>(invitation =>
        {
            invitation.ToTable("account_invitations", DatabaseSchemas.Identity);
            invitation.HasKey(item => item.Id);
            invitation.Property(item => item.TokenHash).HasColumnType("bytea").IsRequired();
            invitation.Property(item => item.Version).IsConcurrencyToken();
            invitation.HasIndex(item => item.UserId).IsUnique();
            invitation.HasIndex(item => item.TokenHash).IsUnique();
            invitation.HasOne(item => item.User)
                .WithOne()
                .HasForeignKey<AccountInvitation>(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<DeviceSession>(session =>
        {
            session.ToTable("device_sessions", DatabaseSchemas.Identity, table =>
            {
                table.HasCheckConstraint("CK_identity_device_sessions_name", "length(trim(\"DeviceName\")) > 0");
                table.HasCheckConstraint(
                    "CK_identity_device_sessions_token_hash",
                    "octet_length(\"RefreshTokenHash\") = 32");
            });
            session.HasKey(item => item.Id);
            session.Property(item => item.Id).ValueGeneratedNever();
            session.Property(item => item.DeviceName).HasMaxLength(100).IsRequired();
            session.Property(item => item.RefreshTokenHash).HasColumnType("bytea").IsRequired();
            session.Property(item => item.PreviousRefreshTokenHash).HasColumnType("bytea");
            session.Property(item => item.DiscardedRefreshTokenHash).HasColumnType("bytea");
            session.HasIndex(item => item.RefreshTokenHash).IsUnique();
            session.HasIndex(item => item.PreviousRefreshTokenHash).IsUnique();
            session.HasIndex(item => item.DiscardedRefreshTokenHash).IsUnique();
            session.HasIndex(item => item.UserId);
            session.HasOne(item => item.User)
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureTrainingSchedule(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<TrainingSchedule>(schedule =>
        {
            schedule.ToTable("training_schedules", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_training_schedules_mode", "\"Mode\" IN ('cycle', 'weekly')");
                table.HasCheckConstraint(
                    "CK_training_schedules_anchor",
                    "(\"Mode\" = 'cycle') = (\"AnchorDate\" IS NOT NULL)");
            });
            schedule.HasKey(item => item.Id);
            schedule.Property(item => item.UserId).ValueGeneratedNever();
            schedule.Property(item => item.Mode)
                .HasConversion(new ValueConverter<TrainingScheduleMode, string>(
                    value => TrainingScheduleModes.ToWireValue(value),
                    value => TrainingScheduleModes.Parse(value)))
                .HasMaxLength(16)
                .IsRequired();
            schedule.Property(item => item.Version).IsConcurrencyToken();
            schedule.HasIndex(item => item.UserId)
                .IsUnique()
                .HasDatabaseName("UX_training_schedules_one_live_per_user")
                .HasFilter("\"DeletedAtUtc\" IS NULL");
            schedule.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TrainingScheduleSlot>(slot =>
        {
            slot.ToTable("training_schedule_slots", DatabaseSchemas.Training, table =>
                table.HasCheckConstraint("CK_training_schedule_slots_position", PositionNonNegativeCheck));
            slot.HasKey(item => item.Id);
            slot.Property(item => item.UserId).ValueGeneratedNever();
            slot.HasIndex(item => new { item.ScheduleId, item.Position }).IsUnique();
            slot.HasIndex(item => new { item.UserId, item.ScheduleId });
            slot.HasOne<TrainingSchedule>()
                .WithMany()
                .HasForeignKey(item => item.ScheduleId)
                .OnDelete(DeleteBehavior.Cascade);
            slot.HasOne<TrainingPlan>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.PlanId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
            slot.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TrainingScheduleShift>(shift =>
        {
            shift.ToTable("training_schedule_shifts", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_training_schedule_shifts_position", PositionNonNegativeCheck);
                table.HasCheckConstraint("CK_training_schedule_shifts_days", "\"Days\" BETWEEN 1 AND 31");
            });
            shift.HasKey(item => item.Id);
            shift.Property(item => item.UserId).ValueGeneratedNever();
            shift.HasIndex(item => new { item.ScheduleId, item.Position }).IsUnique();
            shift.HasIndex(item => new { item.UserId, item.ScheduleId });
            shift.HasOne<TrainingSchedule>()
                .WithMany()
                .HasForeignKey(item => item.ScheduleId)
                .OnDelete(DeleteBehavior.Cascade);
            shift.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TrainingScheduleException>(exception =>
        {
            exception.ToTable("training_schedule_exceptions", DatabaseSchemas.Training, table =>
                table.HasCheckConstraint("CK_training_schedule_exceptions_position", PositionNonNegativeCheck));
            exception.HasKey(item => item.Id);
            exception.Property(item => item.UserId).ValueGeneratedNever();
            exception.HasIndex(item => new { item.ScheduleId, item.Position }).IsUnique();
            exception.HasIndex(item => new { item.ScheduleId, item.Date, item.PlanId }).IsUnique();
            exception.HasIndex(item => new { item.UserId, item.ScheduleId });
            exception.HasOne<TrainingSchedule>()
                .WithMany()
                .HasForeignKey(item => item.ScheduleId)
                .OnDelete(DeleteBehavior.Cascade);
            exception.HasOne<TrainingPlan>()
                .WithMany()
                .HasForeignKey(item => new { item.UserId, item.PlanId })
                .HasPrincipalKey(item => new { item.UserId, item.Id })
                .OnDelete(DeleteBehavior.Restrict);
            exception.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ApplyStorageConventions(IMutableModel model)
    {
        foreach (IMutableProperty property in model.GetEntityTypes().SelectMany(entity => entity.GetProperties()))
        {
            Type propertyType = Nullable.GetUnderlyingType(property.ClrType) ?? property.ClrType;
            ApplyTypeConvention(property, propertyType);
            ApplyNamedConvention(property, propertyType);
        }
    }

    private static void ApplyTypeConvention(IMutableProperty property, Type propertyType)
    {
        if (propertyType == typeof(Guid))
        {
            property.SetColumnType("uuid");
        }
        else if (propertyType == typeof(DateTime) || propertyType == typeof(DateTimeOffset))
        {
            property.SetColumnType("timestamp with time zone");
        }
        else if (propertyType == typeof(DateOnly))
        {
            property.SetColumnType("date");
        }
    }

    private static void ApplyNamedConvention(IMutableProperty property, Type propertyType)
    {
        if (property.Name == "UserId" && propertyType == typeof(Guid))
        {
            property.IsNullable = false;
            property.ValueGenerated = ValueGenerated.Never;
        }

        if (property.Name == "Version" && propertyType == typeof(long))
        {
            property.SetColumnType("bigint");
            property.IsConcurrencyToken = true;
        }
    }

    private void ApplyUserQueryFilters(ModelBuilder modelBuilder)
    {
        Expression<Func<Guid>> currentUserId = () => CurrentUserId;

        foreach (Type clrType in modelBuilder.Model.GetEntityTypes()
                     .Where(entity => typeof(IUserOwnedEntity).IsAssignableFrom(entity.ClrType))
                     .Select(entityType => entityType.ClrType))
        {
            ParameterExpression entity = Expression.Parameter(clrType, "entity");
            MemberExpression owner = Expression.Property(entity, nameof(IUserOwnedEntity.UserId));
            LambdaExpression filter = Expression.Lambda(Expression.Equal(owner, currentUserId.Body), entity);
            modelBuilder.Entity(clrType).HasQueryFilter(filter);
        }
    }
}
