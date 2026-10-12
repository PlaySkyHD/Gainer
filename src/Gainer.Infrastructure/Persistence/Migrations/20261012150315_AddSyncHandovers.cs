using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSyncHandovers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "HandoverRequired",
                schema: "sync",
                table: "user_state",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "handovers",
                schema: "sync",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    SourceClientId = table.Column<Guid>(type: "uuid", nullable: false),
                    TargetClientId = table.Column<Guid>(type: "uuid", nullable: true),
                    FrozenRevision = table.Column<long>(type: "bigint", nullable: false),
                    CodeHash = table.Column<byte[]>(type: "bytea", nullable: false),
                    ProtectedCode = table.Column<string>(type: "character varying(4096)", maxLength: 4096, nullable: true),
                    ExpiresAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CompletedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_handovers", x => new { x.UserId, x.Id });
                    table.CheckConstraint("CK_sync_handovers_code_hash", "octet_length(\"CodeHash\") = 32");
                    table.CheckConstraint("CK_sync_handovers_revision", "\"FrozenRevision\" >= 0");
                    table.CheckConstraint("CK_sync_handovers_status", "\"Status\" IN ('Pending', 'Completed', 'Cancelled', 'Expired')");
                    table.ForeignKey(
                        name: "FK_handovers_clients_UserId_SourceClientId",
                        columns: x => new { x.UserId, x.SourceClientId },
                        principalSchema: "sync",
                        principalTable: "clients",
                        principalColumns: new[] { "UserId", "Id" },
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_handovers_clients_UserId_TargetClientId",
                        columns: x => new { x.UserId, x.TargetClientId },
                        principalSchema: "sync",
                        principalTable: "clients",
                        principalColumns: new[] { "UserId", "Id" },
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_handovers_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "identity",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_handovers_UserId",
                schema: "sync",
                table: "handovers",
                column: "UserId",
                unique: true,
                filter: "\"Status\" = 'Pending'");

            migrationBuilder.CreateIndex(
                name: "IX_handovers_UserId_RequestId",
                schema: "sync",
                table: "handovers",
                columns: new[] { "UserId", "RequestId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_handovers_UserId_SourceClientId",
                schema: "sync",
                table: "handovers",
                columns: new[] { "UserId", "SourceClientId" });

            migrationBuilder.CreateIndex(
                name: "IX_handovers_UserId_TargetClientId",
                schema: "sync",
                table: "handovers",
                columns: new[] { "UserId", "TargetClientId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "handovers",
                schema: "sync");

            migrationBuilder.DropColumn(
                name: "HandoverRequired",
                schema: "sync",
                table: "user_state");
        }
    }
}
