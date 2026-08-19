using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddWorkoutTemplates : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "workout_templates",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
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
                TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                ExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                PlannedSets = table.Column<int>(type: "integer", nullable: false),
                MinimumRepetitions = table.Column<int>(type: "integer", nullable: false),
                MaximumRepetitions = table.Column<int>(type: "integer", nullable: false),
                TargetRir = table.Column<decimal>(type: "numeric(4,2)", precision: 4, scale: 2, nullable: true),
                RestSeconds = table.Column<int>(type: "integer", nullable: true),
                Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
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
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "workout_template_items",
            schema: "training");

        migrationBuilder.DropTable(
            name: "workout_templates",
            schema: "training");
    }
}
