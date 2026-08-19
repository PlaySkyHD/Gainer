using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddExerciseCatalog : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.EnsureSchema(
            name: "training");

        migrationBuilder.CreateTable(
            name: "exercises",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                OwnerUserId = table.Column<Guid>(type: "uuid", nullable: true),
                Name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Description = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                TargetMuscle = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                MuscleGroup = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                Equipment = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                CatalogVersion = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_exercises", x => x.Id);
                table.CheckConstraint("CK_exercises_catalog_ownership", "(\"OwnerUserId\" IS NULL AND \"CatalogVersion\" IS NOT NULL AND \"IsArchived\" = FALSE) OR (\"OwnerUserId\" IS NOT NULL AND \"CatalogVersion\" IS NULL)");
                table.CheckConstraint("CK_exercises_name", "length(trim(\"Name\")) > 0");
                table.ForeignKey(
                    name: "FK_exercises_users_OwnerUserId",
                    column: x => x.OwnerUserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercises",
            columns: new[] { "Id", "CatalogVersion", "CreatedAtUtc", "Description", "Equipment", "IsArchived", "MuscleGroup", "Name", "OwnerUserId", "TargetMuscle", "UpdatedAtUtc", "Version" },
            values: new object[,]
            {
                { new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Barbell", false, "Chest", "Barbell Bench Press", null, "Pectoralis major", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Barbell", false, "Legs", "Back Squat", null, "Quadriceps", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Barbell", false, "Legs", "Romanian Deadlift", null, "Hamstrings", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Cable", false, "Back", "Lat Pulldown", null, "Latissimus dorsi", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Bodyweight", false, "Back", "Pull-Up", null, "Latissimus dorsi", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Cable", false, "Back", "Seated Cable Row", null, "Rhomboids", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Dumbbell", false, "Shoulders", "Dumbbell Lateral Raise", null, "Lateral deltoid", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Barbell", false, "Shoulders", "Standing Overhead Press", null, "Anterior deltoid", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Machine", false, "Legs", "Leg Curl", null, "Hamstrings", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Machine", false, "Legs", "Leg Extension", null, "Quadriceps", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Dumbbell", false, "Arms", "Dumbbell Biceps Curl", null, "Biceps brachii", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"), "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Cable", false, "Arms", "Cable Triceps Pushdown", null, "Triceps brachii", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), 1L }
            });

        migrationBuilder.CreateIndex(
            name: "IX_exercises_OwnerUserId_Equipment",
            schema: "training",
            table: "exercises",
            columns: new[] { "OwnerUserId", "Equipment" });

        migrationBuilder.CreateIndex(
            name: "IX_exercises_OwnerUserId_MuscleGroup",
            schema: "training",
            table: "exercises",
            columns: new[] { "OwnerUserId", "MuscleGroup" });

        migrationBuilder.CreateIndex(
            name: "IX_exercises_OwnerUserId_Name",
            schema: "training",
            table: "exercises",
            columns: new[] { "OwnerUserId", "Name" });

        migrationBuilder.CreateIndex(
            name: "IX_exercises_OwnerUserId_TargetMuscle",
            schema: "training",
            table: "exercises",
            columns: new[] { "OwnerUserId", "TargetMuscle" });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "exercises",
            schema: "training");
    }
}
