## Purpose

Diese Capability definiert überprüfbare Freigabebedingungen für die private iOS-App und eine davon getrennte, spätere Android-Ausbaustufe.

## ADDED Requirements

### Requirement: Unabhängige Prüfung vor iOS-Freigabe

Die iOS-App MUST mit einer reproduzierbar festgelegten Stable-Toolchain gebaut werden und vor Freigabe erfolgreiche Analyse, relevante Unit-/Widget-/API-Integrationstests, iOS-Build sowie physische iPhone-Prüfungen von Offline/Sync, Kamera, HealthKit und Systemoberflächen nachweisen. Nutzerisolation MUST mit mindestens zwei Testkonten geprüft werden. Fehlende Nachweise DÜRFEN nicht als bestanden markiert werden; HealthKit, Widgets, Live Activities und Shortcuts sind Bestandteil des ersten iOS-Releases, nicht optionaler Implementierungsscope.

#### Scenario: Windows-Checks sind grün
- **GIVEN** Dart- und Backend-Prüfungen sind auf Windows erfolgreich
- **WHEN** die iOS-Freigabe bewertet wird
- **THEN** bleibt diese bis zum macOS/Xcode-Build und erforderlichen physischen iPhone-Nachweisen offen

### Requirement: Private Beta und sichere Rückkehr

Die Freigabe MUST einen privaten Beta-Verteilungsweg, Berechtigungs-/Datenschutzhinweise, eine dokumentierte Übergabe-/Recovery-Anleitung und einen geprüften Rückwechsel bereitstellen. Veröffentlichung und externe Uploads MUST als gesonderte operative Aktionen behandelt werden. Die PWA DARF erst nach erfolgreicher Übergabe aller betroffenen Nutzer und separater Entscheidung stillgelegt werden.

#### Scenario: Beta-Rollback
- **GIVEN** eine iOS-Beta zeigt einen Fehler und native Daten stehen aus
- **WHEN** die Rückkehr zur PWA angefordert wird
- **THEN** bleiben native Daten erhalten und die Anleitung führt über Sync und bestätigte Rückübergabe statt App-Deinstallation

### Requirement: Android nach iOS

Android MUST eine getrennte spätere Phase mit eigener Build-, Geräte-, Berechtigungs- und Offline-Abnahme erhalten. Apple-spezifische Funktionen MUST auf Android als nicht verfügbar oder durch definierte Plattformadapter ersetzt erscheinen; Android-Datenzugriff MUST dieselben Konten- und Sync-Regeln erfüllen.

#### Scenario: iOS bereit und Android offen
- **GIVEN** sämtliche iOS-Kriterien sind erfüllt und Android-Tasks noch offen
- **WHEN** die iOS-Beta bewertet wird
- **THEN** verhindern die getrennt ausgewiesenen Android-Tasks keine iOS-Freigabe und der gesamte Change wird noch nicht als vollständig abgeschlossen archiviert
