# Design

## Context

Referenz für Aussehen und Verhalten ist der Trainings-Tab (`ui/features/training/`). Er nutzt `GainerScaffold` (großer Titel, Toolbar links/rechts), `GainerSegmentedControl`, `GainerGroupedSection`/`GainerListRow`, `GainerCard`, `showGainerActionSheet`, `showGainerStackedDialog`, `Dismissible` mit Bestätigung im Tagebuch und das wischbare Pausentimer-Sheet.

## Decisions

### D1 – Layoutregeln je Screen

1. Titel nur über `GainerScaffold`; kein Untertitel-Absatz unter dem großen Titel.
2. Seitenaktionen (Hinzufügen, Bearbeiten, Menü, Datum) stehen als `GainerToolbarButton`/`GainerPillButton` in der Toolbar. Gefüllte Akzent-Pillen im Inhalt gibt es nur für die eine Abschlussaktion eines Formulars oder Sheets (z. B. „Speichern“, „Frage senden“).
3. Inhalte stehen in `GainerGroupedSection` mit kleiner Überschrift darüber und optionaler Fußnote darunter; Navigation in Unterseiten über `GainerListRow` mit Chevron.
4. Abschnittsüberschriften wie im Tagebuch: Titel links, Zähler oder Kurzinfo rechts in Sekundärtext.
5. Erklärtexte und Hinweise als Fußnote einer Gruppe in Sekundärtext, nicht als eigene Karte.

### D2 – Interaktionsregeln

1. Löschen in Listen per Wischen nach links mit Bestätigungsdialog; im Bearbeiten-Modus zusätzlich rotes Minus.
2. Weitere Zeilenaktionen per langem Drücken über `showGainerActionSheet`; keine Inline-Textbuttons in Zeilen.
3. Reihenfolge ändern über ein Neuordnen-Sheet mit Ziehgriffen (wie Übungen neu ordnen) statt „Nach oben/Nach unten“.
4. Alle Sheets haben einen Griff und schließen per Wischen nach unten, per X oder Tippen auf den Hintergrund. Dafür entsteht `showGainerSheet` in `ui/core/components/gainer_sheet.dart`, abgeleitet aus `_SwipeToDismiss` des Pausentimers.
5. Datum und Uhrzeit werden über eine `GainerListRow` mit Wert rechts gewählt, die ein Sheet mit `CupertinoDatePicker` öffnet; Freitextfelder im Format JJJJ-MM-TT entfallen.

### D3 – Reihenfolge und Arbeitsteilung

Zuerst die gemeinsamen Bausteine (ein PR), danach je Bereich ein PR, parallel in getrennten Worktrees: Heute, Check-in/Apple Health, Essen, Mehr/Sync/Coach/Zugang. Jeder PR aktualisiert die Golden-Tests des Bereichs; Fachtests bleiben grün.

## Risks / Trade-offs

- Gesten sind schlechter auffindbar als Buttons → Bearbeiten-Modus mit sichtbaren Minus-Buttons und Kontext-Sheet als Alternative; Semantics-Labels für VoiceOver bleiben erhalten.
- Ersetzte Inline-Buttons brechen bestehende Widget-Tests → Tests suchen künftig über Geste oder Kontext-Sheet, prüfen aber dieselben fachlichen Ergebnisse.
