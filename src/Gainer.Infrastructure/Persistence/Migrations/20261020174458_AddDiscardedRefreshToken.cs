using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddDiscardedRefreshToken : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
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
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
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
}
