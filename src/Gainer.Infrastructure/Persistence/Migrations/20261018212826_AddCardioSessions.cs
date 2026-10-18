using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCardioSessions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "cardio_sessions",
                schema: "training",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ActivityType = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    StartedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    EndedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    TargetZoneLowBpm = table.Column<int>(type: "integer", nullable: true),
                    TargetZoneHighBpm = table.Column<int>(type: "integer", nullable: true),
                    SampleIntervalSeconds = table.Column<int>(type: "integer", nullable: false),
                    HeartRateBpm = table.Column<int[]>(type: "integer[]", nullable: false),
                    RrIntervalsMs = table.Column<int[]>(type: "integer[]", nullable: false),
                    SensorName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    DistanceKm = table.Column<decimal>(type: "numeric(8,3)", precision: 8, scale: 3, nullable: true),
                    AveragePowerWatts = table.Column<decimal>(type: "numeric(7,2)", precision: 7, scale: 2, nullable: true),
                    EnergyKcal = table.Column<decimal>(type: "numeric(8,2)", precision: 8, scale: 2, nullable: true),
                    Notes = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cardio_sessions", x => x.Id);
                    table.UniqueConstraint("AK_cardio_sessions_UserId_Id", x => new { x.UserId, x.Id });
                    table.CheckConstraint("CK_cardio_sessions_activity_type", "\"ActivityType\" IN ('IndoorCycling')");
                    table.CheckConstraint("CK_cardio_sessions_end_after_start", "\"EndedAtUtc\" > \"StartedAtUtc\"");
                    table.CheckConstraint("CK_cardio_sessions_sample_interval", "\"SampleIntervalSeconds\" BETWEEN 1 AND 60");
                    table.CheckConstraint("CK_cardio_sessions_target_zone", "(\"TargetZoneLowBpm\" IS NULL AND \"TargetZoneHighBpm\" IS NULL) OR (\"TargetZoneLowBpm\" >= 40 AND \"TargetZoneHighBpm\" <= 230 AND \"TargetZoneLowBpm\" < \"TargetZoneHighBpm\")");
                    table.ForeignKey(
                        name: "FK_cardio_sessions_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "identity",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_cardio_sessions_UserId_StartedAtUtc",
                schema: "training",
                table: "cardio_sessions",
                columns: new[] { "UserId", "StartedAtUtc" },
                descending: new[] { false, true });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "cardio_sessions",
                schema: "training");
        }
    }
}
