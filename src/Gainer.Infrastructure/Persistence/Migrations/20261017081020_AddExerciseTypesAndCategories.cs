using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddExerciseTypesAndCategories : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "BodyweightFactor",
            schema: "training",
            table: "exercises",
            type: "numeric(5,4)",
            precision: 5,
            scale: 4,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "ExerciseType",
            schema: "training",
            table: "exercises",
            type: "character varying(32)",
            maxLength: 32,
            nullable: false,
            defaultValue: "strength");

        migrationBuilder.AddColumn<string>(
            name: "Notes",
            schema: "training",
            table: "exercises",
            type: "character varying(2000)",
            maxLength: 2000,
            nullable: true);

        migrationBuilder.AddColumn<decimal>(
            name: "WeightFactor",
            schema: "training",
            table: "exercises",
            type: "numeric(5,3)",
            precision: 5,
            scale: 3,
            nullable: true);

        migrationBuilder.CreateTable(
            name: "exercise_categories",
            schema: "training",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                OwnerUserId = table.Column<Guid>(type: "uuid", nullable: true),
                Name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                CatalogVersion = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                Version = table.Column<long>(type: "bigint", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_exercise_categories", x => x.Id);
                table.CheckConstraint("CK_exercise_categories_catalog_ownership", "(\"OwnerUserId\" IS NULL AND \"CatalogVersion\" IS NOT NULL AND \"IsArchived\" = FALSE) OR (\"OwnerUserId\" IS NOT NULL AND \"CatalogVersion\" IS NULL)");
                table.CheckConstraint("CK_exercise_categories_name", "length(trim(\"Name\")) > 0");
                table.ForeignKey(
                    name: "FK_exercise_categories_users_OwnerUserId",
                    column: x => x.OwnerUserId,
                    principalSchema: "identity",
                    principalTable: "users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "exercise_category_assignments",
            schema: "training",
            columns: table => new
            {
                ExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                CategoryId = table.Column<Guid>(type: "uuid", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_exercise_category_assignments", x => new { x.ExerciseId, x.CategoryId });
                table.ForeignKey(
                    name: "FK_exercise_category_assignments_exercise_categories_CategoryId",
                    column: x => x.CategoryId,
                    principalSchema: "training",
                    principalTable: "exercise_categories",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_exercise_category_assignments_exercises_ExerciseId",
                    column: x => x.ExerciseId,
                    principalSchema: "training",
                    principalTable: "exercises",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercise_categories",
            columns: new[] { "Id", "CatalogVersion", "CreatedAtUtc", "IsArchived", "Name", "OwnerUserId", "UpdatedAtUtc", "Version" },
            values: new object[,]
            {
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Rücken", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Ganzkörper", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Waden", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Gesäß", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Beine", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Trizeps", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Schultern", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Bizeps", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Brust", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), "2026.10.1", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Bauch", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L }
            });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { 1.0m, "2026.10.1", "bodyweightLoaded", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            columns: new[] { "BodyweightFactor", "CatalogVersion", "ExerciseType", "Notes", "UpdatedAtUtc", "WeightFactor" },
            values: new object[] { null, "2026.10.1", "strength", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), null });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercises",
            columns: new[] { "Id", "BodyweightFactor", "CatalogVersion", "CreatedAtUtc", "Description", "Equipment", "ExerciseType", "IsArchived", "MuscleGroup", "Name", "Notes", "OwnerUserId", "TargetMuscle", "UpdatedAtUtc", "Version", "WeightFactor" },
            values: new object[,]
            {
                { new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"), 0.64m, "2026.10.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Bodyweight", "bodyweightOnly", false, "Chest", "Push-Up", null, null, "Pectoralis major", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"), 1.0m, "2026.10.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), null, "Bodyweight", "bodyweightLoaded", false, "Arms", "Dips", null, null, "Triceps brachii", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null }
            });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercise_category_assignments",
            columns: new[] { "CategoryId", "ExerciseId" },
            values: new object[,]
            {
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("85c4145d-e045-5153-a18a-1934d16ad4de") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e") }
            });

        migrationBuilder.AddCheckConstraint(
            name: "CK_exercises_bodyweight_factor",
            schema: "training",
            table: "exercises",
            sql: "\"BodyweightFactor\" IS NULL OR (\"BodyweightFactor\" >= 0 AND \"BodyweightFactor\" <= 1)");

        migrationBuilder.AddCheckConstraint(
            name: "CK_exercises_type",
            schema: "training",
            table: "exercises",
            sql: "\"ExerciseType\" IN ('strength', 'bodyweightLoaded', 'bodyweightOnly', 'assisted')");

        migrationBuilder.AddCheckConstraint(
            name: "CK_exercises_weight_factor",
            schema: "training",
            table: "exercises",
            sql: "\"WeightFactor\" IS NULL OR (\"WeightFactor\" > 0 AND \"WeightFactor\" <= 10)");

        migrationBuilder.CreateIndex(
            name: "IX_exercise_categories_OwnerUserId_Name",
            schema: "training",
            table: "exercise_categories",
            columns: new[] { "OwnerUserId", "Name" });

        migrationBuilder.CreateIndex(
            name: "IX_exercise_category_assignments_CategoryId",
            schema: "training",
            table: "exercise_category_assignments",
            column: "CategoryId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "exercise_category_assignments",
            schema: "training");

        migrationBuilder.DropTable(
            name: "exercise_categories",
            schema: "training");

        migrationBuilder.DropCheckConstraint(
            name: "CK_exercises_bodyweight_factor",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropCheckConstraint(
            name: "CK_exercises_type",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropCheckConstraint(
            name: "CK_exercises_weight_factor",
            schema: "training",
            table: "exercises");

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"));

        migrationBuilder.DropColumn(
            name: "BodyweightFactor",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropColumn(
            name: "ExerciseType",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropColumn(
            name: "Notes",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropColumn(
            name: "WeightFactor",
            schema: "training",
            table: "exercises");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            columns: new[] { "CatalogVersion", "UpdatedAtUtc" },
            values: new object[] { "2026.08.1", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc) });
    }
}
