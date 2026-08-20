using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddNutritionGoalPhases : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "CarbohydratePercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "Category",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "character varying(24)",
            maxLength: 24,
            nullable: false,
            defaultValue: "Custom");

        migrationBuilder.AddColumn<DateOnly>(
            name: "EffectiveUntil",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "date",
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FatPercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "InputMode",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "character varying(16)",
            maxLength: 16,
            nullable: false,
            defaultValue: "Grams");

        migrationBuilder.AddColumn<string>(
            name: "Name",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "character varying(80)",
            maxLength: 80,
            nullable: false,
            defaultValue: "Ziel");

        migrationBuilder.AddColumn<decimal>(
            name: "ProteinPercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.Sql(
            """
            WITH ordered_versions AS (
                SELECT
                    "Id",
                    lead("EffectiveFrom") OVER (
                        PARTITION BY "UserId", "NutritionTargetScheduleId"
                        ORDER BY "EffectiveFrom", "Id") AS "NextEffectiveFrom"
                FROM tracking.nutrition_target_versions
            )
            UPDATE tracking.nutrition_target_versions AS target
            SET "EffectiveUntil" = ordered_versions."NextEffectiveFrom" - 1
            FROM ordered_versions
            WHERE target."Id" = ordered_versions."Id"
              AND ordered_versions."NextEffectiveFrom" IS NOT NULL;
            """);

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_category",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "\"Category\" IN ('Custom', 'Cut', 'Maintenance', 'Bulk')");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_dates",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "\"EffectiveUntil\" IS NULL OR \"EffectiveUntil\" >= \"EffectiveFrom\"");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_input",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "(\"InputMode\" = 'Grams' AND \"ProteinPercent\" IS NULL AND \"CarbohydratePercent\" IS NULL AND \"FatPercent\" IS NULL) OR (\"InputMode\" = 'Percent' AND \"ProteinPercent\" > 0 AND \"CarbohydratePercent\" > 0 AND \"FatPercent\" > 0 AND \"ProteinPercent\" + \"CarbohydratePercent\" + \"FatPercent\" = 100)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_name",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "length(trim(\"Name\")) > 0");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_category",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_dates",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_input",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_name",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "CarbohydratePercent",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "Category",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "EffectiveUntil",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "FatPercent",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "InputMode",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "Name",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "ProteinPercent",
            schema: "tracking",
            table: "nutrition_target_versions");
    }
}
