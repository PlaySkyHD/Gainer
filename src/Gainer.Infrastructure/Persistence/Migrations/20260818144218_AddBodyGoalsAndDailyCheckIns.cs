using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddBodyGoalsAndDailyCheckIns : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(
            name: "tracking");

        migrationBuilder.CreateTable(
            name: "body_goals",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                StartWeightKg = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: false),
                TargetWeightKg = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: false),
                StartDate = table.Column<DateOnly>(type: "date", nullable: false),
                TargetDate = table.Column<DateOnly>(type: "date", nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                EndedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_body_goals", x => x.Id);
                table.CheckConstraint("CK_body_goals_kind", "\"Kind\" IN ('Bulk', 'Maintain', 'Cut')");
                table.CheckConstraint("CK_body_goals_start_weight", "\"StartWeightKg\" > 0");
                table.CheckConstraint("CK_body_goals_target_date", "\"TargetDate\" IS NULL OR \"TargetDate\" >= \"StartDate\"");
                table.CheckConstraint("CK_body_goals_target_weight", "\"TargetWeightKg\" > 0");
                table.ForeignKey(
                    name: "FK_body_goals_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "daily_check_ins",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                LocalDate = table.Column<DateOnly>(type: "date", nullable: false),
                WeightKg = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: false),
                CaloriesKcal = table.Column<decimal>(type: "numeric(8,2)", precision: 8, scale: 2, nullable: true),
                ProteinGrams = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                CarbohydrateGrams = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                FatGrams = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                Steps = table.Column<int>(type: "integer", nullable: true),
                SleepMinutes = table.Column<int>(type: "integer", nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_daily_check_ins", x => x.Id);
                table.CheckConstraint("CK_daily_check_ins_calories", "\"CaloriesKcal\" IS NULL OR \"CaloriesKcal\" >= 0");
                table.CheckConstraint("CK_daily_check_ins_carbohydrate", "\"CarbohydrateGrams\" IS NULL OR \"CarbohydrateGrams\" >= 0");
                table.CheckConstraint("CK_daily_check_ins_fat", "\"FatGrams\" IS NULL OR \"FatGrams\" >= 0");
                table.CheckConstraint("CK_daily_check_ins_protein", "\"ProteinGrams\" IS NULL OR \"ProteinGrams\" >= 0");
                table.CheckConstraint("CK_daily_check_ins_sleep", "\"SleepMinutes\" IS NULL OR (\"SleepMinutes\" >= 0 AND \"SleepMinutes\" <= 1440)");
                table.CheckConstraint("CK_daily_check_ins_steps", "\"Steps\" IS NULL OR \"Steps\" >= 0");
                table.CheckConstraint("CK_daily_check_ins_weight", "\"WeightKg\" > 0");
                table.ForeignKey(
                    name: "FK_daily_check_ins_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_body_goals_UserId",
            schema: "tracking",
            table: "body_goals",
            column: "UserId",
            unique: true,
            filter: "\"EndedAtUtc\" IS NULL");

        migrationBuilder.CreateIndex(
            name: "IX_body_goals_UserId_StartDate",
            schema: "tracking",
            table: "body_goals",
            columns: new[] { "UserId", "StartDate" });

        migrationBuilder.CreateIndex(
            name: "IX_daily_check_ins_UserId_LocalDate",
            schema: "tracking",
            table: "daily_check_ins",
            columns: new[] { "UserId", "LocalDate" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "body_goals",
            schema: "tracking");

        migrationBuilder.DropTable(
            name: "daily_check_ins",
            schema: "tracking");
    }
}
