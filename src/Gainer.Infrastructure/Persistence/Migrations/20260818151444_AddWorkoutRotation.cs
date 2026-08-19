using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddWorkoutRotation : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "workout_rotations",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                LastCompletedTemplateId = table.Column<Guid>(type: "uuid", nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_rotations", x => x.Id);
                table.ForeignKey(
                    name: "FK_workout_rotations_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_rotations_workout_templates_LastCompletedTemplateId",
                    column: x => x.LastCompletedTemplateId,
                    principalSchema: "training",
                    principalTable: "workout_templates",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.SetNull);
            });

        migrationBuilder.CreateTable(
            name: "workout_rotation_items",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                RotationId = table.Column<Guid>(type: "uuid", nullable: false),
                TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_rotation_items", x => x.Id);
                table.CheckConstraint("CK_workout_rotation_items_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_workout_rotation_items_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_rotation_items_workout_rotations_RotationId",
                    column: x => x.RotationId,
                    principalSchema: "training",
                    principalTable: "workout_rotations",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_workout_rotation_items_workout_templates_TemplateId",
                    column: x => x.TemplateId,
                    principalSchema: "training",
                    principalTable: "workout_templates",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_Position",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_TemplateId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "TemplateId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_TemplateId",
            schema: "training",
            table: "workout_rotation_items",
            column: "TemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_UserId_RotationId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "UserId", "RotationId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotations_LastCompletedTemplateId",
            schema: "training",
            table: "workout_rotations",
            column: "LastCompletedTemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotations_UserId",
            schema: "training",
            table: "workout_rotations",
            column: "UserId",
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "workout_rotation_items",
            schema: "training");

        migrationBuilder.DropTable(
            name: "workout_rotations",
            schema: "training");
    }
}
