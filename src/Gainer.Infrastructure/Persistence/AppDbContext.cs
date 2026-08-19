using System.Linq.Expressions;
using System.Reflection;
using Gainer.Core.Security;
using Gainer.Core.BodyTracking;
using Gainer.Core.Training;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Catalog;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Provides the single transactional boundary for identity and application data.</summary>
public class AppDbContext(DbContextOptions<AppDbContext> options, IUserContext userContext)
    : IdentityDbContext<AppUser, IdentityRole<Guid>, Guid>(options)
{
    /// <summary>Hash-only metadata for pending account invitations.</summary>
    public DbSet<AccountInvitation> AccountInvitations => Set<AccountInvitation>();

    public DbSet<BodyGoal> BodyGoals => Set<BodyGoal>();

    public DbSet<DailyCheckIn> DailyCheckIns => Set<DailyCheckIn>();

    public DbSet<Exercise> Exercises => Set<Exercise>();

    public DbSet<WorkoutTemplate> WorkoutTemplates => Set<WorkoutTemplate>();

    public DbSet<WorkoutTemplateItem> WorkoutTemplateItems => Set<WorkoutTemplateItem>();

    public DbSet<WorkoutRotation> WorkoutRotations => Set<WorkoutRotation>();

    public DbSet<WorkoutRotationItem> WorkoutRotationItems => Set<WorkoutRotationItem>();

    public DbSet<Workout> Workouts => Set<Workout>();

    public DbSet<WorkoutExercise> WorkoutExercises => Set<WorkoutExercise>();

    public DbSet<WorkoutSet> WorkoutSets => Set<WorkoutSet>();

    public DbSet<SyncClient> SyncClients => Set<SyncClient>();

    public DbSet<UserSyncState> UserSyncStates => Set<UserSyncState>();

    public DbSet<ProcessedMutation> ProcessedMutations => Set<ProcessedMutation>();

    public DbSet<ChangeBatch> ChangeBatches => Set<ChangeBatch>();

    public DbSet<ChangeItem> ChangeItems => Set<ChangeItem>();

    private Guid CurrentUserId => userContext.UserId ?? Guid.Empty;

    /// <inheritdoc />
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        ConfigureIdentity(modelBuilder);
        ConfigureBodyTracking(modelBuilder);
        ConfigureTraining(modelBuilder);
        ConfigureSync(modelBuilder);
        ApplyStorageConventions(modelBuilder.Model);
        ApplyUserQueryFilters(modelBuilder);
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
                table.HasCheckConstraint("CK_change_items_position", "\"Position\" >= 0");
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
                table.HasCheckConstraint("CK_exercises_name", "length(trim(\"Name\")) > 0");
                table.HasCheckConstraint(
                    "CK_exercises_catalog_ownership",
                    "(\"OwnerUserId\" IS NULL AND \"CatalogVersion\" IS NOT NULL AND \"IsArchived\" = FALSE) OR " +
                    "(\"OwnerUserId\" IS NOT NULL AND \"CatalogVersion\" IS NULL)");
            });
            exercise.HasKey(item => item.Id);
            exercise.Property(item => item.Name).HasMaxLength(160).IsRequired();
            exercise.Property(item => item.Description).HasMaxLength(2_000);
            exercise.Property(item => item.TargetMuscle).HasMaxLength(100);
            exercise.Property(item => item.MuscleGroup).HasMaxLength(100);
            exercise.Property(item => item.Equipment).HasMaxLength(100);
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

            DateTime catalogTimestamp = new(2026, 8, 18, 0, 0, 0, DateTimeKind.Utc);
            exercise.HasData(ExerciseCatalogSnapshot.Document.Entries.Select(item => new Exercise
            {
                Id = item.Id,
                Name = item.Name,
                TargetMuscle = item.TargetMuscle,
                MuscleGroup = item.MuscleGroup,
                Equipment = item.Equipment,
                CatalogVersion = ExerciseCatalogSnapshot.Document.CatalogVersion,
                CreatedAtUtc = catalogTimestamp,
                UpdatedAtUtc = catalogTimestamp,
                Version = 1,
            }));
        });

        modelBuilder.Entity<WorkoutTemplate>(template =>
        {
            template.ToTable("workout_templates", DatabaseSchemas.Training, table =>
                table.HasCheckConstraint("CK_workout_templates_name", "length(trim(\"Name\")) > 0"));
            template.HasKey(item => item.Id);
            template.Property(item => item.Name).HasMaxLength(160).IsRequired();
            template.Property(item => item.Version).IsConcurrencyToken();
            template.HasIndex(item => new { item.UserId, item.Name });
            template.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WorkoutTemplateItem>(item =>
        {
            item.ToTable("workout_template_items", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workout_template_items_position", "\"Position\" >= 0");
                table.HasCheckConstraint("CK_workout_template_items_sets", "\"PlannedSets\" > 0");
                table.HasCheckConstraint(
                    "CK_workout_template_items_repetitions",
                    "\"MinimumRepetitions\" > 0 AND \"MaximumRepetitions\" >= \"MinimumRepetitions\"");
                table.HasCheckConstraint(
                    "CK_workout_template_items_rir",
                    "\"TargetRir\" IS NULL OR (\"TargetRir\" >= 0 AND \"TargetRir\" <= 10)");
                table.HasCheckConstraint(
                    "CK_workout_template_items_rest",
                    "\"RestSeconds\" IS NULL OR \"RestSeconds\" >= 0");
            });
            item.HasKey(value => value.Id);
            item.Property(value => value.TargetRir).HasPrecision(4, 2);
            item.Property(value => value.Notes).HasMaxLength(2_000);
            item.HasIndex(value => new { value.TemplateId, value.Position }).IsUnique();
            item.HasIndex(value => new { value.UserId, value.TemplateId });
            item.HasOne<WorkoutTemplate>()
                .WithMany()
                .HasForeignKey(value => value.TemplateId)
                .OnDelete(DeleteBehavior.Cascade);
            item.HasOne<Exercise>()
                .WithMany()
                .HasForeignKey(value => value.ExerciseId)
                .OnDelete(DeleteBehavior.Restrict);
            item.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(value => value.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WorkoutRotation>(rotation =>
        {
            rotation.ToTable("workout_rotations", DatabaseSchemas.Training);
            rotation.HasKey(item => item.Id);
            rotation.Property(item => item.Version).IsConcurrencyToken();
            rotation.HasIndex(item => item.UserId).IsUnique();
            rotation.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            rotation.HasOne<WorkoutTemplate>()
                .WithMany()
                .HasForeignKey(item => item.LastCompletedTemplateId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<WorkoutRotationItem>(item =>
        {
            item.ToTable("workout_rotation_items", DatabaseSchemas.Training, table =>
                table.HasCheckConstraint("CK_workout_rotation_items_position", "\"Position\" >= 0"));
            item.HasKey(value => value.Id);
            item.HasIndex(value => new { value.RotationId, value.Position }).IsUnique();
            item.HasIndex(value => new { value.RotationId, value.TemplateId }).IsUnique();
            item.HasIndex(value => new { value.UserId, value.RotationId });
            item.HasOne<WorkoutRotation>()
                .WithMany()
                .HasForeignKey(value => value.RotationId)
                .OnDelete(DeleteBehavior.Cascade);
            item.HasOne<WorkoutTemplate>()
                .WithMany()
                .HasForeignKey(value => value.TemplateId)
                .OnDelete(DeleteBehavior.Cascade);
            item.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(value => value.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Workout>(workout =>
        {
            workout.ToTable("workouts", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workouts_template_name", "length(trim(\"TemplateNameSnapshot\")) > 0");
                table.HasCheckConstraint(
                    "CK_workouts_status",
                    "(\"Status\" = 'Running' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NULL) OR " +
                    "(\"Status\" = 'Completed' AND \"CompletedAtUtc\" IS NOT NULL AND \"DiscardedAtUtc\" IS NULL) OR " +
                    "(\"Status\" = 'Discarded' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NOT NULL)");
            });
            workout.HasKey(item => item.Id);
            workout.HasAlternateKey(item => new { item.UserId, item.Id });
            workout.Property(item => item.UserId).ValueGeneratedNever();
            workout.Property(item => item.TemplateNameSnapshot).HasMaxLength(160).IsRequired();
            workout.Property(item => item.Status).HasConversion<string>().HasMaxLength(16);
            workout.Property(item => item.Version).IsConcurrencyToken();
            workout.HasIndex(item => new { item.UserId, item.CompletedAtUtc }).IsDescending(false, true);
            workout.HasOne<AppUser>()
                .WithMany()
                .HasForeignKey(item => item.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            workout.HasOne<WorkoutTemplate>()
                .WithMany()
                .HasForeignKey(item => item.SourceTemplateId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<WorkoutExercise>(exercise =>
        {
            exercise.ToTable("workout_exercises", DatabaseSchemas.Training, table =>
            {
                table.HasCheckConstraint("CK_workout_exercises_name", "length(trim(\"ExerciseNameSnapshot\")) > 0");
                table.HasCheckConstraint("CK_workout_exercises_position", "\"Position\" >= 0");
                table.HasCheckConstraint("CK_workout_exercises_sets", "\"PlannedSets\" > 0");
                table.HasCheckConstraint(
                    "CK_workout_exercises_repetitions",
                    "\"MinimumRepetitions\" > 0 AND \"MaximumRepetitions\" >= \"MinimumRepetitions\"");
                table.HasCheckConstraint(
                    "CK_workout_exercises_rir",
                    "\"TargetRir\" IS NULL OR (\"TargetRir\" >= 0 AND \"TargetRir\" <= 10)");
                table.HasCheckConstraint(
                    "CK_workout_exercises_rest",
                    "\"RestSeconds\" IS NULL OR \"RestSeconds\" >= 0");
            });
            exercise.HasKey(item => item.Id);
            exercise.HasAlternateKey(item => new { item.UserId, item.Id });
            exercise.Property(item => item.UserId).ValueGeneratedNever();
            exercise.Property(item => item.ExerciseNameSnapshot).HasMaxLength(160).IsRequired();
            exercise.Property(item => item.TargetRir).HasPrecision(4, 2);
            exercise.Property(item => item.Notes).HasMaxLength(2_000);
            exercise.HasIndex(item => new { item.WorkoutId, item.Position }).IsUnique();
            exercise.HasIndex(item => new { item.UserId, item.SourceExerciseId, item.WorkoutCompletedAtUtc })
                .IsDescending(false, false, true);
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
                table.HasCheckConstraint("CK_workout_sets_position", "\"Position\" >= 0");
                table.HasCheckConstraint("CK_workout_sets_weight", "\"WeightKg\" IS NULL OR \"WeightKg\" >= 0");
                table.HasCheckConstraint("CK_workout_sets_repetitions", "\"Repetitions\" IS NULL OR \"Repetitions\" > 0");
                table.HasCheckConstraint("CK_workout_sets_rir", "\"Rir\" IS NULL OR (\"Rir\" >= 0 AND \"Rir\" <= 10)");
                table.HasCheckConstraint(
                    "CK_workout_sets_completion",
                    "(\"IsCompleted\" = FALSE AND \"CompletedAtUtc\" IS NULL) OR " +
                    "(\"IsCompleted\" = TRUE AND \"CompletedAtUtc\" IS NOT NULL AND \"WeightKg\" IS NOT NULL AND \"Repetitions\" IS NOT NULL)");
            });
            set.HasKey(item => item.Id);
            set.Property(item => item.UserId).ValueGeneratedNever();
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
        PropertyInfo currentUserProperty = typeof(AppDbContext).GetProperty(
            nameof(CurrentUserId),
            BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("The current-user model property is unavailable.");

        foreach (IMutableEntityType entityType in modelBuilder.Model.GetEntityTypes()
                     .Where(entity => typeof(IUserOwnedEntity).IsAssignableFrom(entity.ClrType)))
        {
            ParameterExpression entity = Expression.Parameter(entityType.ClrType, "entity");
            MemberExpression owner = Expression.Property(entity, nameof(IUserOwnedEntity.UserId));
            MemberExpression currentUser = Expression.Property(Expression.Constant(this), currentUserProperty);
            LambdaExpression filter = Expression.Lambda(Expression.Equal(owner, currentUser), entity);
            modelBuilder.Entity(entityType.ClrType).HasQueryFilter(filter);
        }
    }
}
