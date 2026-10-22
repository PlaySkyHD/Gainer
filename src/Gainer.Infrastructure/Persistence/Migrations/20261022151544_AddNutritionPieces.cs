using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddNutritionPieces : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "PieceCount",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(7,2)",
            precision: 7,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "PieceGrams",
            schema: "tracking",
            table: "reusable_meal_components",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "PieceCount",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(7,2)",
            precision: 7,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "PieceGrams",
            schema: "tracking",
            table: "nutrition_entries",
            type: "numeric(9,2)",
            precision: 9,
            scale: 2,
            nullable: true);

        migrationBuilder.AddCheckConstraint(
            name: "CK_reusable_meal_components_pieces",
            schema: "tracking",
            table: "reusable_meal_components",
            sql: "(\"PieceGrams\" IS NULL OR \"PieceGrams\" > 0) AND (\"PieceCount\" IS NULL OR (\"PieceCount\" > 0 AND \"PieceGrams\" IS NOT NULL))");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_entries_pieces",
            schema: "tracking",
            table: "nutrition_entries",
            sql: "(\"PieceGrams\" IS NULL OR \"PieceGrams\" > 0) AND (\"PieceCount\" IS NULL OR (\"PieceCount\" > 0 AND \"PieceGrams\" IS NOT NULL))");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropCheckConstraint(
            name: "CK_reusable_meal_components_pieces",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_entries_pieces",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "PieceCount",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "PieceGrams",
            schema: "tracking",
            table: "reusable_meal_components");

        migrationBuilder.DropColumn(
            name: "PieceCount",
            schema: "tracking",
            table: "nutrition_entries");

        migrationBuilder.DropColumn(
            name: "PieceGrams",
            schema: "tracking",
            table: "nutrition_entries");
    }
}
