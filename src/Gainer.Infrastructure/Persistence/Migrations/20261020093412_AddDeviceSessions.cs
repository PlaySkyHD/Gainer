using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddDeviceSessions : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "device_sessions",
            schema: "identity",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                DeviceName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                RefreshTokenHash = table.Column<byte[]>(type: "bytea", nullable: false),
                PreviousRefreshTokenHash = table.Column<byte[]>(type: "bytea", nullable: true),
                RotatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                LastUsedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                RevokedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                Version = table.Column<long>(type: "bigint", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_device_sessions", x => x.Id);
                table.CheckConstraint("CK_identity_device_sessions_name", "length(trim(\"DeviceName\")) > 0");
                table.CheckConstraint("CK_identity_device_sessions_token_hash", "octet_length(\"RefreshTokenHash\") = 32");
                table.ForeignKey(
                    name: "FK_device_sessions_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_device_sessions_PreviousRefreshTokenHash",
            schema: "identity",
            table: "device_sessions",
            column: "PreviousRefreshTokenHash",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_device_sessions_RefreshTokenHash",
            schema: "identity",
            table: "device_sessions",
            column: "RefreshTokenHash",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_device_sessions_UserId",
            schema: "identity",
            table: "device_sessions",
            column: "UserId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "device_sessions",
            schema: "identity");
    }
}
