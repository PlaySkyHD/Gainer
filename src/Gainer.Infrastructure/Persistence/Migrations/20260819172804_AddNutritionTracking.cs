using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddNutritionTracking : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "nutrition_days",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                LocalDate = table.Column<DateOnly>(type: "date", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_nutrition_days", x => x.Id);
                table.UniqueConstraint("AK_nutrition_days_UserId_Id", x => new { x.UserId, x.Id });
                table.ForeignKey(
                    name: "FK_nutrition_days_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "nutrition_entries",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                NutritionDayId = table.Column<Guid>(type: "uuid", nullable: false),
                Meal = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                ProductName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                Brand = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                AmountGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                AmountUnit = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                Kilocalories = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                ProteinGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                CarbohydrateGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                FatGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                Provider = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                Barcode = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                RetrievedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                BasisGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                KilocaloriesPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                ProteinGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                CarbohydrateGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                FatGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_nutrition_entries", x => x.Id);
                table.CheckConstraint("CK_nutrition_entries_amount", "\"AmountGrams\" > 0");
                table.CheckConstraint("CK_nutrition_entries_basis", "\"BasisGrams\" > 0 AND \"KilocaloriesPerBasis\" > 0");
                table.CheckConstraint("CK_nutrition_entries_basis_macros", "(\"ProteinGramsPerBasis\" IS NULL OR \"ProteinGramsPerBasis\" >= 0) AND (\"CarbohydrateGramsPerBasis\" IS NULL OR \"CarbohydrateGramsPerBasis\" >= 0) AND (\"FatGramsPerBasis\" IS NULL OR \"FatGramsPerBasis\" >= 0)");
                table.CheckConstraint("CK_nutrition_entries_kcal", "\"Kilocalories\" > 0");
                table.CheckConstraint("CK_nutrition_entries_macros", "(\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0) AND (\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0) AND (\"FatGrams\" IS NULL OR \"FatGrams\" >= 0)");
                table.CheckConstraint("CK_nutrition_entries_meal", "\"Meal\" IN ('Breakfast', 'Lunch', 'Dinner', 'Snacks')");
                table.CheckConstraint("CK_nutrition_entries_name", "length(trim(\"ProductName\")) > 0");
                table.CheckConstraint("CK_nutrition_entries_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_nutrition_entries_nutrition_days_UserId_NutritionDayId",
                    columns: x => new { x.UserId, x.NutritionDayId },
                    principalSchema: "tracking",
                    principalTable: "nutrition_days",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_nutrition_entries_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_days_UserId_LocalDate",
            schema: "tracking",
            table: "nutrition_days",
            columns: new[] { "UserId", "LocalDate" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_entries_UserId_Barcode",
            schema: "tracking",
            table: "nutrition_entries",
            columns: new[] { "UserId", "Barcode" });

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_entries_UserId_NutritionDayId_Meal_Position",
            schema: "tracking",
            table: "nutrition_entries",
            columns: new[] { "UserId", "NutritionDayId", "Meal", "Position" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "nutrition_entries",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "nutrition_days",
            schema: "tracking");
    }
}
