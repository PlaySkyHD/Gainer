using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddExerciseMuscles : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string[]>(
            name: "PrimaryMuscles",
            schema: "training",
            table: "exercises",
            type: "text[]",
            nullable: false,
            defaultValueSql: "'{}'::text[]");

        migrationBuilder.AddColumn<string[]>(
            name: "SecondaryMuscles",
            schema: "training",
            table: "exercises",
            type: "text[]",
            nullable: false,
            defaultValueSql: "'{}'::text[]");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("092c9ade-1948-412b-927c-7daea71fb381"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("6272a453-0cdc-4bae-90db-e299fca34817"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("74d2162c-349e-4845-b808-da9339b9d497"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"),
            column: "CatalogVersion",
            value: "2026.10.2");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "chest" }, new[] { "triceps", "frontDelts" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "quads", "glutes" }, new[] { "adductors", "lowerBack" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "hamstrings", "glutes" }, new[] { "lowerBack" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "lats" }, new[] { "biceps", "rearDelts" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "chest" }, new[] { "triceps", "frontDelts", "abs" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "lats" }, new[] { "biceps", "traps", "forearms" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "traps", "lats" }, new[] { "rearDelts", "biceps" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "sideDelts" }, new[] { "traps" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "triceps" }, new[] { "chest", "frontDelts" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "frontDelts" }, new[] { "sideDelts", "triceps" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "hamstrings" }, new[] { "calves" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "quads" }, new string[0] });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "biceps" }, new[] { "forearms" } });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            columns: new[] { "CatalogVersion", "PrimaryMuscles", "SecondaryMuscles" },
            values: new object[] { "2026.10.2", new[] { "triceps" }, new string[0] });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "PrimaryMuscles",
            schema: "training",
            table: "exercises");

        migrationBuilder.DropColumn(
            name: "SecondaryMuscles",
            schema: "training",
            table: "exercises");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("092c9ade-1948-412b-927c-7daea71fb381"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("6272a453-0cdc-4bae-90db-e299fca34817"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("74d2162c-349e-4845-b808-da9339b9d497"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            column: "CatalogVersion",
            value: "2026.10.1");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            column: "CatalogVersion",
            value: "2026.10.1");
    }
}
