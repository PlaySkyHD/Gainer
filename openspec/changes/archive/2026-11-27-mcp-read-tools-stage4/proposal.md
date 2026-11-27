# Proposal

## Why

Der Nutzer möchte über ChatGPT alles abfragen können, was er in der App sieht. Nach Stufe 3 fehlt dem MCP-Server die Vorschau des Trainingsrhythmus, die nur die App rechnet (`TrainingScheduleProjection` in `training_schedule.dart`). Sie steuert die Karte „Heute“, den Status jedes Tages (erledigt, verpasst, geplant, Ruhetag), die Markierungen im Kalender, die Liste „Nächste 14 Tage“ und die Wahl zwischen Trainings- und Ruhetag-Ziel der Ernährung. Bisher nutzte der Server an Tagen ohne festgelegte Tagesart immer das Trainingstag-Ziel und wich damit von der App ab.

## What Changes

- Port `TrainingScheduleProjection` in `Gainer.Core/Training` (rein, lokale Tage Europe/Berlin): Slot je Tag für Zyklus (Anker, Verschiebungen, pausierte Tage, Modulo vor dem Anker) und feste Tage, archivierte oder unbekannte Pläne als Ruhetag, Ausnahmen (verschieben, überspringen, nur wirksam solange der Plan an ihrem Tag noch vorgesehen ist), Status je Training, nächstes offenes Training, heutiger Zyklus-Slot und die automatische Tagesart (`automaticDayKind` aus `day_target.dart`).
- Neue Core-Abfrage `ITrainingScheduleQueries` mit `TrainingScheduleQueries` in `Gainer.Infrastructure` (Rhythmus, Pläne und beendete Trainings eines Zeitraums in einer RepeatableRead-Transaktion).
- Neue lesende Tools `get_training_schedule(from, days)` (Standard heute und 14 Folgetage, höchstens 62 Tage, Vergangenheit erlaubt) und `get_training_today()` (Karte „Heute“ mit nächstem offenen Training).
- `get_nutrition_days` liefert je Tag die automatische Tagesart und das geltende Ziel (`AppliedTarget`); `get_nutrition_averages` wählt das Ruhetag-Ziel wie die App über die automatische Tagesart.
- Gemeinsame Fixture `contracts/fixtures/training-schedule.json` mit Dart- und C#-Test.

## Grenzen

- Die Tagesaktionen (`actionsFor`, verschieben, nachholen) sind schreibend und nicht Teil des lesenden Servers.
- Die App rechnet lokale Tage in der Zeitzone des Geräts, der Server in Europe/Berlin wie alle anderen Tools.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `ai-connector`: Anforderung „Lesende Tools“ nennt den Trainingsrhythmus und erhält Szenarien für die neuen Tools und das Ziel eines Ernährungstags.
- `training-statistics`: „Gleiche Kennzahlen in App und Server“ umfasst die Rhythmus-Vorschau mit automatischer Tagesart; der Server leitet die Tagesart nun wie die App ab.

## Impact

`Gainer.Core` (`TrainingScheduleProjection`, `ITrainingScheduleQueries`, `NutritionAverages` mit automatischer Tagesart), `Gainer.Infrastructure/Persistence` (`TrainingScheduleQueries`, Registrierung), `Gainer.Api/Mcp` (neue Klasse `GainerScheduleTools`, erweitert `GainerNutritionTools`), `GainerConnectorExtensions`, Tests in `Gainer.UnitTests`, `Gainer.IntegrationTests` und `apps/mobile/test`. Keine Migration, kein Sync, keine HTTP-Verträge, keine Änderung am App-Code.
