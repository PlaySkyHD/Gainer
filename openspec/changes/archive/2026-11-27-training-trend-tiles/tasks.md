# Tasks

## 1. Berechnung

- [x] 1.1 `TrainingTrends.compute` mit Zeiträumen, Abschnitten und Kennzahlen. Prüfung: `test/domain/training/training_trends_test.dart` grün.
- [x] 1.2 `workoutTrendEntries` nutzt `workoutExerciseStats` und den Aufwärmsatz-Schalter. Prüfung: dieselbe Testdatei grün.

## 2. Oberfläche

- [x] 2.1 Bereich „Verlauf“ mit Umschalter und acht Kacheln im Statistikbereich. Prüfung: `training_statistics_section_test.dart` grün.
- [x] 2.2 Kein Überlauf bei Textgröße 1,4 und 2,0; ab 1,5 untereinander. Prüfung: `training_statistics_section_test.dart` grün.
- [x] 2.3 Goldens der Statistikliste aktualisiert und Vorschau geprüft.

## 3. Spec

- [x] 3.1 Anforderung in `training-statistics`. Prüfung: `openspec validate --specs --strict` grün.
