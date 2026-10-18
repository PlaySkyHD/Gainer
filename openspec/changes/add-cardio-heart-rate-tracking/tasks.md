# Tasks

## 1. Backend

- [x] 1.1 `ResourceKind.CardioSession`, Entität, Mutationen, Validierung (D1); Unit-Tests für die Validierung.
- [x] 1.2 EF-Mapping mit `integer[]`-Spalten und Migration `AddCardioSessions`.
- [x] 1.3 `CardioSessionMutationHandler` (Anlegen, Ändern, Löschen), Sync-Executor, Fehlerzuordnung in Processor und Controller (D6).
- [x] 1.4 Integrationstests: Anlegen/Ändern/Löschen, Replay, veraltete Version, Validierung, Isolation mit zwei Nutzern.

## 2. Flutter-Daten

- [ ] 2.1 Domänenmodell `CardioSession`, Entwurf und `CardioAnalysis` (D2); Unit-Tests inkl. RMSSD-Artefakte.
- [ ] 2.2 `CardioRepository` (Entwurf, Beenden, Ändern, Löschen, Liste) und Sync-Codec/Typlisten (D5, D6); Tests.

## 3. iOS

- [ ] 3.1 Pigeon-Erweiterung, `NativeHeartRateMonitor`, Parser und Zonenalarm in Swift (D3, D4); XCTests für Parser und Alarm.
- [ ] 3.2 Info.plist (`bluetooth-central`, Bluetooth-Beschreibung), Eintrag in `project.pbxproj`, Benachrichtigungs-Delegate.

## 4. Oberfläche

- [ ] 4.1 `CardioSessionController` mit Abfrage-Schleife, Verdichtung und Wiederaufnahme (D5); Tests mit Fake-Plattform.
- [ ] 4.2 Start-Sheet, Live-Ansicht, Detail, Tagebuchzeile und Toolbar-Button (D7); Widget- und Golden-Tests, Textgröße 2.

## 5. Abschluss

- [ ] 5.1 `flutter analyze`, `flutter test`, Format, `dotnet build/test`, `openspec validate --strict`.
- [ ] 5.2 TestFlight und Abnahme auf dem iPhone mit Polar H10 (Alarm bei gesperrtem Display, Neuverbinden, Sync).
