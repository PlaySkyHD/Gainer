# Design

## Decisions

### D1 – Modell

`WarmupStep(percent: int 1–100, repetitions: int? 1–50)`. `WarmupSettings(enabled: bool = true, showRepetitions: bool = false, steps: [50 %, 80 %])` global in `TrainingPreferenceValues`. `ExerciseWarmupOverride(exerciseId, enabled: bool?, steps: List<WarmupStep>?, roundingKg: double?)` lokal pro Konto, gespeichert neben den Trainingseinstellungen (gleicher Store, Schlüssel je Übung). Fehlende Felder erben die globalen Werte. Maximal fünf Stufen.

### D2 – Berechnung

Reine Funktion `warmupTargets(baseKg, steps, roundingKg, unit)`:
- Basis = Gewicht des ersten Arbeitssatzes (Satztyp normal) aus den Vorwerten des Blocks (`previousValuesFor`), sonst nichts.
- Gewicht je Stufe = Basis × Prozent, gerundet auf das nächste Vielfache der Rundung in der Anzeigeeinheit (Standard 2,5 kg bzw. 5 lb; erlaubt 0,5 / 1 / 1,25 / 2,5 / 5 kg bzw. 1 / 2,5 / 5 / 10 lb).
- Stufen mit Ergebnis ≤ 0 oder ≥ Basis entfallen; doppelte Gewichte werden zusammengefasst.

### D3 – Anzeige

Zeile in Sekundärtext mit Flammen-Icon über der ersten Arbeitssatzzeile nur im aktiven Training: „Aufwärmen 40 kg · 62,5 kg“, mit Wiederholungen „40 kg × 8 · 62,5 kg × 3“. Nicht bei historischen Trainings, nicht wenn bereits erfasste Aufwärmsätze im Block existieren.

### D4 – Eintragen

Tipp auf die Zeile → Action-Sheet mit „Als Aufwärmsätze eintragen“. Legt je Stufe einen Aufwärmsatz mit Gewicht (und Wiederholungen, falls angegeben) vor dem ersten Arbeitssatz an – über die vorhandenen ViewModel-Operationen für Sätze und Satztypen.

### D5 – Oberfläche der Einstellungen

- Global: im Trainings-Menü des Workout-Screens bei den übrigen Trainingseinstellungen ein Eintrag „Aufwärmhinweis“ → Sheet mit Schalter, Stufenliste (Prozent, optionale Wdh., löschen, „+ Stufe“) und Schalter „Wiederholungen anzeigen“.
- Pro Übung: im Übungseditor Abschnitt „Aufwärmen“ mit Auswahl „Standard verwenden / Eigene Stufen / Aus“, Stufenliste wie oben und Rundung.
