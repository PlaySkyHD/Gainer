## ADDED Requirements

### Requirement: Verlauf im Statistikbereich

Die App SHALL im Statistikbereich einen Bereich „Verlauf“ mit Zeitraum-Umschalter (4 Wochen, 3 Monate, 1 Jahr, Alle; Standard 3 Monate) und je einer Kachel für Trainings pro Woche, Ø Trainingsdauer, Gesamtzeit, Volumen, Sätze, Wiederholungen, Ø Wiederholungen pro Satz und Körpergewicht anzeigen. Ohne gezähltes Training und ohne Check-in MUST der Bereich fehlen. Hat nur der gewählte Zeitraum keine Daten, SHALL statt der Kacheln ein Hinweis erscheinen.

#### Scenario: Zeitraum wechseln
- **GIVEN** heute ist Samstag, 17. Oktober 2026, und es gibt drei beendete Trainings
- **WHEN** der Nutzer „4 W“ wählt
- **THEN** beginnt der Zeitraum am Montag, 21. September 2026, und die Kachel Krafttrainings zeigt „Ø 0,8 pro Woche“

#### Scenario: Zeitraum ohne Daten
- **GIVEN** das einzige Training liegt mehr als drei Monate zurück
- **WHEN** der Nutzer die Statistik mit dem Zeitraum 3 Monate öffnet
- **THEN** erscheint statt der Kacheln ein Hinweis, und mit „Alle“ erscheinen die Kacheln

#### Scenario: Große Schrift
- **GIVEN** die Textgröße ist 2,0
- **WHEN** der Bereich „Verlauf“ erscheint
- **THEN** stehen die Kacheln untereinander und nichts läuft über

### Requirement: Abschnitte des Verlaufs

Jede Verlaufskachel MUST einen Wert für den ganzen Zeitraum und eine Linie je Woche (4 Wochen, 3 Monate) oder je Kalendermonat (1 Jahr, Alle) zeigen. Wochen beginnen montags, der letzte Abschnitt enthält den heutigen Tag. „Alle“ beginnt im Monat des ersten gezählten Trainings oder Check-ins.

#### Scenario: Ein Jahr
- **GIVEN** heute ist der 26. November 2026
- **WHEN** der Verlauf für 1 Jahr berechnet wird
- **THEN** beginnt er am 1. Dezember 2025 und hat zwölf Monatsabschnitte

### Requirement: Kennzahlen des Verlaufs

Sätze, Wiederholungen und Volumen im Verlauf MUST derselben Datengrundlage und denselben Formeln folgen wie Rekorde und Übungsstatistik, einschließlich der Einstellung für Aufwärmsätze. Die Dauer eines Trainings ist die Zeit von Start bis Ende. Trainings pro Woche ist die Zahl der Trainings im Zeitraum geteilt durch die Tage vom ersten Tag des Zeitraums bis heute, geteilt durch sieben.

#### Scenario: Werte für drei Monate
- **GIVEN** heute ist Samstag, 17. Oktober 2026, und es gibt drei beendete Trainings à 60 Minuten mit zusammen 6 gezählten Sätzen, 38 Wiederholungen und 3.550 kg Volumen
- **WHEN** der Nutzer die Statistik mit dem Zeitraum 3 Monate öffnet
- **THEN** zeigen die Kacheln „Ø 0,2 pro Woche“, „Ø 60 min“, „3:00 h“, „3.550 kg“, „6“, „38“ und „Ø 6,3“

### Requirement: Körpergewicht im Verlauf

Die Körpergewichtskachel MUST als Wert den jüngsten Check-in im Zeitraum zeigen und als Linie den Durchschnitt der Check-ins je Abschnitt. Abschnitte ohne Check-in MUST leer bleiben und nicht als 0 gelten; die Linie überbrückt sie nicht.

#### Scenario: Woche ohne Check-in
- **GIVEN** Check-ins in der ersten und letzten von vier Wochen
- **WHEN** der Verlauf für 4 Wochen berechnet wird
- **THEN** hat die Körpergewichtslinie Punkte nur für diese zwei Wochen
