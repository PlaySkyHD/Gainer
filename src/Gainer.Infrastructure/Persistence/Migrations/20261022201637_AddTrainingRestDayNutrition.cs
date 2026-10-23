using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddTrainingRestDayNutrition : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "RestCarbohydrateGrams",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestCarbohydratePercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestFatGrams",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestFatPercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "RestInputMode",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "character varying(16)",
            maxLength: 16,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestKilocalories",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestProteinGrams",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(10,2)",
            precision: 10,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "RestProteinPercent",
            schema: "tracking",
            table: "nutrition_target_versions",
            type: "numeric(5,2)",
            precision: 5,
            scale: 2,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "DayKind",
            schema: "tracking",
            table: "nutrition_days",
            type: "character varying(16)",
            maxLength: 16,
            nullable: true);

        migrationBuilder.CreateTable(
            name: "nutrition_day_templates",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                DayKind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_nutrition_day_templates", x => x.Id);
                table.UniqueConstraint("AK_nutrition_day_templates_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_nutrition_day_templates_day_kind", "\"DayKind\" IS NULL OR \"DayKind\" IN ('Training', 'Rest')");
                table.CheckConstraint("CK_nutrition_day_templates_name", "length(trim(\"Name\")) > 0");
                table.ForeignKey(
                    name: "FK_nutrition_day_templates_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "nutrition_day_template_entries",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                NutritionDayTemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                Meal = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                ProductName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                Brand = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                AmountGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                PieceGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                PieceCount = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                Kilocalories = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                ProteinGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                CarbohydrateGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                FatGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                SaltGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                Provider = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                Barcode = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                RetrievedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                BasisGrams = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                KilocaloriesPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: false),
                ProteinGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                CarbohydrateGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                FatGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                SaltGramsPerBasis = table.Column<decimal>(type: "numeric(9,2)", precision: 9, scale: 2, nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_nutrition_day_template_entries", x => x.Id);
                table.CheckConstraint("CK_nutrition_day_template_entries_amount", "\"AmountGrams\" > 0");
                table.CheckConstraint("CK_nutrition_day_template_entries_basis", "\"BasisGrams\" > 0 AND \"KilocaloriesPerBasis\" >= 0");
                table.CheckConstraint("CK_nutrition_day_template_entries_meal", "\"Meal\" IN ('Breakfast', 'Lunch', 'Dinner', 'Snacks')");
                table.CheckConstraint("CK_nutrition_day_template_entries_name", "length(trim(\"ProductName\")) > 0");
                table.CheckConstraint("CK_nutrition_day_template_entries_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_nutrition_day_template_entries_nutrition_day_templates_User~",
                    columns: x => new { x.UserId, x.NutritionDayTemplateId },
                    principalSchema: "tracking",
                    principalTable: "nutrition_day_templates",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_nutrition_day_template_entries_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_target_versions_rest",
            schema: "tracking",
            table: "nutrition_target_versions",
            sql: "(\"RestKilocalories\" IS NULL AND \"RestInputMode\" IS NULL AND \"RestProteinGrams\" IS NULL AND \"RestCarbohydrateGrams\" IS NULL AND \"RestFatGrams\" IS NULL AND \"RestProteinPercent\" IS NULL AND \"RestCarbohydratePercent\" IS NULL AND \"RestFatPercent\" IS NULL) OR (\"RestKilocalories\" > 0 AND \"RestKilocalories\" <= 20000 AND \"RestProteinGrams\" > 0 AND \"RestProteinGrams\" <= 2000 AND \"RestCarbohydrateGrams\" > 0 AND \"RestCarbohydrateGrams\" <= 2000 AND \"RestFatGrams\" > 0 AND \"RestFatGrams\" <= 2000 AND ((\"RestInputMode\" = 'Grams' AND \"RestProteinPercent\" IS NULL AND \"RestCarbohydratePercent\" IS NULL AND \"RestFatPercent\" IS NULL) OR (\"RestInputMode\" = 'Percent' AND \"RestProteinPercent\" > 0 AND \"RestCarbohydratePercent\" > 0 AND \"RestFatPercent\" > 0 AND \"RestProteinPercent\" + \"RestCarbohydratePercent\" + \"RestFatPercent\" = 100)))");

        migrationBuilder.AddCheckConstraint(
            name: "CK_nutrition_days_day_kind",
            schema: "tracking",
            table: "nutrition_days",
            sql: "\"DayKind\" IS NULL OR \"DayKind\" IN ('Training', 'Rest')");

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_day_template_entries_UserId_NutritionDayTemplateI~",
            schema: "tracking",
            table: "nutrition_day_template_entries",
            columns: new[] { "UserId", "NutritionDayTemplateId", "Meal", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_nutrition_day_templates_UserId_UpdatedAtUtc",
            schema: "tracking",
            table: "nutrition_day_templates",
            columns: new[] { "UserId", "UpdatedAtUtc" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "nutrition_day_template_entries",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "nutrition_day_templates",
            schema: "tracking");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_target_versions_rest",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropCheckConstraint(
            name: "CK_nutrition_days_day_kind",
            schema: "tracking",
            table: "nutrition_days");

        migrationBuilder.DropColumn(
            name: "RestCarbohydrateGrams",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestCarbohydratePercent",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestFatGrams",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestFatPercent",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestInputMode",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestKilocalories",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestProteinGrams",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "RestProteinPercent",
            schema: "tracking",
            table: "nutrition_target_versions");

        migrationBuilder.DropColumn(
            name: "DayKind",
            schema: "tracking",
            table: "nutrition_days");
    }
}
