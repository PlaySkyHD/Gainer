using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Gainer.Infrastructure.Persistence.Migrations;

/// <inheritdoc />
public partial class AddGermanExerciseCatalog : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("092c9ade-1948-412b-927c-7daea71fb381"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("6272a453-0cdc-4bae-90db-e299fca34817"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("74d2162c-349e-4845-b808-da9339b9d497"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"),
            column: "CatalogVersion",
            value: "2026.10.3");

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercise_categories",
            columns: new[] { "Id", "CatalogVersion", "CreatedAtUtc", "IsArchived", "Name", "OwnerUserId", "UpdatedAtUtc", "Version" },
            values: new object[] { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), "2026.10.3", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), false, "Unterarme", null, new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0159d8e1-ec7a-527a-9887-5cb4f70b1c83"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Schulterblätter zusammenziehen, Stange kontrolliert zur unteren Brust senken und gerade nach oben drücken.", "Langhantel", "Brust", "Bankdrücken (Langhantel)", "Brust" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Stange auf dem oberen Rücken, Knie über den Zehen, mindestens bis zur Parallele beugen und aufrichten.", "Langhantel", "Beine", "Kniebeugen (Langhantel)", "Quadrizeps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Knie leicht gebeugt, Hüfte nach hinten schieben und Stange an den Beinen entlang bis unter die Knie führen.", "Langhantel", "Beine", "Rumänisches Kreuzheben (Langhantel)", "Beinbeuger" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Breiter Griff, Stange zur oberen Brust ziehen, Schulterblätter nach unten führen.", "Kabelzug", "Rücken", "Latziehen (Kabelzug)", "Latissimus" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Körper bildet eine Linie, Brust bis knapp über den Boden senken und hochdrücken.", "Körpergewicht", "Brust", "Liegestütze", "Brust" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Obergriff etwas breiter als schulterbreit, Brust zur Stange ziehen und kontrolliert ablassen.", "Körpergewicht", "Rücken", "Klimmzüge", "Latissimus" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Aufrecht sitzen, Griff zum Bauch ziehen, Schulterblätter zusammenführen.", "Kabelzug", "Rücken", "Rudern sitzend (Kabelzug)", "Oberer Rücken" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Arme leicht gebeugt seitlich bis auf Schulterhöhe heben und langsam senken.", "Kurzhantel", "Schultern", "Seitheben (Kurzhantel)", "Seitliche Schulter" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "PrimaryMuscles", "SecondaryMuscles", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Am Barren absenken, bis die Oberarme etwa waagerecht sind, und hochdrücken. Vorlage betont die Brust.", "Körpergewicht", "Arme", new[] { "triceps", "chest" }, new[] { "frontDelts" }, "Trizeps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Stange vor den Schultern, Bauch fest, über den Kopf drücken und kontrolliert senken.", "Langhantel", "Schultern", "Schulterdrücken stehend (Langhantel)", "Vordere Schulter" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Bauchlage, Polster über den Fersen, Beine zum Gesäß beugen.", "Maschine", "Beine", "Beinbeuger liegend (Maschine)", "Beinbeuger" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Polster über dem Sprunggelenk, Beine strecken und langsam beugen.", "Maschine", "Beine", "Beinstrecker (Maschine)", "Quadrizeps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Ellbogen fest am Körper, Hanteln nach oben beugen und langsam senken.", "Kurzhantel", "Arme", "Bizepscurls (Kurzhantel)", "Bizeps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.3", "Ellbogen am Körper, Stange nach unten strecken und langsam zurückführen.", "Kabelzug", "Arme", "Trizepsdrücken am Kabel", "Trizeps" });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercises",
            columns: new[] { "Id", "BodyweightFactor", "CatalogVersion", "CreatedAtUtc", "Description", "Equipment", "ExerciseType", "IsArchived", "MuscleGroup", "Name", "Notes", "OwnerUserId", "PrimaryMuscles", "SecondaryMuscles", "TargetMuscle", "UpdatedAtUtc", "Version", "WeightFactor" },
            values: new object[,]
            {
                { new Guid("03080ed4-c8ff-564a-b2cd-76abbd85543e"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Brust an das Polster, Griffe nach hinten ziehen und Schulterblätter zusammenführen.", "Maschine", "strength", false, "Rücken", "Rudermaschine", null, null, new[] { "traps", "lats" }, new[] { "rearDelts", "biceps" }, "Oberer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("05243d54-7f56-59b6-a901-76abb7272c44"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Stange im Nacken, mit geradem Rücken aus der Hüfte nach vorn beugen und aufrichten.", "Langhantel", "strength", false, "Beine", "Good Mornings (Langhantel)", null, null, new[] { "hamstrings", "lowerBack" }, new[] { "glutes" }, "Beinbeuger", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("086f9bcf-5f98-5a17-b2a4-a90ac5636c5f"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Griffe auf Schulterhöhe, nach oben drücken ohne die Ellbogen zu überstrecken.", "Maschine", "strength", false, "Schultern", "Schulterpresse (Maschine)", null, null, new[] { "frontDelts" }, new[] { "sideDelts", "triceps" }, "Vordere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("0bd909a0-6d57-5b36-bebe-38a3461356bb"), 1.0m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Gegengewicht einstellen, Brust zum Griff ziehen und kontrolliert ablassen.", "Maschine", "assisted", false, "Rücken", "Klimmzüge (Maschine, unterstützt)", null, null, new[] { "lats" }, new[] { "biceps", "traps" }, "Latissimus", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("0e371e65-35fe-5bbe-b5f4-b926844b57ef"), 0.35m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rückenlage, Oberkörper ganz bis zu den Knien aufrichten und langsam ablegen.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Sit-ups", null, null, new[] { "abs" }, new[] { "obliques" }, "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("0f45fbc5-d727-586d-b1b2-b035750eb14a"), 0.5m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Kniend den Roller nach vorn rollen, Rumpf fest, und zurückziehen.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Ab Roller", null, null, new[] { "abs" }, new[] { "obliques", "lats" }, "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("10e59c06-7d69-5c46-82e1-6ccc7abc94d4"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Auf der Negativbank die Füße fixieren, Stange zur unteren Brust senken und drücken.", "Langhantel", "strength", false, "Brust", "Negativbankdrücken (Langhantel)", null, null, new[] { "chest" }, new[] { "triceps", "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hinterer Fuß auf der Bank, vorderes Knie beugen, bis der Oberschenkel waagerecht ist.", "Kurzhantel", "strength", false, "Beine", "Bulgarische Kniebeugen (Kurzhantel)", null, null, new[] { "quads", "glutes" }, new[] { "hamstrings", "adductors" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("12db891f-8392-5c1c-a58c-8c7ec6a7f524"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hanteln vor dem Gesicht starten und beim Drücken nach außen drehen.", "Kurzhantel", "strength", false, "Schultern", "Arnold Press (Kurzhantel)", null, null, new[] { "frontDelts", "sideDelts" }, new[] { "triceps" }, "Vordere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("1e1bfeca-1578-5879-b3b3-1e605d2d2ef2"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Polster auf den Knien, Fersen senken und hochdrücken.", "Maschine", "strength", false, "Beine", "Wadenheben sitzend (Maschine)", null, null, new[] { "calves" }, new string[0], "Waden", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("2275dcf2-eea6-5e3c-aab9-2dcbe8921f12"), 0.3m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rückenlage, Schultern einrollend vom Boden heben, unterer Rücken bleibt liegen.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Crunches", null, null, new[] { "abs" }, new string[0], "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("229a8cc8-c04f-56c5-a2f3-6553b8e8d7e3"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Schulterbreiter Untergriff, Stange ohne Schwung zur Brust beugen.", "Langhantel", "strength", false, "Arme", "Bizepscurls (Langhantel)", null, null, new[] { "biceps" }, new[] { "forearms" }, "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("236f46fc-a6a9-58c0-835a-6fe98a944ec4"), 0.5m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Auf Unterarmen und Zehen, Körper in einer Linie halten.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Unterarmstütz (Plank)", null, null, new[] { "abs" }, new[] { "obliques", "frontDelts" }, "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("25af3a6e-1c74-5047-96c3-00d852283daa"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Großer Schritt nach vorn, beide Knie etwa 90° beugen und zurück in den Stand.", "Kurzhantel", "strength", false, "Beine", "Ausfallschritte (Kurzhantel)", null, null, new[] { "quads", "glutes" }, new[] { "hamstrings", "adductors" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("29cc1745-868d-5339-9c2f-38b8efa2cfaa"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Am gewinkelten Griff fassen, Ellbogen ruhig halten und beugen.", "SZ-Stange", "strength", false, "Arme", "Bizepscurls (SZ-Stange)", null, null, new[] { "biceps" }, new[] { "forearms" }, "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("2affd637-a6a2-577f-809a-11bd7162ca66"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Seitlich zum Kabel stehen und den Griff mit leicht gebeugtem Arm bis auf Schulterhöhe führen.", "Kabelzug", "strength", false, "Schultern", "Seitheben am Kabel", null, null, new[] { "sideDelts" }, new[] { "traps" }, "Seitliche Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("2d3197eb-0518-5851-b49e-b8f81a60665e"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hanteln neben der Brust absenken, Ellbogen etwa 45° vom Körper, und über der Brust zusammenführen.", "Kurzhantel", "strength", false, "Brust", "Bankdrücken (Kurzhantel)", null, null, new[] { "chest" }, new[] { "triceps", "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("2e855905-c74d-5971-96ff-1dadfc819714"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Brust an das Polster, Arme nach hinten öffnen und kontrolliert zurückführen.", "Maschine", "strength", false, "Schultern", "Reverse Butterfly (Maschine)", null, null, new[] { "rearDelts" }, new[] { "traps" }, "Hintere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("39c2b212-ad72-55f0-b6e4-030c369508cd"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Griff diagonal von oben nach unten vor dem Körper ziehen, aus dem Rumpf drehen.", "Kabelzug", "strength", false, "Bauch", "Holzhacker am Kabel", null, null, new[] { "obliques" }, new[] { "abs" }, "Seitliche Bauchmuskeln", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Stange nah am Schienbein, Rücken gerade, aus Hüfte und Beinen aufrichten und kontrolliert absetzen.", "Langhantel", "strength", false, "Ganzkörper", "Kreuzheben (Langhantel)", null, null, new[] { "glutes", "hamstrings", "lowerBack" }, new[] { "quads", "traps", "forearms" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("44c0cd21-56dd-5f2f-bf59-35bc94f3e063"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Enger Griff, Ellbogen nah am Körper zur Brust ziehen.", "Kabelzug", "strength", false, "Rücken", "Latziehen enger Griff (Kabelzug)", null, null, new[] { "lats" }, new[] { "biceps", "traps" }, "Latissimus", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("44d234a4-34e6-5b2d-95eb-a71bff470668"), 0.35m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "An der Stange hängend die Beine ohne Schwung bis mindestens waagerecht heben.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Beinheben hängend", null, null, new[] { "abs" }, new[] { "obliques", "forearms" }, "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("45659e6e-0a11-5297-b807-50efe2f621ba"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberschenkel fixiert, Polster unter den Waden nach unten und hinten beugen.", "Maschine", "strength", false, "Beine", "Beinbeuger sitzend (Maschine)", null, null, new[] { "hamstrings" }, new[] { "calves" }, "Beinbeuger", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Füße schulterbreit auf der Platte, Knie bis etwa 90° beugen und drücken, ohne die Knie zu überstrecken.", "Maschine", "strength", false, "Beine", "Beinpresse", null, null, new[] { "quads", "glutes" }, new[] { "hamstrings", "adductors" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("4abccd2a-994c-5e49-afc0-9c953554a51e"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Vorgebeugt, Oberarm am Körper, Unterarm nach hinten strecken.", "Kurzhantel", "strength", false, "Arme", "Trizeps-Kickbacks (Kurzhantel)", null, null, new[] { "triceps" }, new string[0], "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("53bb5413-c0c8-5031-b63e-f7cd672f328e"), 0.3m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rückenlage, Beine gestreckt anheben und kurz über dem Boden senken.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Beinheben liegend", null, null, new[] { "abs" }, new string[0], "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("54522c07-9525-59f5-abea-c989f0abfe92"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Kettlebell aus der Hüfte nach vorn schwingen, Hüfte explosiv strecken.", "Kettlebell", "strength", false, "Beine", "Kettlebell Swings", null, null, new[] { "glutes", "hamstrings" }, new[] { "lowerBack", "abs", "forearms" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Schwere Hanteln seitlich halten und aufrecht eine Strecke gehen.", "Kurzhantel", "strength", false, "Ganzkörper", "Farmer's Walk (Kurzhantel)", null, null, new[] { "forearms", "traps" }, new[] { "abs", "quads" }, "Unterarme", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("5f259881-118c-52cc-980c-5405130adc79"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberkörper etwa 45° vorgeneigt, Stange zum Bauchnabel ziehen und kontrolliert senken.", "Langhantel", "strength", false, "Rücken", "Langhantelrudern", null, null, new[] { "traps", "lats" }, new[] { "rearDelts", "biceps", "lowerBack" }, "Oberer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("5f8e9f25-aa1a-5fc7-b9c3-f7774df7373a"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Knie und Hand auf der Bank, Hantel zur Hüfte ziehen, Ellbogen nah am Körper.", "Kurzhantel", "strength", false, "Rücken", "Kurzhantelrudern einarmig", null, null, new[] { "lats", "traps" }, new[] { "rearDelts", "biceps" }, "Latissimus", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("60ffef06-d690-5441-917d-7ae3d7f09a9c"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberer Rücken an der Bank, Stange auf der Hüfte, Hüfte strecken bis der Körper eine Linie bildet.", "Langhantel", "strength", false, "Beine", "Hip Thrust (Langhantel)", null, null, new[] { "glutes" }, new[] { "hamstrings", "quads" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("641a2f34-5596-5101-9cd9-19c7c471fb10"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Griffe nach unten drücken, bis die Arme gestreckt sind.", "Maschine", "strength", false, "Arme", "Dips-Maschine", null, null, new[] { "triceps" }, new[] { "chest" }, "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("65c2005c-8285-5963-978e-e3fbb5cb5105"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Vorgebeugt die Hanteln seitlich nach außen heben, Schulterblätter zusammenführen.", "Kurzhantel", "strength", false, "Schultern", "Reverse Flys (Kurzhantel)", null, null, new[] { "rearDelts" }, new[] { "traps" }, "Hintere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Mit einem Fuß auf die Bank steigen und über dieses Bein ganz aufrichten.", "Kurzhantel", "strength", false, "Beine", "Step-ups (Kurzhantel)", null, null, new[] { "quads", "glutes" }, new[] { "hamstrings" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Breiter Stand, Füße nach außen, Griff innen. Hüfte nach vorn schieben und aufrichten.", "Langhantel", "strength", false, "Beine", "Sumo-Kreuzheben (Langhantel)", null, null, new[] { "glutes", "quads", "adductors" }, new[] { "hamstrings", "lowerBack" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("6bca7c42-b716-5990-bd5a-a364ac0ccb93"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Griffe mit leicht gebeugten Armen vor dem Körper zusammenführen und langsam öffnen.", "Kabelzug", "strength", false, "Brust", "Cable Crossover (Kabelzug)", null, null, new[] { "chest" }, new[] { "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("6effd19e-2690-55e4-8f7a-9000525295b4"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Fußballen auf der Kante, Fersen tief senken und so hoch wie möglich drücken.", "Maschine", "strength", false, "Beine", "Wadenheben stehend (Maschine)", null, null, new[] { "calves" }, new string[0], "Waden", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Seil auf Gesichtshöhe zum Gesicht ziehen, Ellbogen hoch und nach außen.", "Kabelzug", "strength", false, "Schultern", "Face Pulls (Kabelzug)", null, null, new[] { "rearDelts", "traps" }, new[] { "sideDelts" }, "Hintere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("74a1130e-6980-52f1-8381-aba08116edf2"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Liegend die Stange zur Stirn senken, Oberarme ruhig, und strecken.", "SZ-Stange", "strength", false, "Arme", "Stirndrücken (SZ-Stange)", null, null, new[] { "triceps" }, new string[0], "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("74cac498-ac7c-5ec7-ae15-cedbaaa349a8"), 0.6m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hände auf der Bankkante, Körper absenken, bis die Ellbogen etwa 90° gebeugt sind.", "Körpergewicht", "bodyweightOnly", false, "Arme", "Dips an der Bank", null, null, new[] { "triceps" }, new[] { "chest", "frontDelts" }, "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("77fa1c52-ae8a-5dee-81bf-6ee8730e5a6b"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Fußballen an der unteren Plattenkante, mit gestreckten Beinen die Platte wegdrücken.", "Maschine", "strength", false, "Beine", "Wadendrücken an der Beinpresse", null, null, new[] { "calves" }, new string[0], "Waden", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("7c4c128e-d0d5-5ed5-85f3-4eb927e51ca1"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Sitzend, Ellbogen am Oberschenkel, Hantel langsam nach oben beugen.", "Kurzhantel", "strength", false, "Arme", "Konzentrationscurls (Kurzhantel)", null, null, new[] { "biceps" }, new string[0], "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Auf einem Bein stehen, Oberkörper nach vorn neigen, das freie Bein nach hinten strecken und aufrichten.", "Kurzhantel", "strength", false, "Beine", "Einbeiniges Kreuzheben (Kurzhantel)", null, null, new[] { "hamstrings", "glutes" }, new[] { "lowerBack" }, "Beinbeuger", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("7e364c6d-572f-5b03-a4c1-b962b8c84138"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hanteln mit fast gestreckten Armen nach vorn bis auf Schulterhöhe heben.", "Kurzhantel", "strength", false, "Schultern", "Frontheben (Kurzhantel)", null, null, new[] { "frontDelts" }, new[] { "sideDelts" }, "Vordere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("8a0227e3-674f-5423-9c80-a2a489fb0296"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Vor dem Kabelzug stehen, Griff mit ruhigen Ellbogen zur Brust beugen.", "Kabelzug", "strength", false, "Arme", "Bizepscurls am Kabel", null, null, new[] { "biceps" }, new[] { "forearms" }, "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("8cd645c2-6cad-54e9-adc7-96b85efbbbea"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Beine gegen die Polster nach innen drücken und langsam öffnen.", "Maschine", "strength", false, "Beine", "Adduktoren-Maschine", null, null, new[] { "adductors" }, new string[0], "Adduktoren", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("9226da76-685c-5f7d-9401-656478d870c1"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hantel mit beiden Händen hinter dem Kopf absenken und nach oben strecken.", "Kurzhantel", "strength", false, "Arme", "Trizepsstrecken über Kopf (Kurzhantel)", null, null, new[] { "triceps" }, new string[0], "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("94d5b795-73fc-5442-bef7-3e862e49fd38"), 0.6m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Unter einer Stange hängend, Körper gestreckt, Brust zur Stange ziehen.", "Körpergewicht", "bodyweightOnly", false, "Rücken", "Rudern mit Körpergewicht", null, null, new[] { "traps", "lats" }, new[] { "biceps", "rearDelts" }, "Oberer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("986c4b0b-a86e-5a91-88bd-31c12295de92"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Griffe auf Brusthöhe, nach vorn drücken ohne die Ellbogen ganz durchzustrecken.", "Maschine", "strength", false, "Brust", "Brustpresse (Maschine)", null, null, new[] { "chest" }, new[] { "triceps", "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("989e913f-217a-5888-a862-99534b7fc991"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Quer auf der Bank, Hantel mit leicht gebeugten Armen hinter den Kopf senken und über die Brust zurückführen.", "Kurzhantel", "strength", false, "Brust", "Überzüge (Kurzhantel)", null, null, new[] { "chest", "lats" }, new[] { "triceps" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("9f814341-7b1e-5432-8829-f614d124e1c9"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rücken an die Lehne, Arme vor der Brust zusammenführen und kontrolliert öffnen.", "Maschine", "strength", false, "Brust", "Butterfly (Maschine)", null, null, new[] { "chest" }, new[] { "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hantel vor der Brust halten, tief in die Hocke gehen und aufrichten.", "Kurzhantel", "strength", false, "Beine", "Goblet Squat (Kurzhantel)", null, null, new[] { "quads", "glutes" }, new[] { "adductors", "abs" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("a58cd97f-0716-5e81-8f90-1e04fb8bbc8f"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Schultern gerade nach oben ziehen, kurz halten und langsam senken.", "Kurzhantel", "strength", false, "Rücken", "Shrugs (Kurzhantel)", null, null, new[] { "traps" }, new[] { "forearms" }, "Oberer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("a83bab61-2249-5820-921d-772b161cd3c6"), 0.5m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rückenlage, Füße aufgestellt, Hüfte anheben und Gesäß anspannen.", "Körpergewicht", "bodyweightOnly", false, "Beine", "Glute Bridge", null, null, new[] { "glutes" }, new[] { "hamstrings" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("aa3a48cb-b062-5c1f-9897-98d942edbc7d"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberarme auf dem Polster, Griffe beugen und kontrolliert zurückführen.", "Maschine", "strength", false, "Arme", "Bizepsmaschine", null, null, new[] { "biceps" }, new string[0], "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("ad879102-4b1e-50b6-882a-d3dcf69d1d7c"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Vorgebeugt mit geradem Rücken die Stange zur Brust ziehen.", "Langhantel", "strength", false, "Rücken", "T-Bar-Rudern", null, null, new[] { "traps", "lats" }, new[] { "rearDelts", "biceps", "lowerBack" }, "Oberer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Füße etwas vor der Stange, kontrolliert beugen und aufrichten.", "Smith-Maschine", "strength", false, "Beine", "Kniebeugen (Smith-Maschine)", null, null, new[] { "quads", "glutes" }, new[] { "adductors" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("bab9f487-2071-5e56-a7b6-14b0e3f3feda"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Seil nach unten strecken und am Ende die Enden nach außen ziehen.", "Kabelzug", "strength", false, "Arme", "Trizepsdrücken mit Seil", null, null, new[] { "triceps" }, new string[0], "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("bc15eeae-3bb8-57d8-b24c-12e57c1532f6"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Bank auf 30–45°, Hanteln seitlich der oberen Brust absenken und nach oben drücken.", "Kurzhantel", "strength", false, "Brust", "Schrägbankdrücken (Kurzhantel)", null, null, new[] { "chest" }, new[] { "frontDelts", "triceps" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("c4731fdc-153b-5430-baf7-9ce7d0492ff1"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Bank so stellen, dass die Stange über der unteren Brust läuft, kontrolliert senken und drücken.", "Smith-Maschine", "strength", false, "Brust", "Bankdrücken (Smith-Maschine)", null, null, new[] { "chest" }, new[] { "triceps", "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("c5c78e54-fa76-5877-8f32-a792e08ff84c"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Stange vorn auf den Schultern, Oberkörper aufrecht, tief beugen und aufrichten.", "Langhantel", "strength", false, "Beine", "Frontkniebeugen (Langhantel)", null, null, new[] { "quads" }, new[] { "glutes", "abs" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Obergriff, Stange mit ruhigen Ellbogen nach oben beugen.", "SZ-Stange", "strength", false, "Arme", "Reverse Curls (SZ-Stange)", null, null, new[] { "forearms", "biceps" }, new string[0], "Unterarme", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Daumen zeigen nach oben, Hanteln im Neutralgriff beugen.", "Kurzhantel", "strength", false, "Arme", "Hammercurls (Kurzhantel)", null, null, new[] { "biceps", "forearms" }, new string[0], "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Stange nah am Körper bis unter die Brust ziehen, Ellbogen führen.", "SZ-Stange", "strength", false, "Schultern", "Aufrechtes Rudern (SZ-Stange)", null, null, new[] { "sideDelts", "traps" }, new[] { "biceps" }, "Seitliche Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Stange explosiv vom Boden ziehen und in der Viertelhocke auf den Schultern fangen.", "Langhantel", "strength", false, "Ganzkörper", "Umsetzen (Power Clean)", null, null, new[] { "glutes", "quads", "traps" }, new[] { "hamstrings", "lowerBack", "forearms" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("d2a89607-77c8-544a-bb53-b7475fa50000"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Kniend, Seil am Kopf, Oberkörper einrollend nach unten ziehen.", "Kabelzug", "strength", false, "Bauch", "Crunches am Kabel", null, null, new[] { "abs" }, new[] { "obliques" }, "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("d426fa1e-541f-5549-8478-8f8bbc5fe055"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Unterarme auf der Bank, Hanteln nur aus dem Handgelenk nach oben rollen.", "Kurzhantel", "strength", false, "Arme", "Handgelenkcurls (Kurzhantel)", null, null, new[] { "forearms" }, new string[0], "Unterarme", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("d77c1429-d22e-531e-aa71-5fe353742448"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Beine gegen die Polster nach außen drücken und langsam schließen.", "Maschine", "strength", false, "Beine", "Abduktoren-Maschine", null, null, new[] { "glutes" }, new string[0], "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("d89adbcc-66d4-5679-9eea-df9f7f612ddf"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberkörper gegen den Widerstand einrollen und langsam zurückführen.", "Maschine", "strength", false, "Bauch", "Bauchmaschine", null, null, new[] { "abs" }, new string[0], "Bauch", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("d93ac4fe-bc50-5a04-adbc-3ce7284d25c8"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Bank auf 30–45° stellen, Stange zur oberen Brust senken und über den Schultern ausdrücken.", "Langhantel", "strength", false, "Brust", "Schrägbankdrücken (Langhantel)", null, null, new[] { "chest" }, new[] { "frontDelts", "triceps" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("dabb98cb-24ec-5323-bb22-ee5832da9aa2"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Manschette am Fuß, Bein gestreckt nach hinten führen.", "Kabelzug", "strength", false, "Beine", "Gesäß-Kickbacks am Kabel", null, null, new[] { "glutes" }, new[] { "hamstrings" }, "Gesäß", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("dd9d3216-abc9-5567-9915-5e0b465b1add"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Vom Kabel abgewandt, Seil hinter dem Kopf aus gebeugten Armen nach vorn oben strecken.", "Kabelzug", "strength", false, "Arme", "Trizepsstrecken über Kopf (Kabelzug)", null, null, new[] { "triceps" }, new string[0], "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("e12aacd1-5a12-53fe-9e2a-703c0225fb2b"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Seitlich zum Kabel, Griff vor der Brust nach vorn drücken, ohne sich zu drehen.", "Kabelzug", "strength", false, "Bauch", "Pallof Press (Kabelzug)", null, null, new[] { "obliques", "abs" }, new string[0], "Seitliche Bauchmuskeln", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("e218ff8a-a6d2-541d-babe-3b6fff7715d5"), 0.4m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Seitlich auf einem Unterarm, Hüfte anheben und halten.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Seitstütz", null, null, new[] { "obliques" }, new[] { "abs" }, "Seitliche Bauchmuskeln", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Schulterbreiter Griff, Ellbogen nah am Körper zur unteren Brust senken und drücken.", "Langhantel", "strength", false, "Arme", "Enges Bankdrücken (Langhantel)", null, null, new[] { "triceps", "chest" }, new[] { "frontDelts" }, "Trizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("e541f4f6-04fb-57d9-92b7-56a2f6ba7a1b"), 0.35m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Sitzend, Oberkörper zurückgelehnt, abwechselnd zur Seite drehen.", "Körpergewicht", "bodyweightOnly", false, "Bauch", "Russian Twist", null, null, new[] { "obliques" }, new[] { "abs" }, "Seitliche Bauchmuskeln", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("e57a1210-e482-5bca-9a45-f8cddd6474e3"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Auf der Schrägbank hängen die Arme nach hinten, Hanteln nach oben beugen.", "Kurzhantel", "strength", false, "Arme", "Schrägbank-Curls (Kurzhantel)", null, null, new[] { "biceps" }, new[] { "forearms" }, "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b"), 1.0m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Untergriff schulterbreit, Kinn über die Stange ziehen und langsam ablassen.", "Körpergewicht", "bodyweightLoaded", false, "Rücken", "Klimmzüge im Untergriff", null, null, new[] { "lats", "biceps" }, new[] { "traps", "forearms" }, "Latissimus", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("efcfc194-539c-59d2-be2b-67a011d37082"), 0.7m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "In den Liegestütz springen, Liegestütz, Beine heranziehen und mit einem Strecksprung aufrichten.", "Körpergewicht", "bodyweightOnly", false, "Ganzkörper", "Burpees", null, null, new[] { "quads", "chest", "glutes" }, new[] { "triceps", "frontDelts", "abs" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f0557f25-9c72-5c55-9e4e-b14bf71cf669"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Arme an die Polster, seitlich bis auf Schulterhöhe heben.", "Maschine", "strength", false, "Schultern", "Seitheben (Maschine)", null, null, new[] { "sideDelts" }, new[] { "traps" }, "Seitliche Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f061fbb1-0ccb-549c-be30-9ef995a1aebf"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Sitzend oder stehend die Hanteln von Schulterhöhe über den Kopf drücken.", "Kurzhantel", "strength", false, "Schultern", "Schulterdrücken (Kurzhantel)", null, null, new[] { "frontDelts" }, new[] { "sideDelts", "triceps" }, "Vordere Schulter", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f4057df2-d82e-5aff-a826-9428a7ffcdd2"), 0.5m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Hüfte am Polster, Oberkörper absenken und bis in die Verlängerung der Beine aufrichten.", "Körpergewicht", "bodyweightOnly", false, "Rücken", "Hyperextensions", null, null, new[] { "lowerBack" }, new[] { "glutes", "hamstrings" }, "Unterer Rücken", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f4bdfb0d-3874-5979-a5b4-b36db09facf1"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Oberarme auf dem Pult, Stange beugen und fast ganz strecken.", "SZ-Stange", "strength", false, "Arme", "Scottcurls (SZ-Stange)", null, null, new[] { "biceps" }, new[] { "forearms" }, "Bizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Aus der tiefen Kniebeuge aufrichten und die Hanteln in einer Bewegung über den Kopf drücken.", "Kurzhantel", "strength", false, "Ganzkörper", "Thruster (Kurzhantel)", null, null, new[] { "quads", "frontDelts", "glutes" }, new[] { "triceps", "abs" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f6a0e7a5-efdb-532c-9c7e-77754dfb329f"), 0.6m, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Kniend, Fersen fixiert, Oberkörper langsam nach vorn sinken lassen und zurückziehen.", "Körpergewicht", "bodyweightOnly", false, "Beine", "Nordic Hamstring Curls", null, null, new[] { "hamstrings" }, new[] { "glutes" }, "Beinbeuger", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Abwechselnd Ausfallschritte nach vorn gehen, Oberkörper aufrecht.", "Kurzhantel", "strength", false, "Beine", "Ausfallschritte gehend (Kurzhantel)", null, null, new[] { "quads", "glutes" }, new[] { "hamstrings", "adductors" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("f7939d2f-d3d2-5636-9c97-07512964e64a"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Mit fast gestreckten Armen die Stange in einem Bogen bis zu den Oberschenkeln ziehen.", "Kabelzug", "strength", false, "Rücken", "Überzüge am Kabel", null, null, new[] { "lats" }, new[] { "triceps" }, "Latissimus", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("fa4b8b08-f7ad-59f3-b0a1-c789f19be41f"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Rücken am Polster, tief beugen und über die ganze Fußsohle hochdrücken.", "Maschine", "strength", false, "Beine", "Hackenschmidt-Kniebeugen (Maschine)", null, null, new[] { "quads" }, new[] { "glutes" }, "Quadrizeps", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null },
                { new Guid("fef86868-838e-58c6-a86e-bf594af3611c"), null, "2026.10.3", new DateTime(2026, 8, 18, 0, 0, 0, 0, DateTimeKind.Utc), "Arme leicht gebeugt in einem Bogen seitlich absenken, bis die Brust gedehnt ist, und zurückführen.", "Kurzhantel", "strength", false, "Brust", "Fliegende (Kurzhantel)", null, null, new[] { "chest" }, new[] { "frontDelts" }, "Brust", new DateTime(2026, 10, 17, 0, 0, 0, 0, DateTimeKind.Utc), 1L, null }
            });

        migrationBuilder.InsertData(
            schema: "training",
            table: "exercise_category_assignments",
            columns: new[] { "CategoryId", "ExerciseId" },
            values: new object[,]
            {
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("03080ed4-c8ff-564a-b2cd-76abbd85543e") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("05243d54-7f56-59b6-a901-76abb7272c44") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("05243d54-7f56-59b6-a901-76abb7272c44") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("086f9bcf-5f98-5a17-b2a4-a90ac5636c5f") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("0bd909a0-6d57-5b36-bebe-38a3461356bb") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("0e371e65-35fe-5bbe-b5f4-b926844b57ef") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("0f45fbc5-d727-586d-b1b2-b035750eb14a") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("10e59c06-7d69-5c46-82e1-6ccc7abc94d4") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("12db891f-8392-5c1c-a58c-8c7ec6a7f524") },
                { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("1e1bfeca-1578-5879-b3b3-1e605d2d2ef2") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("2275dcf2-eea6-5e3c-aab9-2dcbe8921f12") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("229a8cc8-c04f-56c5-a2f3-6553b8e8d7e3") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("236f46fc-a6a9-58c0-835a-6fe98a944ec4") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("25af3a6e-1c74-5047-96c3-00d852283daa") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("25af3a6e-1c74-5047-96c3-00d852283daa") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("29cc1745-868d-5339-9c2f-38b8efa2cfaa") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("2affd637-a6a2-577f-809a-11bd7162ca66") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("2d3197eb-0518-5851-b49e-b8f81a60665e") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("2e855905-c74d-5971-96ff-1dadfc819714") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("39c2b212-ad72-55f0-b6e4-030c369508cd") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("44c0cd21-56dd-5f2f-bf59-35bc94f3e063") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("44d234a4-34e6-5b2d-95eb-a71bff470668") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("45659e6e-0a11-5297-b807-50efe2f621ba") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("4abccd2a-994c-5e49-afc0-9c953554a51e") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("53bb5413-c0c8-5031-b63e-f7cd672f328e") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") },
                { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f259881-118c-52cc-980c-5405130adc79") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f8e9f25-aa1a-5fc7-b9c3-f7774df7373a") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("60ffef06-d690-5441-917d-7ae3d7f09a9c") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("641a2f34-5596-5101-9cd9-19c7c471fb10") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("65c2005c-8285-5963-978e-e3fbb5cb5105") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("6bca7c42-b716-5990-bd5a-a364ac0ccb93") },
                { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("6effd19e-2690-55e4-8f7a-9000525295b4") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("74a1130e-6980-52f1-8381-aba08116edf2") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("74cac498-ac7c-5ec7-ae15-cedbaaa349a8") },
                { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("77fa1c52-ae8a-5dee-81bf-6ee8730e5a6b") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("7c4c128e-d0d5-5ed5-85f3-4eb927e51ca1") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("7e364c6d-572f-5b03-a4c1-b962b8c84138") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("8a0227e3-674f-5423-9c80-a2a489fb0296") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("8cd645c2-6cad-54e9-adc7-96b85efbbbea") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("9226da76-685c-5f7d-9401-656478d870c1") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("94d5b795-73fc-5442-bef7-3e862e49fd38") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("986c4b0b-a86e-5a91-88bd-31c12295de92") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("989e913f-217a-5888-a862-99534b7fc991") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("989e913f-217a-5888-a862-99534b7fc991") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("9f814341-7b1e-5432-8829-f614d124e1c9") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("a58cd97f-0716-5e81-8f90-1e04fb8bbc8f") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("a83bab61-2249-5820-921d-772b161cd3c6") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("aa3a48cb-b062-5c1f-9897-98d942edbc7d") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("ad879102-4b1e-50b6-882a-d3dcf69d1d7c") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("bab9f487-2071-5e56-a7b6-14b0e3f3feda") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("bc15eeae-3bb8-57d8-b24c-12e57c1532f6") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("c4731fdc-153b-5430-baf7-9ce7d0492ff1") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("c5c78e54-fa76-5877-8f32-a792e08ff84c") },
                { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a") },
                { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("d2a89607-77c8-544a-bb53-b7475fa50000") },
                { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("d426fa1e-541f-5549-8478-8f8bbc5fe055") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("d77c1429-d22e-531e-aa71-5fe353742448") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("d89adbcc-66d4-5679-9eea-df9f7f612ddf") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("d93ac4fe-bc50-5a04-adbc-3ce7284d25c8") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("dabb98cb-24ec-5323-bb22-ee5832da9aa2") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("dd9d3216-abc9-5567-9915-5e0b465b1add") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e12aacd1-5a12-53fe-9e2a-703c0225fb2b") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e218ff8a-a6d2-541d-babe-3b6fff7715d5") },
                { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21") },
                { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e541f4f6-04fb-57d9-92b7-56a2f6ba7a1b") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("e57a1210-e482-5bca-9a45-f8cddd6474e3") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f0557f25-9c72-5c55-9e4e-b14bf71cf669") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f061fbb1-0ccb-549c-be30-9ef995a1aebf") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("f4057df2-d82e-5aff-a826-9428a7ffcdd2") },
                { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("f4bdfb0d-3874-5979-a5b4-b36db09facf1") },
                { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") },
                { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f6a0e7a5-efdb-532c-9c7e-77754dfb329f") },
                { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee") },
                { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("f7939d2f-d3d2-5636-9c97-07512964e64a") },
                { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("fa4b8b08-f7ad-59f3-b0a1-c789f19be41f") },
                { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("fef86868-838e-58c6-a86e-bf594af3611c") }
            });
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("03080ed4-c8ff-564a-b2cd-76abbd85543e") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("05243d54-7f56-59b6-a901-76abb7272c44") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("05243d54-7f56-59b6-a901-76abb7272c44") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("086f9bcf-5f98-5a17-b2a4-a90ac5636c5f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("0bd909a0-6d57-5b36-bebe-38a3461356bb") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("0e371e65-35fe-5bbe-b5f4-b926844b57ef") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("0f45fbc5-d727-586d-b1b2-b035750eb14a") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("10e59c06-7d69-5c46-82e1-6ccc7abc94d4") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("12db891f-8392-5c1c-a58c-8c7ec6a7f524") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("1e1bfeca-1578-5879-b3b3-1e605d2d2ef2") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("2275dcf2-eea6-5e3c-aab9-2dcbe8921f12") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("229a8cc8-c04f-56c5-a2f3-6553b8e8d7e3") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("236f46fc-a6a9-58c0-835a-6fe98a944ec4") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("25af3a6e-1c74-5047-96c3-00d852283daa") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("25af3a6e-1c74-5047-96c3-00d852283daa") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("29cc1745-868d-5339-9c2f-38b8efa2cfaa") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("2affd637-a6a2-577f-809a-11bd7162ca66") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("2d3197eb-0518-5851-b49e-b8f81a60665e") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("2e855905-c74d-5971-96ff-1dadfc819714") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("39c2b212-ad72-55f0-b6e4-030c369508cd") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("44c0cd21-56dd-5f2f-bf59-35bc94f3e063") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("44d234a4-34e6-5b2d-95eb-a71bff470668") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("45659e6e-0a11-5297-b807-50efe2f621ba") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("4abccd2a-994c-5e49-afc0-9c953554a51e") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("53bb5413-c0c8-5031-b63e-f7cd672f328e") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("54522c07-9525-59f5-abea-c989f0abfe92") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f259881-118c-52cc-980c-5405130adc79") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("5f8e9f25-aa1a-5fc7-b9c3-f7774df7373a") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("60ffef06-d690-5441-917d-7ae3d7f09a9c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("641a2f34-5596-5101-9cd9-19c7c471fb10") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("65c2005c-8285-5963-978e-e3fbb5cb5105") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("6bca7c42-b716-5990-bd5a-a364ac0ccb93") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("6effd19e-2690-55e4-8f7a-9000525295b4") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("74a1130e-6980-52f1-8381-aba08116edf2") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("74cac498-ac7c-5ec7-ae15-cedbaaa349a8") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("396b4f80-26de-4c59-aff0-b7eb6d938e4f"), new Guid("77fa1c52-ae8a-5dee-81bf-6ee8730e5a6b") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("7c4c128e-d0d5-5ed5-85f3-4eb927e51ca1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("7e364c6d-572f-5b03-a4c1-b962b8c84138") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("8a0227e3-674f-5423-9c80-a2a489fb0296") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("8cd645c2-6cad-54e9-adc7-96b85efbbbea") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("9226da76-685c-5f7d-9401-656478d870c1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("94d5b795-73fc-5442-bef7-3e862e49fd38") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("986c4b0b-a86e-5a91-88bd-31c12295de92") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("989e913f-217a-5888-a862-99534b7fc991") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("989e913f-217a-5888-a862-99534b7fc991") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("9f814341-7b1e-5432-8829-f614d124e1c9") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("a58cd97f-0716-5e81-8f90-1e04fb8bbc8f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("a83bab61-2249-5820-921d-772b161cd3c6") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("aa3a48cb-b062-5c1f-9897-98d942edbc7d") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("ad879102-4b1e-50b6-882a-d3dcf69d1d7c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("bab9f487-2071-5e56-a7b6-14b0e3f3feda") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("bc15eeae-3bb8-57d8-b24c-12e57c1532f6") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("c4731fdc-153b-5430-baf7-9ce7d0492ff1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("c5c78e54-fa76-5877-8f32-a792e08ff84c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("d2a89607-77c8-544a-bb53-b7475fa50000") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"), new Guid("d426fa1e-541f-5549-8478-8f8bbc5fe055") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("d77c1429-d22e-531e-aa71-5fe353742448") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("d89adbcc-66d4-5679-9eea-df9f7f612ddf") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("d93ac4fe-bc50-5a04-adbc-3ce7284d25c8") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("dabb98cb-24ec-5323-bb22-ee5832da9aa2") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("dd9d3216-abc9-5567-9915-5e0b465b1add") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e12aacd1-5a12-53fe-9e2a-703c0225fb2b") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e218ff8a-a6d2-541d-babe-3b6fff7715d5") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("74d2162c-349e-4845-b808-da9339b9d497"), new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("d1e68f73-aa3b-4950-996b-1cc0d2076868"), new Guid("e541f4f6-04fb-57d9-92b7-56a2f6ba7a1b") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("e57a1210-e482-5bca-9a45-f8cddd6474e3") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("efcfc194-539c-59d2-be2b-67a011d37082") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f0557f25-9c72-5c55-9e4e-b14bf71cf669") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f061fbb1-0ccb-549c-be30-9ef995a1aebf") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("f4057df2-d82e-5aff-a826-9428a7ffcdd2") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("9a77eeda-816d-41c1-be71-b911d8055e67"), new Guid("f4bdfb0d-3874-5979-a5b4-b36db09facf1") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("2a147135-db68-4768-84b1-e10f270fc7a5"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("875b1842-01c7-476a-8b7f-ca9637ad4cd8"), new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f6a0e7a5-efdb-532c-9c7e-77754dfb329f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("5bd0bcb1-25d6-4d9d-b132-4c202f126418"), new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("092c9ade-1948-412b-927c-7daea71fb381"), new Guid("f7939d2f-d3d2-5636-9c97-07512964e64a") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("6272a453-0cdc-4bae-90db-e299fca34817"), new Guid("fa4b8b08-f7ad-59f3-b0a1-c789f19be41f") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_category_assignments",
            keyColumns: new[] { "CategoryId", "ExerciseId" },
            keyValues: new object[] { new Guid("a0bc5a82-56ad-4ce4-96ab-968a253c21d2"), new Guid("fef86868-838e-58c6-a86e-bf594af3611c") });

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercise_categories",
            keyColumn: "Id",
            keyValue: new Guid("6dbe2f85-1e9d-5728-815a-4cf5e97055b1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("03080ed4-c8ff-564a-b2cd-76abbd85543e"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("05243d54-7f56-59b6-a901-76abb7272c44"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("086f9bcf-5f98-5a17-b2a4-a90ac5636c5f"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0bd909a0-6d57-5b36-bebe-38a3461356bb"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0e371e65-35fe-5bbe-b5f4-b926844b57ef"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("0f45fbc5-d727-586d-b1b2-b035750eb14a"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("10e59c06-7d69-5c46-82e1-6ccc7abc94d4"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("124e12b4-9377-5c00-89d5-e2f3ad4affe0"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("12db891f-8392-5c1c-a58c-8c7ec6a7f524"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("1e1bfeca-1578-5879-b3b3-1e605d2d2ef2"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2275dcf2-eea6-5e3c-aab9-2dcbe8921f12"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("229a8cc8-c04f-56c5-a2f3-6553b8e8d7e3"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("236f46fc-a6a9-58c0-835a-6fe98a944ec4"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("25af3a6e-1c74-5047-96c3-00d852283daa"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("29cc1745-868d-5339-9c2f-38b8efa2cfaa"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2affd637-a6a2-577f-809a-11bd7162ca66"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2d3197eb-0518-5851-b49e-b8f81a60665e"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2e855905-c74d-5971-96ff-1dadfc819714"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("39c2b212-ad72-55f0-b6e4-030c369508cd"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("3aca6eb8-0d2b-564c-80db-e1a67d0917f1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("44c0cd21-56dd-5f2f-bf59-35bc94f3e063"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("44d234a4-34e6-5b2d-95eb-a71bff470668"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("45659e6e-0a11-5297-b807-50efe2f621ba"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("45da1d33-f437-5704-a7c9-0c171ee6f569"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4abccd2a-994c-5e49-afc0-9c953554a51e"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("53bb5413-c0c8-5031-b63e-f7cd672f328e"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("54522c07-9525-59f5-abea-c989f0abfe92"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("5f1f95c5-724c-5ff5-9778-a0d901138e25"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("5f259881-118c-52cc-980c-5405130adc79"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("5f8e9f25-aa1a-5fc7-b9c3-f7774df7373a"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("60ffef06-d690-5441-917d-7ae3d7f09a9c"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("641a2f34-5596-5101-9cd9-19c7c471fb10"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("65c2005c-8285-5963-978e-e3fbb5cb5105"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b4d2b-8bdb-5c11-9cc0-a8205ed0fdfb"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("6ac80f9a-8219-5f58-91e1-005c93c419b7"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("6bca7c42-b716-5990-bd5a-a364ac0ccb93"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("6effd19e-2690-55e4-8f7a-9000525295b4"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("70a2ddbc-6995-5679-9ea3-25132a51e778"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("74a1130e-6980-52f1-8381-aba08116edf2"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("74cac498-ac7c-5ec7-ae15-cedbaaa349a8"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("77fa1c52-ae8a-5dee-81bf-6ee8730e5a6b"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("7c4c128e-d0d5-5ed5-85f3-4eb927e51ca1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("7cfea19e-86df-5075-a090-9a6463ec7b19"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("7e364c6d-572f-5b03-a4c1-b962b8c84138"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("8a0227e3-674f-5423-9c80-a2a489fb0296"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("8cd645c2-6cad-54e9-adc7-96b85efbbbea"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9226da76-685c-5f7d-9401-656478d870c1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("94d5b795-73fc-5442-bef7-3e862e49fd38"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("986c4b0b-a86e-5a91-88bd-31c12295de92"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("989e913f-217a-5888-a862-99534b7fc991"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9f814341-7b1e-5432-8829-f614d124e1c9"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9fa92a8b-4100-5091-83d7-263f0b8d8c7c"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("a58cd97f-0716-5e81-8f90-1e04fb8bbc8f"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("a83bab61-2249-5820-921d-772b161cd3c6"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("aa3a48cb-b062-5c1f-9897-98d942edbc7d"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("ad879102-4b1e-50b6-882a-d3dcf69d1d7c"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b15c581a-cc26-517a-b30c-1c5ca6a896fa"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("bab9f487-2071-5e56-a7b6-14b0e3f3feda"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("bc15eeae-3bb8-57d8-b24c-12e57c1532f6"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c4731fdc-153b-5430-baf7-9ce7d0492ff1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c5c78e54-fa76-5877-8f32-a792e08ff84c"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6246a04-69af-5895-8cc6-1380ebbe4e6a"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c67400a6-ca5b-5e56-b067-411c73b5864d"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("cdcf9968-ebe5-5dd9-880b-6ef2170dab9f"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("cffa8d75-7e82-5e0d-aa44-86e586eff8d7"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("d2a89607-77c8-544a-bb53-b7475fa50000"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("d426fa1e-541f-5549-8478-8f8bbc5fe055"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("d77c1429-d22e-531e-aa71-5fe353742448"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("d89adbcc-66d4-5679-9eea-df9f7f612ddf"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("d93ac4fe-bc50-5a04-adbc-3ce7284d25c8"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("dabb98cb-24ec-5323-bb22-ee5832da9aa2"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("dd9d3216-abc9-5567-9915-5e0b465b1add"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("e12aacd1-5a12-53fe-9e2a-703c0225fb2b"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("e218ff8a-a6d2-541d-babe-3b6fff7715d5"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("e3a5fafb-04dc-5aa1-bd08-c2e0dc432f21"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("e541f4f6-04fb-57d9-92b7-56a2f6ba7a1b"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("e57a1210-e482-5bca-9a45-f8cddd6474e3"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("ee3ed3aa-e22f-56e3-b307-2f8b824fc78b"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("efcfc194-539c-59d2-be2b-67a011d37082"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f0557f25-9c72-5c55-9e4e-b14bf71cf669"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f061fbb1-0ccb-549c-be30-9ef995a1aebf"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f4057df2-d82e-5aff-a826-9428a7ffcdd2"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f4bdfb0d-3874-5979-a5b4-b36db09facf1"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f5a3b22d-e4e8-5252-b19a-f80b22c48929"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f6a0e7a5-efdb-532c-9c7e-77754dfb329f"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f7859df9-614c-5a43-8d34-c6b87f7f30ee"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("f7939d2f-d3d2-5636-9c97-07512964e64a"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("fa4b8b08-f7ad-59f3-b0a1-c789f19be41f"));

        migrationBuilder.DeleteData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("fef86868-838e-58c6-a86e-bf594af3611c"));

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
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Barbell", "Chest", "Barbell Bench Press", "Pectoralis major" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("07859f08-0fa6-5da4-882f-f5db0a7c310d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Barbell", "Legs", "Back Squat", "Quadriceps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("173d2d47-c8a1-5967-8f5b-88de90a30659"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Barbell", "Legs", "Romanian Deadlift", "Hamstrings" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("28d6db67-f2d0-5e15-a63b-759fc96e01cb"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Cable", "Back", "Lat Pulldown", "Latissimus dorsi" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Bodyweight", "Chest", "Push-Up", "Pectoralis major" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("42ce4803-05e3-5f07-92b6-326c9aa95658"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Bodyweight", "Back", "Pull-Up", "Latissimus dorsi" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Cable", "Back", "Seated Cable Row", "Rhomboids" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("66f8d486-cedf-54ee-8154-6b295371d2f7"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Dumbbell", "Shoulders", "Dumbbell Lateral Raise", "Lateral deltoid" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("679b0f26-ac2b-4dc8-bb45-4121b2d3b8e6"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "PrimaryMuscles", "SecondaryMuscles", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Bodyweight", "Arms", new[] { "triceps" }, new[] { "chest", "frontDelts" }, "Triceps brachii" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("71f9157f-2cec-5517-a910-a3a8c6d82f07"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Barbell", "Shoulders", "Standing Overhead Press", "Anterior deltoid" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("85c4145d-e045-5153-a18a-1934d16ad4de"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Machine", "Legs", "Leg Curl", "Hamstrings" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("9a23aa0d-a43b-5d10-a25e-b22db398578e"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Machine", "Legs", "Leg Extension", "Quadriceps" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Dumbbell", "Arms", "Dumbbell Biceps Curl", "Biceps brachii" });

        migrationBuilder.UpdateData(
            schema: "training",
            table: "exercises",
            keyColumn: "Id",
            keyValue: new Guid("c6fb4053-2f69-597f-890e-e7bd58444a3e"),
            columns: new[] { "CatalogVersion", "Description", "Equipment", "MuscleGroup", "Name", "TargetMuscle" },
            values: new object[] { "2026.10.2", null, "Cable", "Arms", "Cable Triceps Pushdown", "Triceps brachii" });
    }
}
