using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddTrainingSchedule : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "workout_rotation_items",
            schema: "training");

        migrationBuilder.DropTable(
            name: "workout_rotations",
            schema: "training");

        migrationBuilder.CreateTable(
            name: "training_schedules",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Mode = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                AnchorDate = table.Column<DateOnly>(type: "date", nullable: true),
                ValidFrom = table.Column<DateOnly>(type: "date", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_schedules", x => x.Id);
                table.CheckConstraint("CK_training_schedules_anchor", "(\"Mode\" = 'cycle') = (\"AnchorDate\" IS NOT NULL)");
                table.CheckConstraint("CK_training_schedules_mode", "\"Mode\" IN ('cycle', 'weekly')");
                table.ForeignKey(
                    name: "FK_training_schedules_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "training_schedule_exceptions",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ScheduleId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                Date = table.Column<DateOnly>(type: "date", nullable: false),
                PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                MovedToDate = table.Column<DateOnly>(type: "date", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_schedule_exceptions", x => x.Id);
                table.CheckConstraint("CK_training_schedule_exceptions_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_training_schedule_exceptions_training_plans_UserId_PlanId",
                    columns: x => new { x.UserId, x.PlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_training_schedule_exceptions_training_schedules_ScheduleId",
                    column: x => x.ScheduleId,
                    principalSchema: "training",
                    principalTable: "training_schedules",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_training_schedule_exceptions_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "training_schedule_shifts",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ScheduleId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                FromDate = table.Column<DateOnly>(type: "date", nullable: false),
                Days = table.Column<int>(type: "integer", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_schedule_shifts", x => x.Id);
                table.CheckConstraint("CK_training_schedule_shifts_days", "\"Days\" BETWEEN 1 AND 31");
                table.CheckConstraint("CK_training_schedule_shifts_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_training_schedule_shifts_training_schedules_ScheduleId",
                    column: x => x.ScheduleId,
                    principalSchema: "training",
                    principalTable: "training_schedules",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_training_schedule_shifts_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "training_schedule_slots",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ScheduleId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                PlanId = table.Column<Guid>(type: "uuid", nullable: true),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_training_schedule_slots", x => x.Id);
                table.CheckConstraint("CK_training_schedule_slots_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_training_schedule_slots_training_plans_UserId_PlanId",
                    columns: x => new { x.UserId, x.PlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_training_schedule_slots_training_schedules_ScheduleId",
                    column: x => x.ScheduleId,
                    principalSchema: "training",
                    principalTable: "training_schedules",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_training_schedule_slots_users_UserId",
                    column: x => x.UserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_exceptions_ScheduleId_Date_PlanId",
            schema: "training",
            table: "training_schedule_exceptions",
            columns: new[] { "ScheduleId", "Date", "PlanId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_exceptions_ScheduleId_Position",
            schema: "training",
            table: "training_schedule_exceptions",
            columns: new[] { "ScheduleId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_exceptions_UserId_PlanId",
            schema: "training",
            table: "training_schedule_exceptions",
            columns: new[] { "UserId", "PlanId" });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_exceptions_UserId_ScheduleId",
            schema: "training",
            table: "training_schedule_exceptions",
            columns: new[] { "UserId", "ScheduleId" });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_shifts_ScheduleId_Position",
            schema: "training",
            table: "training_schedule_shifts",
            columns: new[] { "ScheduleId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_shifts_UserId_ScheduleId",
            schema: "training",
            table: "training_schedule_shifts",
            columns: new[] { "UserId", "ScheduleId" });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_slots_ScheduleId_Position",
            schema: "training",
            table: "training_schedule_slots",
            columns: new[] { "ScheduleId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_slots_UserId_PlanId",
            schema: "training",
            table: "training_schedule_slots",
            columns: new[] { "UserId", "PlanId" });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedule_slots_UserId_ScheduleId",
            schema: "training",
            table: "training_schedule_slots",
            columns: new[] { "UserId", "ScheduleId" });

        migrationBuilder.CreateIndex(
            name: "IX_training_schedules_UserId",
            schema: "training",
            table: "training_schedules",
            column: "UserId",
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "training_schedule_exceptions",
            schema: "training");

        migrationBuilder.DropTable(
            name: "training_schedule_shifts",
            schema: "training");

        migrationBuilder.DropTable(
            name: "training_schedule_slots",
            schema: "training");

        migrationBuilder.DropTable(
            name: "training_schedules",
            schema: "training");

        migrationBuilder.CreateTable(
            name: "workout_rotations",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false)
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
            });

        migrationBuilder.CreateTable(
            name: "workout_rotation_items",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                PlanId = table.Column<Guid>(type: "uuid", nullable: false),
                Position = table.Column<int>(type: "integer", nullable: false),
                RotationId = table.Column<Guid>(type: "uuid", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_workout_rotation_items", x => x.Id);
                table.CheckConstraint("CK_workout_rotation_items_position", "\"Position\" >= 0");
                table.ForeignKey(
                    name: "FK_workout_rotation_items_training_plans_UserId_PlanId",
                    columns: x => new { x.UserId, x.PlanId },
                    principalSchema: "training",
                    principalTable: "training_plans",
                    principalColumns: new[] { "UserId", "Id" },
                    onDelete: ReferentialAction.Restrict);
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
            });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_PlanId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "PlanId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_RotationId_Position",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "RotationId", "Position" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_UserId_PlanId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "UserId", "PlanId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotation_items_UserId_RotationId",
            schema: "training",
            table: "workout_rotation_items",
            columns: new[] { "UserId", "RotationId" });

        migrationBuilder.CreateIndex(
            name: "IX_workout_rotations_UserId",
            schema: "training",
            table: "workout_rotations",
            column: "UserId",
            unique: true);
    }
}
