# Design

## Decisions

### D1 – Muskelschlüssel

Feste Schlüssel in camelCase wie die Übungstypen: `chest`, `frontDelts`, `sideDelts`, `rearDelts`, `biceps`, `triceps`, `forearms`, `abs`, `obliques`, `lats`, `traps`, `lowerBack`, `glutes`, `quads`, `hamstrings`, `adductors`, `calves`. Backend (`MuscleKeys`) und App (`Muscle`) führen dieselbe Liste. Unbekannte Schlüssel aus dem Sync ignoriert die App, damit spätere Erweiterungen alte Builds nicht brechen. Das Backend lehnt sie ab.

### D2 – Modell und Grenzen

`primaryMuscles` und `secondaryMuscles` sind geordnete Listen von Schlüsseln, beide optional und standardmäßig leer. Höchstens 3 Haupt- und 6 Hilfsmuskeln, keine Wiederholungen, kein Muskel in beiden Listen. Gespeichert als `text[]` in `training.exercises`. `TargetMuscle` und `MuscleGroup` bleiben unverändert.

### D3 – Zählung

- Arbeitssatz = Satz mit Typ `normal` oder `dropset`. Aufwärmsätze zählen nie.
- Hauptmuskel +1 je Arbeitssatz, Hilfsmuskel +0,5.
- **Geplant:** `workingSets` jedes Eintrags. „Alle Pläne“ summiert alle nicht archivierten Pläne.
- **Trainiert:** abgeschlossene, nicht gelöschte Trainings, deren Start im Zeitraum liegt. Gezählt werden erfasste Arbeitssätze nach derselben Regel wie in der Statistik (`isSetRecorded`). Bei 28 Tagen wird durch 4 geteilt (Ø pro Woche). Die Übung wird über `sourceExerciseId` aufgelöst, auch wenn sie archiviert ist.

### D4 – Farbstufen

Satzzahl → Stufe: 0 = keine, unter 4 = wenig, 4 bis unter 10 = mittel, 10 bis 20 = viel, über 20 = sehr viel. Die Stufen nutzen die Akzentfarbe in steigender Deckkraft, „sehr viel“ die Warnfarbe. Die Legende zeigt die Grenzen. In der Übungsansicht (Editor) sind Hauptmuskeln voll und Hilfsmuskeln halb eingefärbt.

### D5 – Körperkarte

Eigenes Widget `BodyMap` mit `CustomPainter`. Silhouette und Muskelflächen sind eigene Pfade (Catmull-Rom-Kurven durch Stützpunkte, links definiert und gespiegelt), Vorder- und Rückansicht nebeneinander. Keine fremden Grafiken. Ein Tipp auf eine Fläche meldet den Muskel (Hit-Test über die Pfade). Die Karte hat ein Semantics-Label mit allen trainierten Muskeln und ihren Sätzen. Die Liste darunter bietet jede Fläche auch ohne Karte an.

### D6 – Oberfläche

- Übungseditor: Abschnitt „Muskeln“ nach „Notiz“ mit kleiner Karte und den Zeilen „Hauptmuskeln“ und „Hilfsmuskeln“. Jede Zeile öffnet ein Sheet zur Mehrfachauswahl. Muskeln der anderen Liste sind dort gesperrt und so beschriftet. Ein Tipp auf die Karte schaltet einen Muskel um: Haupt → Hilfs → keiner. Lesemodus (Basisübung): dieselben Zeilen ohne Bearbeitung.
- Statistik-Segment: Zeile „Muskeln“ über der Übungsliste → `MuscleMapScreen`.
- `MuscleMapScreen`: Segment „Geplant | Trainiert“. Bei „Geplant“ die Zeile „Plan“ mit Auswahl, bei „Trainiert“ das Segment „7 Tage | Ø 28 Tage“. Dann Karte mit Legende, Hinweis auf Übungen ohne Muskeln und eine Liste aller 17 Muskeln, absteigend nach Sätzen. Ein Tipp auf Zeile oder Fläche öffnet ein Sheet mit den beitragenden Übungen.
- Plan-Editor: Karte „Muskeln“ am Ende, nach Fehlern und Speicherhinweis, sobald der Plan mindestens eine Übung hat.

### D7 – Katalog

`exercise-catalog.v2.json` bekommt `primaryMuscles` und `secondaryMuscles` je Eintrag, `catalogVersion` 2026.10.2. Jeder Katalogeintrag braucht mindestens einen Hauptmuskel. Die Migration setzt die Werte der Basisübungen über `HasData`.
