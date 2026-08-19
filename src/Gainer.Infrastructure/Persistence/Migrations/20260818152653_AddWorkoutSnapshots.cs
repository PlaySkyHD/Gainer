using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddWorkoutSnapshots : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "workouts",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                SourceTemplateId = table.Column<Guid>(type: "uuid", nullable: true),
                TemplateNameSnapshot = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                StartedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                CompletedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                DiscardedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workouts", x => x.Id);
                table.UniqueConstraint("AK_workouts_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_workouts_status", "(\"Status\" = 'Running' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NULL) OR (\"Status\" = 'Completed' AND \"CompletedAtUtc\" IS NOT NULL AND \"DiscardedAtUtc\" IS NULL) OR (\"Status\" = 'Discarded' AND \"CompletedAtUtc\" IS NULL AND \"DiscardedAtUtc\" IS NOT NULL)");
                table.CheckConstraint("CK_workouts_template_name", "length(trim(\"TemplateNameSnapshot\")) > 0");
                table.ForeignKey(
                    name: "FK_workouts_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workouts_workout_templates_SourceTemplateId",
                    column: x => x.SourceTemplateId,
                    principalSchema: "training",
                    principalTable: "workout_templates",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
            });

        migrationBuilder.CreateTable(
            name: "workout_exercises",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                WorkoutId = table.Column<Guid>(type: "uuid", nullable: false),
                SourceExerciseId = table.Column<Guid>(type: "uuid", nullable: true),
                ExerciseNameSnapshot = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                PlannedSets = table.Column<int>(type: "integer", nullable: false),
                MinimumRepetitions = table.Column<int>(type: "integer", nullable: false),
                MaximumRepetitions = table.Column<int>(type: "integer", nullable: false),
                TargetRir = table.Column<decimal>(type: "numeric(4,2)", precision: 4, scale: 2, nullable: true),
                RestSeconds = table.Column<int>(type: "integer", nullable: true),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                WorkoutCompletedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_exercises", x => x.Id);
                table.UniqueConstraint("AK_workout_exercises_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_workout_exercises_name", "length(trim(\"ExerciseNameSnapshot\")) > 0");
                table.CheckConstraint("CK_workout_exercises_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_workout_exercises_repetitions", "\"MinimumRepetitions\" > 0 AND \"MaximumRepetitions\" >= \"MinimumRepetitions\"");
                table.CheckConstraint("CK_workout_exercises_rest", "\"RestSeconds\" IS NULL OR \"RestSeconds\" >= 0");
                table.CheckConstraint("CK_workout_exercises_rir", "\"TargetRir\" IS NULL OR (\"TargetRir\" >= 0 AND \"TargetRir\" <= 10)");
                table.CheckConstraint("CK_workout_exercises_sets", "\"PlannedSets\" > 0");
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
                WeightKg = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                Repetitions = table.Column<int>(type: "integer", nullable: true),
                Rir = table.Column<decimal>(type: "numeric(4,2)", precision: 4, scale: 2, nullable: true),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                IsCompleted = table.Column<bool>(type: "boolean", nullable: false),
                CompletedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_sets", x => x.Id);
                table.CheckConstraint("CK_workout_sets_completion", "(\"IsCompleted\" = FALSE AND \"CompletedAtUtc\" IS NULL) OR (\"IsCompleted\" = TRUE AND \"CompletedAtUtc\" IS NOT NULL AND \"WeightKg\" IS NOT NULL AND \"Repetitions\" IS NOT NULL)");
                table.CheckConstraint("CK_workout_sets_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_workout_sets_repetitions", "\"Repetitions\" IS NULL OR \"Repetitions\" > 0");
                table.CheckConstraint("CK_workout_sets_rir", "\"Rir\" IS NULL OR (\"Rir\" >= 0 AND \"Rir\" <= 10)");
                table.CheckConstraint("CK_workout_sets_weight", "\"WeightKg\" IS NULL OR \"WeightKg\" >= 0");
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

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_SourceExerciseId",
            schema: "training",
            table: "workout_exercises",
            column: "SourceExerciseId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_exercises_UserId_SourceExerciseId_WorkoutCompletedA~",
            schema: "training",
            table: "workout_exercises",
            columns: new[] { "UserId", "SourceExerciseId", "WorkoutCompletedAtUtc" },
            descending: new[] { false, false, true });

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
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "workout_sets",
            schema: "training");

        migrationBuilder.DropTable(
            name: "workout_exercises",
            schema: "training");

        migrationBuilder.DropTable(
            name: "workouts",
            schema: "training");
    }
}
