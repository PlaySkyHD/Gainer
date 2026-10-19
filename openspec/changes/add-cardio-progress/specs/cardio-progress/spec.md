# cardio-progress

## ADDED Requirements

### Requirement: Wochenstatistik Cardio

Das Statistik-Segment SHALL je Woche (Montag–Sonntag, lokal) die Minuten im Zielbereich, die Zahl der Einheiten und die Gesamtdauer der letzten 8 Wochen zeigen, zusammen mit einem einstellbaren Wochenziel (Standard 150 min).

#### Scenario: Laufende Woche
- **GIVEN** in dieser Woche drei Einheiten mit 30, 35 und 30 min im Zielbereich und einer Gesamtdauer von 1:42 h
- **WHEN** der Nutzer die Statistik öffnet
- **THEN** steht dort „Diese Woche 95 / 150 min · 3 Einheiten · 1:42 h“

#### Scenario: Keine Cardio-Einheiten
- **GIVEN** keine Cardio-Einheit in den letzten 8 Wochen
- **WHEN** der Nutzer die Statistik öffnet
- **THEN** zeigt der Cardio-Bereich einen Hinweis zum Starten statt leerer Balken

### Requirement: Aerobe Form

Die App SHALL für Einheiten mit Ø-Leistung und Ø-Puls den Effizienzfaktor (Leistung ÷ Puls) als Verlauf zeigen und für die häufigste Leistungsstufe ab 3 Einheiten den ersten und letzten Ø-Puls vergleichen.

#### Scenario: Gleiche Leistung, niedrigerer Puls
- **GIVEN** vier Einheiten mit 148, 152, 150 und 151 W und Ø-Puls 138, 136, 133, 131
- **WHEN** die Statistik berechnet wird
- **THEN** steht dort „bei 150 W: 138 → 131 bpm“

#### Scenario: Ohne Leistung
- **GIVEN** keine Einheit mit Ø-Leistung
- **WHEN** der Nutzer die Statistik öffnet
- **THEN** erscheint der Hinweis, die Ø-Leistung einzutragen, und kein Diagramm

### Requirement: Erholungspuls

Nach dem Beenden einer Einheit mit Pulssignal SHALL die App 60 s weiter messen und den Pulsabfall speichern. Die Dauer der Einheit MUST beim Beenden enden. Die Erholung MUST überspringbar sein.

#### Scenario: Erholung gemessen
- **GIVEN** Ø-Puls 152 in den letzten 10 s vor dem Beenden
- **WHEN** der Puls 60 s später bei 124 liegt
- **THEN** zeigt die Detailansicht „Erholung −28 bpm in 1 min“

#### Scenario: Übersprungen
- **GIVEN** die Erholungsanzeige läuft
- **WHEN** der Nutzer „Überspringen“ tippt
- **THEN** ist die Einheit ohne Erholungswerte gespeichert

### Requirement: HRV-Messung in Ruhe

Der Nutzer SHALL mit verbundenem Gurt eine geführte Ruhemessung (Standard 2 min nach 30 s Einschwingen) durchführen können. Ruhepuls (Median) und RMSSD MUST im Check-in des Tages gespeichert werden. Bei mehr als 20 % verworfenen RR-Werten MUST die App vor dem Speichern nachfragen.

#### Scenario: Messung speichern
- **GIVEN** ein verbundener Gurt
- **WHEN** der Nutzer eine 2-Minuten-Messung abschließt
- **THEN** enthält der heutige Check-in Ruhepuls und HRV, und der Verlauf zeigt den neuen Punkt

#### Scenario: Ohne Gurt
- **GIVEN** kein verbundener Gurt
- **WHEN** der Nutzer „HRV-Messung“ öffnet
- **THEN** ist „Messung starten“ deaktiviert und die App erklärt, dass ein Gurt nötig ist

#### Scenario: Unruhige Messung
- **GIVEN** 25 % der RR-Werte wurden verworfen
- **WHEN** die Messung endet
- **THEN** fragt die App „Messung unruhig – wiederholen?“

#### Scenario: Ruhepuls für Zonen
- **GIVEN** sieben Messungen mit Ruhepuls-Median 58
- **WHEN** der Nutzer „Als Ruhepuls übernehmen“ tippt
- **THEN** rechnen die Zonen mit Ruhepuls 58 (Karvonen)

### Requirement: Rückwärtskompatibler Vertrag

Die neuen Felder SHALL optional sein. Das Backend MUST Werte außerhalb der Grenzen mit `validation_failed` ablehnen und Einheiten bzw. Check-ins ohne die Felder unverändert akzeptieren.

#### Scenario: Alte App
- **GIVEN** eine App-Version ohne Erholungsfelder
- **WHEN** sie eine Cardio-Einheit speichert
- **THEN** speichert der Server sie mit leeren Erholungswerten
