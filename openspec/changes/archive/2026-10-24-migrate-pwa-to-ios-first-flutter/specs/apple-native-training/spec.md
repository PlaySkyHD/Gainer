## Purpose

Diese Capability erweitert die iPhone-Kernreise um native Erfassung, zeitbasierte Trainingshilfe und kontrollierte Einstiege über Apple-Systemoberflächen.

> **Teilweise abgelöst:** Die Requirements „Pausentimer und lokale Benachrichtigungen“ und „Live Activity für Workout und Pause“ werden durch die Capabilities `rest-timer` und `training-screens` der Change `rebuild-training-logging` ersetzt und beim Archivieren nicht übernommen.

## ADDED Requirements

### Requirement: Native Kamera und Fotoauswahl

Die App MUST nutzerinitiierte Kamera-/Barcode-Erfassung und systemeigene Fotoauswahl anbieten, Berechtigungen bedarfsgerecht anfordern und manuelle Eingabe bei Ablehnung erlauben. Label-/AI-Bildverarbeitung MUST die bestehenden Online-, Einwilligungs-, Format-/Größen- und Review-Regeln erhalten. Bilder DÜRFEN nicht in die Offline-Outbox oder normale Telemetrie gelangen.

#### Scenario: Kamera abgelehnt oder geschlossen
- **GIVEN** ein Lebensmittelentwurf ohne bestätigte Mutation
- **WHEN** Kamera-Zugriff abgelehnt oder Fotoauswahl abgebrochen wird
- **THEN** bleibt der Entwurf unverändert, manuelle Erfassung bleibt möglich und keine Bildübertragung erfolgt

#### Scenario: Scan überprüfen
- **GIVEN** ein unterstütztes Foto und aktive Sitzung mit Internet
- **WHEN** der Nutzer den Scan erlaubt und ein Ergebnis erhält
- **THEN** muss er Bezugsgröße und Werte prüfen und bestätigen, bevor ein lokaler Ernährungseintrag samt Outbox entsteht

### Requirement: Pausentimer und lokale Benachrichtigungen

Die App MUST Timer-Zielzeit dauerhaft speichern, bei Wiederaufnahme korrekt fortrechnen und auf Nutzerwunsch eine lokale Benachrichtigung planen. Änderung, Abbruch, Workout-Ende und Kontowechsel MUST zugehörige Benachrichtigungen ersetzen oder entfernen. Fehlende Berechtigung DARF das Training nicht blockieren. Zustellung durch das Betriebssystem ist keine Garantie; die App MUST den tatsächlichen Timerstand nach Wiederaufnahme zeigen.

#### Scenario: Timer läuft während Suspend weiter
- **GIVEN** ein gespeicherter Pausentimer und erlaubte Benachrichtigungen
- **WHEN** die App suspendiert wird und später zurückkehrt
- **THEN** zeigt sie den aus der Zielzeit abgeleiteten Rest statt eines angehaltenen UI-Ticks und erzeugt keine doppelte Benachrichtigung

#### Scenario: Timer abbrechen
- **GIVEN** eine geplante Pausenbenachrichtigung
- **WHEN** Timer, Workout oder Konto beendet beziehungsweise gewechselt wird
- **THEN** wird die zugehörige ausstehende Benachrichtigung entfernt und das Speichern des Workouts bleibt unabhängig davon möglich

### Requirement: Live Activity für Workout und Pause

Die App MUST auf unterstützten iPhones eine freiwillig gestartete Live Activity für laufendes Workout und Pausentimer anbieten. Sie MUST Zeitstände ohne permanenten App-Hintergrundprozess darstellen, bei in der App ausgeführtem Workout-Ende/Ausloggen/Kontowechsel beendet werden und bei Wiederaufnahme veraltete Activities bereinigen. Bei Prozessende MUST eine begrenzte Gültigkeit veraltete Anzeige als überholt kennzeichnen; eine sofortige Aktualisierung ohne App-Ausführung DARF nicht zugesagt werden. Ohne Freigabe DÜRFEN keine Übungsnamen, Gewichte, Wiederholungen, Körper- oder Ernährungsdaten auf dem Sperrbildschirm erscheinen. Deaktivierte oder nicht verfügbare Live Activities MUST durch den In-App-Timer ersetzt werden.

#### Scenario: Sperrbildschirm im Standardmodus
- **GIVEN** eine aktive Live Activity ohne Freigabe detaillierter Anzeige
- **WHEN** das iPhone gesperrt wird
- **THEN** sind nur allgemeiner Trainings-/Pausenstatus und Zeit sichtbar, keine persönlichen Trainingswerte oder Kontodaten

#### Scenario: System beendet Activity
- **GIVEN** ein lokal gespeichertes laufendes Workout
- **WHEN** das System dessen Live Activity beendet
- **THEN** bleibt das Workout erhalten und die App zeigt bei Wiederaufnahme den korrekten Status ohne automatische doppelte Activity

### Requirement: Widget und Shortcuts als kontrollierte Einstiege

Die App MUST ein Home-Screen-Widget für „Training öffnen“ und „Check-in öffnen“ und Shortcuts für „Training öffnen“, „Check-in öffnen“ und „Ernährung öffnen“ bereitstellen. Systemoberflächen DÜRFEN weder Passwörter/Sitzungstoken noch komplette Fitnessdaten speichern und keine fachliche Mutation ohne In-App-Bestätigung ausführen. Veraltete, abgemeldete oder kontoübergreifende Einstiege MUST sicher in den aktuellen Zugangspfad führen.

#### Scenario: Widget nach Kontowechsel
- **GIVEN** ein Widget wurde unter Konto A eingerichtet
- **WHEN** Konto B aktiv wird und das Widget geöffnet wird
- **THEN** werden keine A-Daten angezeigt und der Einstieg löst keine Aktion für A aus

#### Scenario: Shortcut ohne aktive Sitzung
- **GIVEN** ein Shortcut und keine gültige Sitzung
- **WHEN** der Nutzer den Shortcut ausführt
- **THEN** öffnet sich die App mit dem passenden Zugangspfad und führt keine versteckte Mutation aus
