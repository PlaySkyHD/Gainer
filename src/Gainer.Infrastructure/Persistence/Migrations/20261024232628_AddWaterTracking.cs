using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddWaterTracking : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "water_intake_days",
            schema: "tracking",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                LocalDate = table.Column<DateOnly>(type: "date", nullable: false),
                AmountMl = table.Column<int>(type: "integer", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_water_intake_days", x => x.Id);
                table.CheckConstraint("CK_water_intake_days_amount", "\"AmountMl\" >= 0 AND \"AmountMl\" <= 10000");
                table.ForeignKey(
                    name: "FK_water_intake_days_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_water_intake_days_UserId_LocalDate",
            schema: "tracking",
            table: "water_intake_days",
            columns: new[] { "UserId", "LocalDate" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "water_intake_days",
            schema: "tracking");
    }
}
