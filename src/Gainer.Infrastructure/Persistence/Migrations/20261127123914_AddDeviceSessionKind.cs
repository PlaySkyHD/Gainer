using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddDeviceSessionKind : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<byte[]>(
            name: "ConnectorClientHash",
            schema: "identity",
            table: "device_sessions",
            type: "bytea",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "Kind",
            schema: "identity",
            table: "device_sessions",
            type: "integer",
            nullable: false,
            defaultValue: 0);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "ConnectorClientHash",
            schema: "identity",
            table: "device_sessions");

        migrationBuilder.DropColumn(
            name: "Kind",
            schema: "identity",
            table: "device_sessions");
    }
}
