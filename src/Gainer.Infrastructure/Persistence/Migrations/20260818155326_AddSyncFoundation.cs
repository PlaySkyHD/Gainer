using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddSyncFoundation : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(
            name: "sync");

        migrationBuilder.CreateTable(
            name: "clients",
            schema: "sync",
            columns: table => new
            {
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                DisplayName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                ProtocolVersion = table.Column<int>(type: "integer", nullable: false),
                RegisteredAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                LastSeenAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_clients", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_sync_clients_name", "length(trim(\"DisplayName\")) > 0");
                table.CheckConstraint("CK_sync_clients_protocol", "\"ProtocolVersion\" > 0");
                table.ForeignKey(
                    name: "FK_clients_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "processed_mutations",
            schema: "sync",
            columns: table => new
            {
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                MutationId = table.Column<Guid>(type: "uuid", nullable: false),
                ClientId = table.Column<Guid>(type: "uuid", nullable: false),
                ClientSequence = table.Column<long>(type: "bigint", nullable: false),
                ContentHash = table.Column<byte[]>(type: "bytea", nullable: false),
                ResultJson = table.Column<string>(type: "jsonb", nullable: false),
                Revision = table.Column<long>(type: "bigint", nullable: false),
                AppliedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_processed_mutations", x => new { x.UserId, x.MutationId });
                table.CheckConstraint("CK_processed_mutations_hash", "octet_length(\"ContentHash\") = 32");
                table.CheckConstraint("CK_processed_mutations_revision", "\"Revision\" > 0");
                table.CheckConstraint("CK_processed_mutations_sequence", "\"ClientSequence\" > 0");
                table.ForeignKey(
                    name: "FK_processed_mutations_clients_UserId_ClientId",
                    columns: x => new { x.UserId, x.ClientId },
                    principalSchema: "sync",
                    principalTable: "clients",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_processed_mutations_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "user_state",
            schema: "sync",
            columns: table => new
            {
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                CurrentRevision = table.Column<long>(type: "bigint", nullable: false),
                ActiveClientId = table.Column<Guid>(type: "uuid", nullable: true),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_user_state", x => x.UserId);
                table.CheckConstraint("CK_sync_user_state_revision", "\"CurrentRevision\" >= 0");
                table.ForeignKey(
                    name: "FK_user_state_clients_UserId_ActiveClientId",
                    columns: x => new { x.UserId, x.ActiveClientId },
                    principalSchema: "sync",
                    principalTable: "clients",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_user_state_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "change_batches",
            schema: "sync",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Revision = table.Column<long>(type: "bigint", nullable: false),
                MutationId = table.Column<Guid>(type: "uuid", nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_change_batches", x => x.Id);
                table.UniqueConstraint("AK_change_batches_UserId_Id", x => new { x.UserId, x.Id });
                table.CheckConstraint("CK_change_batches_revision", "\"Revision\" > 0");
                table.ForeignKey(
                    name: "FK_change_batches_processed_mutations_UserId_MutationId",
                    columns: x => new { x.UserId, x.MutationId },
                    principalSchema: "sync",
                    principalTable: "processed_mutations",
                    principalColumns: new[] { "UserId", "MutationId" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_change_batches_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "change_items",
            schema: "sync",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                BatchId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                ResourceType = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                ResourceId = table.Column<Guid>(type: "uuid", nullable: false),
                ResourceVersion = table.Column<long>(type: "bigint", nullable: false),
                IsTombstone = table.Column<bool>(type: "boolean", nullable: false),
                SnapshotJson = table.Column<string>(type: "jsonb", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_change_items", x => x.Id);
                table.CheckConstraint("CK_change_items_payload", "(\"IsTombstone\" = TRUE AND \"SnapshotJson\" IS NULL) OR (\"IsTombstone\" = FALSE AND \"SnapshotJson\" IS NOT NULL)");
                table.CheckConstraint("CK_change_items_position", "\"Position\" >= 0");
                table.CheckConstraint("CK_change_items_resource_type", "length(trim(\"ResourceType\")) > 0");
                table.CheckConstraint("CK_change_items_resource_version", "\"ResourceVersion\" > 0");
                table.ForeignKey(
                    name: "FK_change_items_change_batches_UserId_BatchId",
                    columns: x => new { x.UserId, x.BatchId },
                    principalSchema: "sync",
                    principalTable: "change_batches",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_change_items_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_change_batches_UserId_MutationId",
            schema: "sync",
            table: "change_batches",
            columns: new[] { "UserId", "MutationId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_change_batches_UserId_Revision",
            schema: "sync",
            table: "change_batches",
            columns: new[] { "UserId", "Revision" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_change_items_BatchId_Position",
            schema: "sync",
            table: "change_items",
            columns: new[] { "BatchId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_change_items_UserId_BatchId",
            schema: "sync",
            table: "change_items",
            columns: new[] { "UserId", "BatchId" });

        migrationBuilder.CreateIndex(
            name: "IX_change_items_UserId_ResourceType_ResourceId",
            schema: "sync",
            table: "change_items",
            columns: new[] { "UserId", "ResourceType", "ResourceId" });

        migrationBuilder.CreateIndex(
            name: "IX_clients_Id",
            schema: "sync",
            table: "clients",
            column: "Id");

        migrationBuilder.CreateIndex(
            name: "IX_processed_mutations_UserId_ClientId_ClientSequence",
            schema: "sync",
            table: "processed_mutations",
            columns: new[] { "UserId", "ClientId", "ClientSequence" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_user_state_UserId_ActiveClientId",
            schema: "sync",
            table: "user_state",
            columns: new[] { "UserId", "ActiveClientId" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "change_items",
            schema: "sync");

        migrationBuilder.DropTable(
            name: "user_state",
            schema: "sync");

        migrationBuilder.DropTable(
            name: "change_batches",
            schema: "sync");

        migrationBuilder.DropTable(
            name: "processed_mutations",
            schema: "sync");

        migrationBuilder.DropTable(
            name: "clients",
            schema: "sync");
    }
}
