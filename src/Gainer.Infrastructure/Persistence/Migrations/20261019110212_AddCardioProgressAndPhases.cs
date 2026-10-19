using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddCardioProgressAndPhases : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>(
            name: "RestingHeartRateBpm",
            schema: "tracking",
            table: "daily_check_ins",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "RestingHrvMs",
            schema: "tracking",
            table: "daily_check_ins",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "Phases",
            schema: "training",
            table: "cardio_sessions",
            type: "jsonb",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "RecoveryEndBpm",
            schema: "training",
            table: "cardio_sessions",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "RecoveryStartBpm",
            schema: "training",
            table: "cardio_sessions",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "TemplateName",
            schema: "training",
            table: "cardio_sessions",
            type: "character varying(100)",
            maxLength: 100,
            nullable: true);

        migrationBuilder.AddCheckConstraint(
            name: "CK_daily_check_ins_resting_hr",
            schema: "tracking",
            table: "daily_check_ins",
            sql: "\"RestingHeartRateBpm\" IS NULL OR (\"RestingHeartRateBpm\" >= 25 AND \"RestingHeartRateBpm\" <= 150)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_daily_check_ins_resting_hrv",
            schema: "tracking",
            table: "daily_check_ins",
            sql: "\"RestingHrvMs\" IS NULL OR (\"RestingHrvMs\" >= 1 AND \"RestingHrvMs\" <= 300)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_cardio_sessions_recovery",
            schema: "training",
            table: "cardio_sessions",
            sql: "(\"RecoveryStartBpm\" IS NULL AND \"RecoveryEndBpm\" IS NULL) OR (\"RecoveryStartBpm\" BETWEEN 25 AND 250 AND \"RecoveryEndBpm\" BETWEEN 25 AND 250)");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropCheckConstraint(
            name: "CK_daily_check_ins_resting_hr",
            schema: "tracking",
            table: "daily_check_ins");

        migrationBuilder.DropCheckConstraint(
            name: "CK_daily_check_ins_resting_hrv",
            schema: "tracking",
            table: "daily_check_ins");

        migrationBuilder.DropCheckConstraint(
            name: "CK_cardio_sessions_recovery",
            schema: "training",
            table: "cardio_sessions");

        migrationBuilder.DropColumn(
            name: "RestingHeartRateBpm",
            schema: "tracking",
            table: "daily_check_ins");

        migrationBuilder.DropColumn(
            name: "RestingHrvMs",
            schema: "tracking",
            table: "daily_check_ins");

        migrationBuilder.DropColumn(
            name: "Phases",
            schema: "training",
            table: "cardio_sessions");

        migrationBuilder.DropColumn(
            name: "RecoveryEndBpm",
            schema: "training",
            table: "cardio_sessions");

        migrationBuilder.DropColumn(
            name: "RecoveryStartBpm",
            schema: "training",
            table: "cardio_sessions");

        migrationBuilder.DropColumn(
            name: "TemplateName",
            schema: "training",
            table: "cardio_sessions");
    }
}
