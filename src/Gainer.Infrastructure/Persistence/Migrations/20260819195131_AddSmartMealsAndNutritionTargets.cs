using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddSmartMealsAndNutritionTargets : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "nutrition_target_schedules",
            schema: "tracking",
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
                table.PrimaryKey("PK_nutrition_target_schedules", x => x.Id);
                table.UniqueConstraint("AK_nutrition_target_schedules_UserId_Id", x => new { x.UserId, x.Id });
                table.ForeignKey(
                    name: "FK_nutrition_target_schedules_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "reusable_meals",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                StandardPortion = table.Column<decimal>(type: "numeric(8,2)", precision: 8, scale: 2, nullable: false),
                Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_reusable_meals", x => x.Id);
                table.UniqueConstraint("AK_reusable_meals_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_reusable_meals_name", "length(trim(\"Name\")) > 0");
                table.CheckConstraint("CK_reusable_meals_portion", "\"StandardPortion\" >= 0.01 AND \"StandardPortion\" <= 100");
                table.CheckConstraint("CK_reusable_meals_status", "\"Status\" IN ('Active', 'Archived')");
                table.ForeignKey(
                    name: "FK_reusable_meals_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "nutrition_target_versions",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                NutritionTargetScheduleId = table.Column<Guid>(type: "uuid", nullable: false),
                EffectiveFrom = table.Column<DateOnly>(type: "date", nullable: false),
                Kilocalories = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                ProteinGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                CarbohydrateGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                FatGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                Origin = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                AlgorithmVersion = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                Reason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_nutrition_target_versions", x => x.Id);
                table.CheckConstraint("CK_nutrition_target_versions_kcal", "\"Kilocalories\" > 0 AND \"Kilocalories\" <= 20000");
                table.CheckConstraint("CK_nutrition_target_versions_macros", "\"ProteinGrams\" > 0 AND \"ProteinGrams\" <= 2000 AND \"CarbohydrateGrams\" > 0 AND \"CarbohydrateGrams\" <= 2000 AND \"FatGrams\" > 0 AND \"FatGrams\" <= 2000");
                table.CheckConstraint("CK_nutrition_target_versions_origin", "\"Origin\" = 'Manual'");
                table.ForeignKey(
                    name: "FK_nutrition_target_versions_nutrition_target_schedules_UserId~",
                    columns: x => new { x.UserId, x.NutritionTargetScheduleId },
                    principalSchema: "tracking",
                    principalTable: "nutrition_target_schedules",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_nutrition_target_versions_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "reusable_meal_components",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ReusableMealId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                Brand = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                AmountGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                Kilocalories = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                ProteinGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                CarbohydrateGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                FatGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                KilocaloriesPer100Grams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                ProteinGramsPer100Grams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                CarbohydrateGramsPer100Grams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                FatGramsPer100Grams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: true),
                BasisGrams = table.Column<decimal>(type: "numeric(10,2)", precision: 10, scale: 2, nullable: false),
                Provider = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                Barcode = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                RetrievedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_reusable_meal_components", x => x.Id);
                table.CheckConstraint("CK_reusable_meal_components_amount", "\"AmountGrams\" >= 0.01 AND \"AmountGrams\" <= 100000");
                table.CheckConstraint("CK_reusable_meal_components_basis", "\"BasisGrams\" > 0");
                table.CheckConstraint("CK_reusable_meal_components_kcal", "\"Kilocalories\" > 0 AND \"KilocaloriesPer100Grams\" > 0");
                table.CheckConstraint("CK_reusable_meal_components_macros", "(\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0) AND (\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0) AND (\"FatGrams\" IS NULL OR \"FatGrams\" >= 0)");
                table.CheckConstraint("CK_reusable_meal_components_name", "length(trim(\"Name\")) > 0");
                table.CheckConstraint("CK_reusable_meal_components_per100_macros", "(\"ProteinGramsPer100Grams\" IS NULL OR \"ProteinGramsPer100Grams\" >= 0) AND (\"CarbohydrateGramsPer100Grams\" IS NULL OR \"CarbohydrateGramsPer100Grams\" >= 0) AND (\"FatGramsPer100Grams\" IS NULL OR \"FatGramsPer100Grams\" >= 0)");
                table.CheckConstraint("CK_reusable_meal_components_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_reusable_meal_components_reusable_meals_UserId_ReusableMeal~",
                    columns: x => new { x.UserId, x.ReusableMealId },
                    principalSchema: "tracking",
                    principalTable: "reusable_meals",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_reusable_meal_components_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_target_schedules_UserId",
            schema: "tracking",
            table: "nutrition_target_schedules",
            column: "UserId",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_target_versions_UserId_NutritionTargetScheduleId_~",
            schema: "tracking",
            table: "nutrition_target_versions",
            columns: new[] { "UserId", "NutritionTargetScheduleId", "EffectiveFrom" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_reusable_meal_components_UserId_ReusableMealId_Position",
            schema: "tracking",
            table: "reusable_meal_components",
            columns: new[] { "UserId", "ReusableMealId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_reusable_meals_UserId_Status_Name",
            schema: "tracking",
            table: "reusable_meals",
            columns: new[] { "UserId", "Status", "Name" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "nutrition_target_versions",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "reusable_meal_components",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "nutrition_target_schedules",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "reusable_meals",
            schema: "tracking");
    }
}
