using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddFiberTracking : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "FiberGrams",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGramsPer100Grams",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGramsPerBasis",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_day_template_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "FiberGramsPerBasis",
            schema: "tracking",
            table: "nutrition_day_template_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddCheckConstraint(
            name: "CK_reusable_meal_components_fiber",
            schema: "tracking",
            table: "reusable_meal_components",
            sql: "(\"FiberGrams\" IS NULL OR \"FiberGrams\" >= 0) AND (\"FiberGramsPer100Grams\" IS NULL OR (\"FiberGramsPer100Grams\" >= 0 AND \"FiberGramsPer100Grams\" <= 100))");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_fiber",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "\"FiberGrams\" IS NULL OR (\"FiberGrams\" > 0 AND \"FiberGrams\" <= 100)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_entries_fiber",
            schema: "tracking",
            table: "nutrition_entries",
            sql: "(\"FiberGrams\" IS NULL OR \"FiberGrams\" >= 0) AND (\"FiberGramsPerBasis\" IS NULL OR \"FiberGramsPerBasis\" >= 0)");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropCheckConstraint(
            name: "CK_reusable_meal_components_fiber",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_fiber",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_entries_fiber",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "FiberGrams",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "FiberGramsPer100Grams",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "FiberGramsPerBasis",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "FiberGrams",
            schema: "tracking",
            table: "nutrition_day_template_entries");

        migrationBuilder.DropColumn(
            name: "FiberGramsPerBasis",
            schema: "tracking",
            table: "nutrition_day_template_entries");
    }
}
