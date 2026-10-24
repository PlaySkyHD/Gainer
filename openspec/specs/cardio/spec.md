# cardio Specification

## Purpose
Cardio-Einheiten am Rad-Ergometer mit Bluetooth-Pulsgurt: Zielbereich und Zonenalarm, Intervall-Vorlagen, Sprachansagen, Live Activity, Kennzahlen, HRV, Wochenstatistik und Export nach Apple Health.

## Requirements

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

### Requirement: Live Activity während Cardio

Während einer laufenden Cardio-Einheit SHALL die App eine Live Activity mit Puls, Zonenstatus, Zielbereich und Dauer zeigen, sofern Live Activities erlaubt sind. Sie MUST bei gesperrtem Display aktualisiert werden und mit dem Beenden der Einheit enden.

#### Scenario: Gesperrtes Display
- **GIVEN** eine laufende Einheit mit Zielbereich 125–140 und gesperrtem iPhone
- **WHEN** der Puls von 130 auf 145 steigt
- **THEN** zeigt die Live Activity 145 bpm und „Zu hoch“ in Warnfarbe

#### Scenario: Live Activities aus
- **GIVEN** Live Activities sind in den iOS-Einstellungen aus
- **WHEN** der Nutzer eine Einheit startet
- **THEN** läuft die Einheit mit Alarm normal, ohne Live Activity und ohne Fehlermeldung

#### Scenario: Beenden
- **GIVEN** eine laufende Einheit mit Live Activity
- **WHEN** der Nutzer „Beenden“ tippt
- **THEN** verschwindet die Live Activity

### Requirement: Export nach Apple Health

Der Nutzer SHALL eine beendete Cardio-Einheit nach Apple Health sichern können: als Indoor-Radtraining mit Pulsproben und, falls vorhanden, Distanz und kcal. Ein erneuter Export derselben Version MUST ohne Dublette mit „bereits vorhanden“ enden. Ohne Schreibrecht MUST die App den Grund zeigen.

#### Scenario: Erster Export
- **GIVEN** eine beendete Einheit mit 360 Pulswerten
- **WHEN** der Nutzer „In Apple Health sichern“ tippt und erlaubt
- **THEN** enthält Apple Health ein Indoor-Radtraining mit Pulsproben und die Detailansicht zeigt „In Apple Health gesichert“

#### Scenario: Doppelt tippen
- **GIVEN** eine bereits exportierte Einheit
- **WHEN** der Export erneut läuft
- **THEN** entsteht kein zweites Workout

### Requirement: Zonen-Empfehlung

Hat der Nutzer Maximalpuls oder Alter angegeben, SHALL die App die Zonen 1–5 nach der festgelegten Formel berechnen und als Auswahl beim Festlegen des Zielbereichs anbieten. Ohne diese Angaben MUST die Auswahl fehlen und ein Hinweis auf die Einstellung erscheinen.

#### Scenario: Zone 2 aus Maximalpuls
- **GIVEN** Maximalpuls 190, kein Ruhepuls
- **WHEN** der Nutzer im Start-Sheet „Zone 2“ tippt
- **THEN** ist der Zielbereich 114–133 bpm

#### Scenario: Karvonen
- **GIVEN** Maximalpuls 190 und Ruhepuls 60
- **WHEN** die Zonen berechnet werden
- **THEN** ist Zone 2 = 138–151 bpm

#### Scenario: Alter statt Maximalpuls
- **GIVEN** Alter 30, kein Maximalpuls
- **WHEN** die Zonen berechnet werden
- **THEN** gilt HFmax 187 und Zone 2 = 112–131 bpm

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

### Requirement: Cardio nach dem Krafttraining anbieten

Nach dem Beenden eines aktiven Krafttrainings SHALL die Zusammenfassung „Cardio anhängen“ anbieten, sofern die Einstellung an ist und keine Cardio-Einheit läuft. Ein Tipp auf „Starten“ MUST mit dem gemerkten Gurt und der zuletzt genutzten Vorlage bzw. dem letzten Zielbereich starten.

#### Scenario: Push beendet
- **GIVEN** das Krafttraining „Push“ läuft, zuletzt wurde „Zone 2 – 30 min“ genutzt
- **WHEN** der Nutzer „Push“ beendet und in der Zusammenfassung „Starten“ tippt
- **THEN** läuft eine Cardio-Einheit mit „Zone 2 – 30 min“ und die Live-Ansicht ist offen

#### Scenario: Ausgeschaltet
- **GIVEN** „Cardio nach Krafttraining anbieten“ ist aus
- **WHEN** der Nutzer ein Krafttraining beendet
- **THEN** zeigt die Zusammenfassung keine Cardio-Karte

### Requirement: Intervall-Vorlagen

Der Nutzer SHALL Vorlagen aus Phasen mit Dauer und Zielbereich (Zone oder bpm) wählen, anlegen, ändern und löschen können. Während einer Einheit mit Vorlage MUST der Zielbereich zu Phasenbeginn wechseln, und der Wechsel MUST angekündigt werden, auch bei gesperrtem Display.

#### Scenario: 4×4
- **GIVEN** Maximalpuls 190 und die Vorlage „4×4 (Norwegisch)“
- **WHEN** nach 10 min Aufwärmen die erste Belastungsphase beginnt
- **THEN** gilt Ziel 152–171 bpm und es erscheint „Phase 2/9 · Belastung 4:00 – Ziel 152–171“

#### Scenario: Karenz pro Phase
- **GIVEN** eine Belastungsphase beginnt mit Puls 140 bei Ziel 152–171
- **WHEN** der Puls innerhalb von 15 s auf 155 steigt
- **THEN** erscheint kein Alarm „Puls zu niedrig“

#### Scenario: Zonenvorlage ohne Zonen
- **GIVEN** keine Maximalpuls- oder Altersangabe
- **WHEN** der Nutzer „4×4 (Norwegisch)“ wählt
- **THEN** ist „Starten“ deaktiviert mit Verweis auf die Cardio-Einstellungen

#### Scenario: Vorlage zu Ende
- **GIVEN** die letzte Phase ist abgelaufen
- **WHEN** der Nutzer weiterfährt
- **THEN** läuft die Einheit weiter ohne Zielbereich, bis er beendet

### Requirement: Phasen in der gespeicherten Einheit

Eine Einheit mit Vorlage SHALL Vorlagenname und aufgelöste Phasen speichern. Die Zeit im Zielbereich MUST gegen die jeweils gültige Phase gerechnet werden. Die Pulskurve MUST das Zielband stufenweise je Phase zeigen.

#### Scenario: Zeit im Ziel je Phase
- **GIVEN** Phase 1 (0–5 s, Ziel 110–130) und Phase 2 (5–10 s, Ziel 150–170), Intervall 5 s, Werte 120 und 160
- **WHEN** die Kennzahlen berechnet werden
- **THEN** ist die Zeit im Zielbereich 10 s

### Requirement: Sprachansagen

Sind Sprachansagen eingeschaltet, SHALL die App Zonenalarme, Phasenwechsel und im gewählten Intervall Dauer und Puls auf Deutsch ansagen und andere Audiowiedergabe währenddessen leiser stellen. Standardmäßig MUST die Funktion aus sein.

#### Scenario: Musik läuft
- **GIVEN** Sprachansagen an und Musik läuft
- **WHEN** der Puls 16 s über dem Ziel liegt
- **THEN** wird die Musik leiser, die App sagt „Puls 146, über dem Ziel. Etwas langsamer.“ und die Musik wird wieder lauter

#### Scenario: Intervallansage
- **GIVEN** Sprachansagen alle 5 Minuten
- **WHEN** 10 Minuten vergangen sind
- **THEN** sagt die App „10 Minuten, Puls 134.“
