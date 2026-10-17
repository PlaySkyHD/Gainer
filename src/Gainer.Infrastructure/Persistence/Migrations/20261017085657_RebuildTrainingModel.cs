using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class RebuildTrainingModel : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Data reset (D11): legacy workout, template and rotation rows are dropped without migration.
        migrationBuilder.DropTable(name: "workout_rotation_items", schema: "training");
        migrationBuilder.DropTable(name: "workout_rotations", schema: "training");
        migrationBuilder.DropTable(name: "workout_sets", schema: "training");
        migrationBuilder.DropTable(name: "workout_exercises", schema: "training");
        migrationBuilder.DropTable(name: "workouts", schema: "training");
        migrationBuilder.DropTable(name: "workout_template_items", schema: "training");
        migrationBuilder.DropTable(name: "workout_templates", schema: "training");

        // Sync idempotency receipts and change history of the removed and reset resource types.
        migrationBuilder.Sql(
            """
            DELETE FROM sync.change_batches
            WHERE "Id" IN (
                SELECT "BatchId" FROM sync.change_items
                WHERE "ResourceType" IN ('Workout', 'WorkoutTemplate', 'WorkoutRotation', 'CustomExercise'));
            """);
        migrationBuilder.Sql(
            """
            DELETE FROM sync.processed_mutations
            WHERE "ResultJson"::text ~ '"resourceType"\s*:\s*"(Workout|WorkoutTemplate|WorkoutRotation|CustomExercise)"';
            """);

        // Own exercises are reset; their category assignments cascade.
        migrationBuilder.Sql("DELETE FROM training.exercises WHERE \"OwnerUserId\" IS NOT NULL;");

        migrationBuilder.CreateTable(
            name: "training_plans",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                PreviousValueSource = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                SortOrder = table.Column<int>(type: "integer", nullable: false),
                IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_plans", x => x.Id);
                table.UniqueConstraint("AK_training_plans_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_training_plans_name", "length(trim(\"Name\")) > 0");
                table.CheckConstraint("CK_training_plans_previous_value_source", "\"PreviousValueSource\" IN ('exercise', 'plan', 'workout')");
                table.CheckConstraint("CK_training_plans_sort_order", "\"SortOrder\" >= 0");
                table.ForeignKey(
                    name: "FK_training_plans_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "training_plan_entries",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                ExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                WarmupSets = table.Column<int>(type: "integer", nullable: false),
                WorkingSets = table.Column<int>(type: "integer", nullable: false),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                SupersetId = table.Column<Guid>(type: "uuid", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_plan_entries", x => x.Id);
                table.CheckConstraint("CK_training_plan_entries_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_training_plan_entries_sets", "\"WarmupSets\" + \"WorkingSets\" BETWEEN 1 AND 50");
                table.CheckConstraint("CK_training_plan_entries_warmup_sets", "\"WarmupSets\" BETWEEN 0 AND 20");
                table.CheckConstraint("CK_training_plan_entries_working_sets", "\"WorkingSets\" BETWEEN 0 AND 50");
                table.ForeignKey(
                    name: "FK_training_plan_entries_exercises_ExerciseId",
                    column: x => x.ExerciseId,
                    principalSchema: "training",
                    principalTable: "exercises",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_training_plan_entries_training_plans_UserId_PlanId",
                    columns: x => new { x.UserId, x.PlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_training_plan_entries_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "workouts",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Title = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                StartedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                EndedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                PreviousValueSource = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                SourcePlanId = table.Column<Guid>(type: "uuid", nullable: true),
                SourceWorkoutId = table.Column<Guid>(type: "uuid", nullable: true),
                DeletedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workouts", x => x.Id);
                table.UniqueConstraint("AK_workouts_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_workouts_end_after_start", "\"EndedAtUtc\" IS NULL OR \"EndedAtUtc\" > \"StartedAtUtc\"");
                table.CheckConstraint("CK_workouts_previous_value_source", "\"PreviousValueSource\" IN ('exercise', 'plan', 'workout')");
                table.CheckConstraint("CK_workouts_title", "length(trim(\"Title\")) > 0");
                table.ForeignKey(
                    name: "FK_workouts_training_plans_UserId_SourcePlanId",
                    columns: x => new { x.UserId, x.SourcePlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_workouts_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workouts_workouts_UserId_SourceWorkoutId",
                    columns: x => new { x.UserId, x.SourceWorkoutId },
                    principalSchema: "training",
                    principalTable: "workouts",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
            });

        migrationBuilder.CreateTable(
            name: "workout_exercises",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                WorkoutId = table.Column<Guid>(type: "uuid", nullable: false),
                SourceExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                ExerciseNameSnapshot = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                ExerciseTypeSnapshot = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                SupersetId = table.Column<Guid>(type: "uuid", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_exercises", x => x.Id);
                table.UniqueConstraint("AK_workout_exercises_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_workout_exercises_name", "length(trim(\"ExerciseNameSnapshot\")) > 0");
                table.CheckConstraint("CK_workout_exercises_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_workout_exercises_exercises_SourceExerciseId",
                    column: x => x.SourceExerciseId,
                    principalSchema: "training",
                    principalTable: "exercises",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_workout_exercises_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_exercises_workouts_UserId_WorkoutId",
                    columns: x => new { x.UserId, x.WorkoutId },
                    principalSchema: "training",
                    principalTable: "workouts",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "workout_sets",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                WorkoutId = table.Column<Guid>(type: "uuid", nullable: false),
                WorkoutExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                SetType = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                WeightKg = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                Repetitions = table.Column<int>(type: "integer", nullable: true),
                Rir = table.Column<decimal>(type: "numeric(4,2)", precision: 4, scale: 2, nullable: true),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_sets", x => x.Id);
                table.CheckConstraint("CK_workout_sets_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_workout_sets_repetitions", "\"Repetitions\" IS NULL OR (\"Repetitions\" >= 0 AND \"Repetitions\" <= 10000)");
                table.CheckConstraint("CK_workout_sets_rir", "\"Rir\" IS NULL OR (\"Rir\" >= 0 AND \"Rir\" <= 10)");
                table.CheckConstraint("CK_workout_sets_type", "\"SetType\" IN ('normal', 'warmup', 'dropset')");
                table.CheckConstraint("CK_workout_sets_weight", "\"WeightKg\" IS NULL OR (\"WeightKg\" >= 0 AND \"WeightKg\" <= 10000)");
                table.ForeignKey(
                    name: "FK_workout_sets_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_sets_workout_exercises_UserId_WorkoutExerciseId",
                    columns: x => new { x.UserId, x.WorkoutExerciseId },
                    principalSchema: "training",
                    principalTable: "workout_exercises",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_sets_workouts_UserId_WorkoutId",
                    columns: x => new { x.UserId, x.WorkoutId },
                    principalSchema: "training",
                    principalTable: "workouts",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "workout_rotations",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_rotations", x => x.Id);
                table.ForeignKey(
                    name: "FK_workout_rotations_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "workout_rotation_items",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                RotationId = table.Column<Guid>(type: "uuid", nullable: false),
                PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_rotation_items", x => x.Id);
                table.CheckConstraint("CK_workout_rotation_items_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_workout_rotation_items_training_plans_UserId_PlanId",
                    columns: x => new { x.UserId, x.PlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_workout_rotation_items_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_rotation_items_workout_rotations_RotationId",
                    column: x => x.RotationId,
                    principalSchema: "training",
                    principalTable: "workout_rotations",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_workouts_UserId_EndedAtUtc",
            schema: "training",
            table: "workouts",
            columns: new[] { "UserId", "EndedAtUtc" },
            descending: new[] { false, true });

        migrationBuilder.CreateIndex(
            name: "IX_workouts_UserId_SourcePlanId",
            schema: "training",
            table: "workouts",
            columns: new[] { "UserId", "SourcePlanId" });

        migrationBuilder.CreateIndex(
            name: "IX_workouts_UserId_SourceWorkoutId",
            schema: "training",
            table: "workouts",
            columns: new[] { "UserId", "SourceWorkoutId" });

        migrationBuilder.CreateIndex(
            name: "UX_workouts_one_active_per_user",
            schema: "training",
            table: "workouts",
            column: "UserId",
            unique: true,
            filter: "\"EndedAtUtc\" IS NULL AND \"DeletedAtUtc\" IS NULL");

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_SourceExerciseId",
            schema: "training",
            table: "workout_exercises",
            column: "SourceExerciseId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_UserId_SourceExerciseId",
            schema: "training",
            table: "workout_exercises",
            columns: new[] { "UserId", "SourceExerciseId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_UserId_WorkoutId",
            schema: "training",
            table: "workout_exercises",
            columns: new[] { "UserId", "WorkoutId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_WorkoutId_Position",
            schema: "training",
            table: "workout_exercises",
            columns: new[] { "WorkoutId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_sets_UserId_WorkoutExerciseId",
            schema: "training",
            table: "workout_sets",
            columns: new[] { "UserId", "WorkoutExerciseId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_sets_UserId_WorkoutId",
            schema: "training",
            table: "workout_sets",
            columns: new[] { "UserId", "WorkoutId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_sets_WorkoutExerciseId_Position",
            schema: "training",
            table: "workout_sets",
            columns: new[] { "WorkoutExerciseId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotations_UserId",
            schema: "training",
            table: "workout_rotations",
            column: "UserId",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_PlanId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "PlanId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_Position",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_UserId_PlanId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "UserId", "PlanId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_UserId_RotationId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "UserId", "RotationId" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropForeignKey(
            name: "FK_workout_rotation_items_training_plans_UserId_PlanId",
            schema: "training",
            table: "workout_rotation_items");

        migrationBuilder.DropForeignKey(
            name: "FK_workouts_training_plans_UserId_SourcePlanId",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropForeignKey(
            name: "FK_workouts_workouts_UserId_SourceWorkoutId",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropTable(
            name: "training_plan_entries",
            schema: "training");

        migrationBuilder.DropTable(
            name: "training_plans",
            schema: "training");

        migrationBuilder.DropIndex(
            name: "IX_workouts_UserId_EndedAtUtc",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropIndex(
            name: "IX_workouts_UserId_SourcePlanId",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropIndex(
            name: "IX_workouts_UserId_SourceWorkoutId",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropIndex(
            name: "UX_workouts_one_active_per_user",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workouts_end_after_start",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workouts_previous_value_source",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workouts_title",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workout_sets_repetitions",
            schema: "training",
            table: "workout_sets");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workout_sets_type",
            schema: "training",
            table: "workout_sets");

        migrationBuilder.DropCheckConstraint(
            name: "CK_workout_sets_weight",
            schema: "training",
            table: "workout_sets");

        migrationBuilder.DropIndex(
            name: "IX_workout_rotation_items_UserId_PlanId",
            schema: "training",
            table: "workout_rotation_items");

        migrationBuilder.DropIndex(
            name: "IX_workout_exercises_UserId_SourceExerciseId",
            schema: "training",
            table: "workout_exercises");

        migrationBuilder.DropColumn(
            name: "CreatedAtUtc",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropColumn(
            name: "Notes",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropColumn(
            name: "SourcePlanId",
            schema: "training",
            table: "workouts");

        migrationBuilder.DropColumn(
            name: "SetType",
            schema: "training",
            table: "workout_sets");

        migrationBuilder.DropColumn(
            name: "ExerciseTypeSnapshot",
            schema: "training",
            table: "workout_exercises");

        migrationBuilder.DropColumn(
            name: "SupersetId",
            schema: "training",
            table: "workout_exercises");

        migrationBuilder.RenameColumn(
            name: "Title",
            schema: "training",
            table: "workouts",
            newName: "TemplateNameSnapshot");

        migrationBuilder.RenameColumn(
            name: "SourceWorkoutId",
            schema: "training",
            table: "workouts",
            newName: "SourceTemplateId");

        migrationBuilder.RenameColumn(
            name: "PreviousValueSource",
            schema: "training",
            table: "workouts",
            newName: "Status");

        migrationBuilder.RenameColumn(
            name: "EndedAtUtc",
            schema: "training",
            table: "workouts",
            newName: "DiscardedAtUtc");

        migrationBuilder.RenameColumn(
            name: "DeletedAtUtc",
            schema: "training",
            table: "workouts",
            newName: "CompletedAtUtc");

        migrationBuilder.RenameColumn(
            name: "PlanId",
            schema: "training",
            table: "workout_rotation_items",
            newName: "TemplateId");

        migrationBuilder.RenameIndex(
            name: "IX_workout_rotation_items_RotationId_PlanId",
            schema: "training",
            table: "workout_rotation_items",
            newName: "IX_workout_rotation_items_RotationId_TemplateId");

        migrationBuilder.AddColumn<DateTime>(
            name: "CompletedAtUtc",
            schema: "training",
            table: "workout_sets",
            type: "timestamp with time zone",
            nullable: true);

        migrationBuilder.AddColumn<bool>(
            name: "IsCompleted",
            schema: "training",
            table: "workout_sets",
            type: "boolean",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<Guid>(
            name: "LastCompletedTemplateId",
            schema: "training",
            table: "workout_rotations",
            type: "uuid",
            nullable: true);

        migrationBuilder.AlterColumn<Guid>(
            name: "SourceExerciseId",
            schema: "training",
            table: "workout_exercises",
            type: "uuid",
            nullable: true,
            oldClrType: typeof(Guid),
            oldType: "uuid");

        migrationBuilder.AddColumn<int>(
            name: "MaximumRepetitions",
            schema: "training",
            table: "workout_exercises",
            type: "integer",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<int>(
            name: "MinimumRepetitions",
            schema: "training",
            table: "workout_exercises",
            type: "integer",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<int>(
            name: "PlannedSets",
            schema: "training",
            table: "workout_exercises",
            type: "integer",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<int>(
            name: "RestSeconds",
            schema: "training",
            table: "workout_exercises",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "TargetRir",
            schema: "training",
            table: "workout_exercises",
            type: "numeric(4,2)",
            precision: 4,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<DateTime>(
            name: "WorkoutCompletedAtUtc",
            schema: "training",
            table: "workout_exercises",
            type: "timestamp with time zone",
            nullable: true);

        migrationBuilder.CreateTable(
            name: "workout_templates",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                Name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_templates", x => x.Id);
                table.CheckConstraint("CK_workout_templates_name", "length(trim(\"Name\")) > 0");
                table.ForeignKey(
                    name: "FK_workout_templates_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "workout_template_items",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                MaximumRepetitions = table.Column<int>(type: "integer", nullable: false),
                MinimumRepetitions = table.Column<int>(type: "integer", nullable: false),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                PlannedSets = table.Column<int>(type: "integer", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                RestSeconds = table.Column<int>(type: "integer", nullable: true),
                TargetRir = table.Column<decimal>(type: "numeric(4,2)", precision: 4, scale: 2, nullable: true),
                TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_template_items", x => x.Id);
                table.CheckConstraint("CK_workout_template_items_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_workout_template_items_repetitions", "\"MinimumRepetitions\" > 0 AND \"MaximumRepetitions\" >= \"MinimumRepetitions\"");
                table.CheckConstraint("CK_workout_template_items_rest", "\"RestSeconds\" IS NULL OR \"RestSeconds\" >= 0");
                table.CheckConstraint("CK_workout_template_items_rir", "\"TargetRir\" IS NULL OR (\"TargetRir\" >= 0 AND \"TargetRir\" <= 10)");
                table.CheckConstraint("CK_workout_template_items_sets", "\"PlannedSets\" > 0");
                table.ForeignKey(
                    name: "FK_workout_template_items_exercises_ExerciseId",
                    column: x => x.ExerciseId,
                    principalSchema: "training",
                    principalTable: "exercises",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_workout_template_items_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_template_items_workout_templates_TemplateId",
                    column: x => x.TemplateId,
                    principalSchema: "training",
                    principalTable: "workout_templates",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_workouts_SourceTemplateId",
            schema: "training",
            table: "workouts",
            column: "SourceTemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_workouts_UserId_CompletedAtUtc",
            schema: "training",
            table: "workouts",
            columns: new[] { "UserId", "CompletedAtUtc" },
            descending: new[] { false, true });

        migrationBuilder.AddCheckConstraint(
            name: "CK_workouts_status",
            schema: "training",
            table: "workouts",
            sql: "(\"Status\" = 'Running' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NULL) OR (\"Status\" = 'Completed' AND \"CompletedAtUtc\" IS NOT NULL AND \"DiscardedAtUtc\" IS NULL) OR (\"Status\" = 'Discarded' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NOT NULL)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workouts_template_name",
            schema: "training",
            table: "workouts",
            sql: "length(trim(\"TemplateNameSnapshot\")) > 0");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_sets_completion",
            schema: "training",
            table: "workout_sets",
            sql: "(\"IsCompleted\" = FALSE AND \"CompletedAtUtc\" IS NULL) OR (\"IsCompleted\" = TRUE AND \"CompletedAtUtc\" IS NOT NULL AND \"WeightKg\" IS NOT NULL AND \"Repetitions\" IS NOT NULL)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_sets_repetitions",
            schema: "training",
            table: "workout_sets",
            sql: "\"Repetitions\" IS NULL OR \"Repetitions\" > 0");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_sets_weight",
            schema: "training",
            table: "workout_sets",
            sql: "\"WeightKg\" IS NULL OR \"WeightKg\" >= 0");

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotations_LastCompletedTemplateId",
            schema: "training",
            table: "workout_rotations",
            column: "LastCompletedTemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_TemplateId",
            schema: "training",
            table: "workout_rotation_items",
            column: "TemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_UserId_SourceExerciseId_WorkoutCompletedA~",
            schema: "training",
            table: "workout_exercises",
            columns: new[] { "UserId", "SourceExerciseId", "WorkoutCompletedAtUtc" },
            descending: new[] { false, false, true });

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_exercises_repetitions",
            schema: "training",
            table: "workout_exercises",
            sql: "\"MinimumRepetitions\" > 0 AND \"MaximumRepetitions\" >= \"MinimumRepetitions\"");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_exercises_rest",
            schema: "training",
            table: "workout_exercises",
            sql: "\"RestSeconds\" IS NULL OR \"RestSeconds\" >= 0");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_exercises_rir",
            schema: "training",
            table: "workout_exercises",
            sql: "\"TargetRir\" IS NULL OR (\"TargetRir\" >= 0 AND \"TargetRir\" <= 10)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_workout_exercises_sets",
            schema: "training",
            table: "workout_exercises",
            sql: "\"PlannedSets\" > 0");

        migrationBuilder.CreateIndex(
            name: "IX_workout_template_items_ExerciseId",
            schema: "training",
            table: "workout_template_items",
            column: "ExerciseId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_template_items_TemplateId_Position",
            schema: "training",
            table: "workout_template_items",
            columns: new[] { "TemplateId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_template_items_UserId_TemplateId",
            schema: "training",
            table: "workout_template_items",
            columns: new[] { "UserId", "TemplateId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_templates_UserId_Name",
            schema: "training",
            table: "workout_templates",
            columns: new[] { "UserId", "Name" });

        migrationBuilder.AddForeignKey(
            name: "FK_workout_rotation_items_workout_templates_TemplateId",
            schema: "training",
            table: "workout_rotation_items",
            column: "TemplateId",
            principalSchema: "training",
            principalTable: "workout_templates",
            principalColumn: "Id",
            onDelete: ReferentialAction.Cascade);

        migrationBuilder.AddForeignKey(
            name: "FK_workout_rotations_workout_templates_LastCompletedTemplateId",
            schema: "training",
            table: "workout_rotations",
            column: "LastCompletedTemplateId",
            principalSchema: "training",
            principalTable: "workout_templates",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);

        migrationBuilder.AddForeignKey(
            name: "FK_workouts_workout_templates_SourceTemplateId",
            schema: "training",
            table: "workouts",
            column: "SourceTemplateId",
            principalSchema: "training",
            principalTable: "workout_templates",
            principalColumn: "Id",
            onDelete: ReferentialAction.Restrict);
    }
}
