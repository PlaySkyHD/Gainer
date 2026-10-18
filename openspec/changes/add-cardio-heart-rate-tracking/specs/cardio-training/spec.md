# cardio-training

## ADDED Requirements

### Requirement: Cardio-Einheit starten und beenden

Der Nutzer SHALL im Trainings-Tab eine Cardio-Einheit „Rad-Ergometer“ starten können, unabhängig von Trainingsplänen und einem aktiven Krafttraining. Es MUST höchstens eine laufende Cardio-Einheit geben. Beim Beenden MUST die Einheit mit Start, Ende, Zielbereich, Pulsreihe und RR-Intervallen gespeichert werden.

#### Scenario: Einheit nach dem Krafttraining
- **GIVEN** ein aktives Krafttraining „Push“
- **WHEN** der Nutzer „Cardio starten“ wählt und mit Zielbereich 125–140 bpm startet
- **THEN** läuft die Cardio-Einheit, das Krafttraining bleibt aktiv

#### Scenario: Zweite Einheit
- **GIVEN** eine laufende Cardio-Einheit
- **WHEN** der Nutzer erneut „Cardio starten“ wählt
- **THEN** öffnet die App die laufende Einheit statt eine zweite zu starten

#### Scenario: Sehr kurze Einheit
- **GIVEN** eine Einheit, die seit 40 s läuft
- **WHEN** der Nutzer „Beenden“ tippt
- **THEN** fragt die App, ob die Einheit verworfen oder gespeichert werden soll

### Requirement: Pulsgurt verbinden

Die App SHALL Pulsgurte mit dem Bluetooth-Heart-Rate-Service finden, verbinden und den zuletzt genutzten Gurt merken. Nach einem Verbindungsabbruch MUST sie ohne Zutun neu verbinden. Ist Bluetooth aus oder nicht erlaubt, MUST sie den Grund und einen Weg in die Einstellungen zeigen.

#### Scenario: Polar H10 koppeln
- **GIVEN** eine angelegte Polar H10 in Reichweite
- **WHEN** der Nutzer „Gurt suchen“ tippt und „Polar H10 1A2B3C4D“ wählt
- **THEN** zeigt die App den Live-Puls und beim nächsten Start ist dieser Gurt vorausgewählt

#### Scenario: Signal kurz weg
- **GIVEN** eine laufende Einheit mit verbundenem Gurt
- **WHEN** die Verbindung 20 s abbricht und der Gurt wieder sendet
- **THEN** verbindet die App neu, die Pulsreihe enthält für die Lücke 0-Werte und die Einheit läuft weiter

#### Scenario: Bluetooth aus
- **GIVEN** Bluetooth ist ausgeschaltet
- **WHEN** der Nutzer „Gurt suchen“ tippt
- **THEN** erklärt die App, dass Bluetooth aus ist, und startet keine Suche

### Requirement: Zielbereich und Zonenalarm

Der Nutzer SHALL einen Zielbereich von–bis in bpm (40–230, von < bis) vor und während der Einheit festlegen können. Liegt der Puls nach der Aufwärmzeit länger als 15 s außerhalb, MUST eine Benachrichtigung mit Ton erscheinen, auch bei gesperrtem Display. Bleibt der Puls außerhalb, MUST sie sich höchstens alle 60 s wiederholen.

#### Scenario: Zu hoch
- **GIVEN** Zielbereich 125–140, Aufwärmzeit vorbei
- **WHEN** der Puls 16 s lang über 140 liegt
- **THEN** erscheint „Puls zu hoch: 146 bpm (Ziel 125–140)“ mit Ton

#### Scenario: Kurzer Ausreißer
- **GIVEN** Zielbereich 125–140
- **WHEN** der Puls 10 s über 140 liegt und dann wieder bei 135
- **THEN** erscheint keine Benachrichtigung

#### Scenario: Rückkehr
- **GIVEN** ein Alarm „Puls zu niedrig“ wurde gezeigt
- **WHEN** der Puls wieder im Zielbereich liegt
- **THEN** erscheint „Wieder im Zielbereich“ ohne Ton

#### Scenario: Aufwärmen
- **GIVEN** Aufwärmzeit 3 min und Zielbereich 125–140
- **WHEN** der Puls in der zweiten Minute bei 100 liegt
- **THEN** erscheint kein Alarm

#### Scenario: Zielbereich ändern
- **GIVEN** eine laufende Einheit mit 125–140
- **WHEN** der Nutzer den Bereich auf 130–145 ändert
- **THEN** gilt ab sofort 130–145 für Alarm und Anzeige, und die gespeicherte Einheit enthält 130–145

### Requirement: Kennzahlen und HRV

Die App SHALL für jede Einheit Dauer, Ø-Puls, Maximalpuls, Zeit im Zielbereich und HRV (RMSSD) aus den gespeicherten Reihen berechnen. Werte ohne Signal (0) MUST bei Ø, Max und Zone unberücksichtigt bleiben. RMSSD MUST Artefakte nach der festgelegten Regel verwerfen und bei weniger als 30 gültigen Differenzen fehlen.

#### Scenario: Zeit in Zone
- **GIVEN** Intervall 5 s, Zielbereich 120–140, Pulsreihe 118, 125, 0, 141, 130
- **WHEN** die Kennzahlen berechnet werden
- **THEN** ist Ø 128,5 bpm, Max 141 bpm und Zeit im Zielbereich 10 s

#### Scenario: RMSSD mit Artefakt
- **GIVEN** RR-Werte mit einem Einzelwert von 2 400 ms zwischen Werten um 800 ms
- **WHEN** RMSSD berechnet wird
- **THEN** fließen weder der 2 400-ms-Wert noch seine Differenzen ein

### Requirement: Tagebuch und Detail

Cardio-Einheiten SHALL im Trainings-Tagebuch im passenden Monat erscheinen, erkennbar als Cardio und mit Dauer, Ø-Puls und Anteil im Zielbereich. Die Detailansicht MUST die Pulskurve mit Zielband, die Kennzahlen und die manuell änderbaren Werte (Distanz, Ø-Leistung, kcal, Notiz) zeigen. Löschen MUST bestätigt werden.

#### Scenario: Eintrag im Tagebuch
- **GIVEN** eine beendete Einheit vom 18.10. mit 30 min, Ø 132 bpm und 78 % im Zielbereich
- **WHEN** der Nutzer das Tagebuch öffnet
- **THEN** steht im Oktober „Rad-Ergometer · 30 min“ mit „Ø 132 bpm · 78 % in Zone“

#### Scenario: Werte nachtragen
- **GIVEN** eine gespeicherte Einheit
- **WHEN** der Nutzer 14,2 km und 165 W einträgt
- **THEN** zeigt die Detailansicht „Distanz 14,2 km“ und „Ø-Leistung 165 W“ und die Änderung wird synchronisiert

### Requirement: Sync und Nutzerisolation

Cardio-Einheiten SHALL über den bestehenden Sync-Vertrag als Ressource `CardioSession` gespeichert, geändert und gelöscht werden. Das Backend MUST die Einheit an den angemeldeten Nutzer binden, ungültige Werte mit `validation_failed` ablehnen und veraltete Basisversionen mit `stale_base_version` beantworten. Kein Nutzer MUST Einheiten eines anderen Nutzers lesen, ändern oder löschen können.

#### Scenario: Wiederholtes Senden
- **GIVEN** eine gesendete `saveCardioSession`-Mutation, deren Antwort verloren ging
- **WHEN** die App dieselbe Mutation erneut sendet
- **THEN** antwortet der Server mit dem gespeicherten Ergebnis und legt keine zweite Einheit an

#### Scenario: Fremde Einheit
- **GIVEN** Nutzer A besitzt die Einheit X
- **WHEN** Nutzer B `deleteCardioSession` für X sendet
- **THEN** antwortet der Server mit `resource_not_found` und X bleibt erhalten

#### Scenario: Ungültige Pulsreihe
- **GIVEN** eine Pulsreihe mit dem Wert 400
- **WHEN** die App sie sendet
- **THEN** lehnt der Server mit `validation_failed` ab und die Einheit bleibt lokal erhalten und ist als Konflikt sichtbar

#### Scenario: Offline beendet
- **GIVEN** das iPhone ist offline
- **WHEN** der Nutzer eine Einheit beendet
- **THEN** ist sie sofort im Tagebuch sichtbar und wird beim nächsten Sync gesendet
