# Design

## Decisions

### D1 – Auswahl und Daten

Übungen, die in üblichen Studios vorkommen, je Muskelgruppe mit den gängigen Varianten (Langhantel, Kurzhantel, Kabelzug, Maschine, Körpergewicht). Namen auf Deutsch mit Equipment in Klammern, wo es Varianten gibt. Muskeln aus der festen Liste der Muskelkarte, Auswahl und Muskeln gegen das MIT-lizenzierte exercises-dataset gegengeprüft. Die Anleitungen sind eigene Texte.

### D2 – IDs und Migration

Bestehende Einträge behalten ihre IDs. Neue IDs sind UUIDv5 aus einem festen Namensraum und einem Schlüssel je Übung. Die Migration ändert Namen und Werte über `HasData` und fügt neue Einträge und Kategoriezuordnungen ein. Trainings behalten ihre Namens-Snapshots.

### D3 – Körpergewichtsfaktoren

Übungen mit Körpergewicht bekommen einen geschätzten Anteil (z. B. Crunches 30 %, Rudern mit Körpergewicht 60 %), damit Volumen und Rekorde nicht mit 100 % gerechnet werden.

### D4 – Muskel-Vorschlag

Reine Funktion `suggestMuscleSource(name, candidates)`. Namen werden kleingeschrieben, Umlaute ersetzt, in Wörter zerlegt, Füllwörter entfernt und gängige englische Begriffe übersetzt. Ähnlichkeit je Wort: gleich = 1, enthalten = Längenanteil, gemeinsamer Anfang ab sechs Zeichen = Längenanteil. Punktzahl = Ø der besten Ähnlichkeit der Suchwörter + ½ × Ø für die Wörter der Kandidatin. Mindestens ein Wort, das kein Equipment ist, muss zu 60 % passen, und die Punktzahl muss mindestens 0,75 betragen. Der Vorschlag erscheint nur, solange keine Muskeln gewählt sind.
