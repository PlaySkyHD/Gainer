# Tasks

## 1. Backend

- [x] 1.1 `WaterIntakeDay`, Snapshot, Mutationen, Grenzen und Exceptions in Core; `ResourceKind.WaterIntakeDay = 14` (D1, D2, D3).
- [x] 1.2 Konfiguration in `AppDbContext`, Migration `AddWaterTracking`, `DatabaseSchemaVersion.RequiredMigration` (D5).
- [x] 1.3 `WaterIntakeMutationHandler`, Operationen `addWaterIntake` und `setWaterIntake` in `SyncMutationExecutor`, Fehlercodes in `SyncMutationProcessor` (D2, D5).
- [x] 1.4 Integrationstests gegen Postgres: Anlegen, Addieren, Setzen, Grenzen, Versionskonflikt, zweite ID für denselben Tag, zwei Nutzer, Change-Feed-Snapshot und Export.

## 2. App

- [x] 2.1 Sync-Codec, Typzuordnungen, Konfliktanzeige und Zusammenfassen für `water-intake-day` (D6); Tests.
- [x] 2.2 `WaterIntakeRepository` mit Warteschlange, Addieren und Setzen über `LocalSyncStore.commitMutation` (D2); Tests.
- [x] 2.3 `NutritionPreferences` mit Schalter und Tagesziel (D7); Tests.
- [x] 2.4 Wasser-Karte, Korrektur-Sheet und Ernährungs-Einstellungen (D7, D8); Widget-Tests inklusive Textgröße 2 und Goldens hell und dunkel.
