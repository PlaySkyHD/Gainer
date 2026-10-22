using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddSaltTracking : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "SaltGrams",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "SaltGramsPer100Grams",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "SaltGrams",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "SaltGrams",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "SaltGramsPerBasis",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddCheckConstraint(
            name: "CK_reusable_meal_components_salt",
            schema: "tracking",
            table: "reusable_meal_components",
            sql: "(\"SaltGrams\" IS NULL OR \"SaltGrams\" >= 0) AND (\"SaltGramsPer100Grams\" IS NULL OR (\"SaltGramsPer100Grams\" >= 0 AND \"SaltGramsPer100Grams\" <= 100))");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_salt",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "\"SaltGrams\" IS NULL OR (\"SaltGrams\" > 0 AND \"SaltGrams\" <= 100)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_entries_salt",
            schema: "tracking",
            table: "nutrition_entries",
            sql: "(\"SaltGrams\" IS NULL OR \"SaltGrams\" >= 0) AND (\"SaltGramsPerBasis\" IS NULL OR \"SaltGramsPerBasis\" >= 0)");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropCheckConstraint(
            name: "CK_reusable_meal_components_salt",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_salt",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_entries_salt",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "SaltGrams",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "SaltGramsPer100Grams",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "SaltGrams",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "SaltGrams",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "SaltGramsPerBasis",
            schema: "tracking",
            table: "nutrition_entries");
    }
}
