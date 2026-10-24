using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddCoachMemory : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(
            name: "ai");

        migrationBuilder.CreateTable(
            name: "coach_memories",
            schema: "ai",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Category = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                Text = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_coach_memories", x => x.Id);
                table.CheckConstraint("CK_coach_memories_category", "\"Category\" IN ('Goal', 'Preference', 'Intolerance', 'Injury', 'Other')");
                table.CheckConstraint("CK_coach_memories_text", "length(trim(\"Text\")) > 0 AND length(\"Text\") <= 200");
                table.ForeignKey(
                    name: "FK_coach_memories_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_coach_memories_UserId_CreatedAtUtc",
            schema: "ai",
            table: "coach_memories",
            columns: new[] { "UserId", "CreatedAtUtc" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "coach_memories",
            schema: "ai");
    }
}
