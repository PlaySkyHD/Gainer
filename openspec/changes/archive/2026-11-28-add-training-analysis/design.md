# Design

## D1 Datengrundlage

Gezählt werden beendete, nicht gelöschte Trainings, deren lokaler Starttag im Zeitraum liegt (App: Gerätezeitzone, Server: Europe/Berlin wie alle Tools). Die Zeiträume sind die begrenzten des Verlaufs: 4 W ab Montag vor drei Wochen, 3 M ab Montag vor zwölf Wochen (Standard), 1 J ab dem Monatsersten vor elf Monaten. „Alle“ ist nicht erlaubt.

Arbeitssätze sind alle erfassten Sätze außer Aufwärmsätzen (unabhängig vom Schalter „Aufwärmsätze einbeziehen“, weil Aufwärmsätze nie über Fortschritt entscheiden sollen). Effektives Gewicht, Körpergewicht aus Check-ins, Volumen und 1RM (Epley) kommen unverändert aus `TrainingStatistics` bzw. `training_statistics.dart`; es gibt keine zweite Formel.

Eine Einheit ist ein Training mit mindestens einem Arbeitssatz der Übung; mehrere Blöcke einer Übung im Training zählen zusammen. Je Einheit: höchstes 1RM, höchstes effektives Gewicht (Topgewicht), Topsätze (Sätze mit diesem Gewicht, auf Cent verglichen), kleinste und größte Wiederholungen der Topsätze, größtes eingetragenes Gewicht der Topsätze, Zahl der Sätze mit RIR und mit RIR 0.

## D2 Trends

Einfach und deterministisch: k = max(1, Einheiten / 3) (ganzzahlig). Verglichen wird das Mittel der ersten k mit dem der letzten k Einheiten, ab zwei Einheiten. Das gilt für 1RM, Topgewicht und Volumen je Einheit (in %) sowie für die größte Topsatz-Wiederholung (absolut). Volumen und Arbeitssätze je Woche sind Summen geteilt durch (Tage des Zeitraums / 7). Eine lineare Regression wurde verworfen: Sie reagiert stärker auf einzelne Ausreißer und ist schwerer zu erklären.

## D3 Status

| Status | Regel |
| --- | --- |
| InsufficientData | weniger als 3 Einheiten oder keine 1RM-Änderung berechenbar |
| Regressing | 1RM-Änderung ≤ −2,5 % |
| Progressing | 1RM-Änderung ≥ +2,5 % und Bestwert in den letzten 3 Einheiten (höchstens 2 Einheiten danach) |
| Stagnating | sonst |

`sessionsSinceBest` zählt die Einheiten nach der ersten Einheit mit dem höchsten 1RM des Zeitraums.

## D4 Ermüdungssignale

- `DecliningRepetitions`: In den letzten 3 Einheiten steigt das Topgewicht nicht, und die größte Topsatz-Wiederholung sinkt zweimal. Belege: von/bis Wiederholungen, Topgewicht.
- `FailureOnMostSets`: In beiden letzten Einheiten haben mindestens 2 Arbeitssätze einen RIR und mehr als die Hälfte davon RIR 0. Belege: Sätze mit RIR 0 und mit RIR in der letzten Einheit.
- `VolumeAndStrengthDrop`: Ab 3 Einheiten verliert die letzte gegenüber dem Mittel der bis zu 3 Einheiten davor mindestens 20 % Volumen und 5 % 1RM. Belege: beide Änderungen.

## D5 Empfehlung

Grundlage ist die letzte Einheit, Reihenfolge:

1. Keine Einheit → `NoRecommendation`.
2. Ermüdungssignal oder `Regressing` → `Deload`: 90 % des eingetragenen Topgewichts, auf die Stufe abgerundet (ganzzahlig in Cent gerechnet).
3. `Stagnating` mit mindestens 4 Einheiten seit dem Bestwert → `ChangeStimulus` (Wiederholungsbereich oder Variante wechseln).
4. Doppelte Progression. Planeinträge haben kein Wiederholungsziel, daher wählt die größte Topsatz-Wiederholung den Bereich: bis 5 → 3–5, bis 12 → 6–12, darüber 13–20.
   - Alle Topsätze am oberen Ende: `IncreaseWeight` um die Stufe, Wiederholungen auf das untere Ende (Kraft, Körpergewicht mit Zusatzgewicht); bei Körpergewicht ohne Zusatz und assistiert `ChangeStimulus` mit Bereich.
   - Ein Topsatz unter dem unteren Ende: `KeepWeight`, Ziel unteres Ende.
   - Sonst `IncreaseReps`, Ziel kleinste Topsatz-Wiederholung + 1.

Stufe: kleinster positiver Abstand der eingetragenen Gewichte aller Arbeitssätze der Übung im Zeitraum, höchstens 2,5 kg, ohne Abstand 2,5 kg. Gewichte in Empfehlungen sind eingetragene Gewichte (Zusatz- bzw. Unterstützungsgewicht), nicht effektive.

Der deutsche Begründungstext entsteht je Seite an genau einer Stelle (`TrainingRecommendation.Text` bzw. `TrainingRecommendation.text()`), die Fixture prüft den Wortlaut. Die App kann Gewichte in lbs formatieren; in kg ist der Text identisch.

## D6 Gesamt

7-Tage-Abschnitte ab Zeitraumbeginn mit Volumen und Arbeitssätzen aller Übungen. Der Wochentrend nutzt die Regel aus D2 über die vollständigen Abschnitte (der laufende zählt nicht, sonst zöge er den Trend nach unten). `Fatigued` gilt, wenn mindestens eine Übung ein Signal hat und diese mindestens ein Drittel der Übungen mit 3 oder mehr Einheiten sind.

## D7 Server und Tool

`TrainingAnalysisQueries.AnalysisAsync` lädt Check-ins (Zeitraum plus letzter davor), beendete Trainings ab Zeitraumbeginn und Katalogfaktoren in einer RepeatableRead-Transaktion; der globale Query-Filter isoliert die Nutzer. `get_training_analysis(period = threeMonths, exerciseId?)` ist nur lesend, idempotent, ohne offene Welt und liefert eigene Ergebnis-Records mit PascalCase-Enums. Eine fremde oder unbekannte Übung ergibt einen Tool-Fehler; der Gesamtteil umfasst immer alle Übungen.

## D8 App

Neuer Eintrag „Trainingsanalyse“ im Statistikbereich unter „Muskeln“. Der Screen nutzt `GainerScaffold`, `GainerSegmentedControl` (4 W, 3 M, 1 J), `GainerGroupedSection` und `GainerListRow`; je Übung ein Status-Badge (ab Textgröße 1,5 in der Unterzeile). Das Detail zeigt Empfehlung, Trends, Ermüdungshinweise und Einheiten. Daten kommen aus dem lokalen Drift-Speicher wie die übrige Statistik.
