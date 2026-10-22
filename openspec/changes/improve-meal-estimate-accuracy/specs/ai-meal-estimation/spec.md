# ai-meal-estimation

## ADDED Requirements

### Requirement: Referenzwerte per Websuche

Die Mahlzeiten-Schätzung SHALL Nährwerte pro 100 g aus Nährwertdatenbanken ansetzen und dafür per Websuche auf einer konfigurierten Liste von Nährwertseiten nachschlagen können. Grundzutaten SHALL als roh gelten, solange keine Zubereitung genannt ist. Eine Quelle MUST nur angezeigt werden, wenn sie ein https-Link auf einer erlaubten Seite ist. Lehnt der Anbieter die Suche ab, SHALL die Schätzung ohne Suche erfolgen statt zu scheitern.

#### Scenario: Hähnchenbrustfilet
- **GIVEN** die Beschreibung „200 g Hähnchenbrustfilet“
- **WHEN** die KI schätzt
- **THEN** liegt das Fett im Bereich roher Hähnchenbrust (etwa 1–2 g pro 100 g), und der Vorschlag zeigt die Quelle, z. B. „fddb.info“

#### Scenario: Fremde Quelle
- **GIVEN** das Modell nennt eine Seite außerhalb der Liste
- **WHEN** der Server die Antwort prüft
- **THEN** entfällt die Quelle, und die Werte bleiben als Vorschlag erhalten

#### Scenario: Suche nicht verfügbar
- **GIVEN** der Anbieter lehnt die Anfrage mit Websuche mit HTTP 400 ab
- **WHEN** die Schätzung läuft
- **THEN** wiederholt der Server sie einmal ohne Suche und liefert einen Vorschlag
