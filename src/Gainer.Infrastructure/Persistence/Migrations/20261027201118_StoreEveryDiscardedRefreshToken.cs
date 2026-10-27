using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class StoreEveryDiscardedRefreshToken : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "device_session_discarded_tokens",
            schema: "identity",
            columns: table => new
            {
                SessionId = table.Column<Guid>(type: "uuid", nullable: false),
                TokenHash = table.Column<byte[]>(type: "bytea", nullable: false),
                DiscardedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_device_session_discarded_tokens", x => new { x.SessionId, x.TokenHash });
                table.CheckConstraint("CK_identity_device_session_discarded_tokens_hash", "octet_length(\"TokenHash\") = 32");
                table.ForeignKey(
                    name: "FK_device_session_discarded_tokens_device_sessions_SessionId",
                    column: x => x.SessionId,
                    principalSchema: "identity",
                    principalTable: "device_sessions",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_device_session_discarded_tokens_TokenHash",
            schema: "identity",
            table: "device_session_discarded_tokens",
            column: "TokenHash",
            unique: true);

        // Running sessions keep their discarded token as a revocation trigger. Without a retry since the
        // last rotation it counts as discarded in that rotation, so the next normal rotation keeps it once more.
        migrationBuilder.Sql(
            """
            INSERT INTO "identity".device_session_discarded_tokens ("SessionId", "TokenHash", "DiscardedAt")
            SELECT "Id", "DiscardedRefreshTokenHash", COALESCE("DiscardedAt", "RotatedAt", "CreatedAt")
            FROM "identity".device_sessions
            WHERE "DiscardedRefreshTokenHash" IS NOT NULL;
            """);

        migrationBuilder.DropIndex(
            name: "IX_device_sessions_DiscardedRefreshTokenHash",
            schema: "identity",
            table: "device_sessions");

        migrationBuilder.DropColumn(
            name: "DiscardedAt",
            schema: "identity",
            table: "device_sessions");

        migrationBuilder.DropColumn(
            name: "DiscardedRefreshTokenHash",
            schema: "identity",
            table: "device_sessions");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "DiscardedAt",
            schema: "identity",
            table: "device_sessions",
            type: "timestamp with time zone",
            nullable: true);

        migrationBuilder.AddColumn<byte[]>(
            name: "DiscardedRefreshTokenHash",
            schema: "identity",
            table: "device_sessions",
            type: "bytea",
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_device_sessions_DiscardedRefreshTokenHash",
            schema: "identity",
            table: "device_sessions",
            column: "DiscardedRefreshTokenHash",
            unique: true);

        // The single column can only hold one trigger; keep the earliest of each session.
        migrationBuilder.Sql(
            """
            UPDATE "identity".device_sessions AS session
            SET "DiscardedRefreshTokenHash" = earliest."TokenHash"
            FROM (
                SELECT DISTINCT ON ("SessionId") "SessionId", "TokenHash"
                FROM "identity".device_session_discarded_tokens
                ORDER BY "SessionId", "DiscardedAt"
            ) AS earliest
            WHERE session."Id" = earliest."SessionId";
            """);

        migrationBuilder.DropTable(
            name: "device_session_discarded_tokens",
            schema: "identity");
    }
}
