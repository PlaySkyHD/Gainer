using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddStravaExport : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(
            name: "integrations");

        migrationBuilder.CreateTable(
            name: "strava_connections",
            schema: "integrations",
            columns: table => new
            {
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                AthleteId = table.Column<long>(type: "bigint", nullable: false),
                AthleteName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                Scope = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                ProtectedAccessToken = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                ProtectedRefreshToken = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                AccessTokenExpiresAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                CardioExportSinceUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                StrengthExportSinceUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                NeedsReconnect = table.Column<bool>(type: "boolean", nullable: false),
                PausedUntilUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                ConnectedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_strava_connections", x => x.UserId);
                table.CheckConstraint("CK_strava_connections_athlete", "\"AthleteId\" > 0");
                table.ForeignKey(
                    name: "FK_strava_connections_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "strava_exports",
            schema: "integrations",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                ResourceId = table.Column<Guid>(type: "uuid", nullable: false),
                AthleteId = table.Column<long>(type: "bigint", nullable: false),
                Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                UploadId = table.Column<long>(type: "bigint", nullable: true),
                ActivityId = table.Column<long>(type: "bigint", nullable: true),
                Attempts = table.Column<int>(type: "integer", nullable: false),
                NextAttemptAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                LastErrorCode = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_strava_exports", x => x.Id);
                table.CheckConstraint("CK_strava_exports_attempts", "\"Attempts\" >= 0");
                table.CheckConstraint("CK_strava_exports_kind", "\"Kind\" IN ('Cardio', 'Strength')");
                table.CheckConstraint("CK_strava_exports_status", "\"Status\" IN ('Pending', 'Processing', 'Completed', 'Failed')");
                table.ForeignKey(
                    name: "FK_strava_exports_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_strava_exports_UserId_Kind_ResourceId_AthleteId",
            schema: "integrations",
            table: "strava_exports",
            columns: new[] { "UserId", "Kind", "ResourceId", "AthleteId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_strava_exports_UserId_Status_NextAttemptAtUtc",
            schema: "integrations",
            table: "strava_exports",
            columns: new[] { "UserId", "Status", "NextAttemptAtUtc" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "strava_connections",
            schema: "integrations");

        migrationBuilder.DropTable(
            name: "strava_exports",
            schema: "integrations");
    }
}
