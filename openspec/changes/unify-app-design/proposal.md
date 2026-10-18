# Proposal

## Why

Das Trainingssystem wurde mit neuen Bausteinen und Bedienmustern umgebaut (große Titel mit Toolbar-Aktionen, gruppierte Listen, Wischen zum Löschen, Kontext-Sheets per langem Drücken, Sheets mit Griff zum Wegwischen, gestapelte Dialoge). Die übrigen Tabs nutzen zwar die neuen Farbrollen, sehen aber anders aus und verhalten sich anders: Untertitel unter dem Titel, große Akzent-Buttons im Inhalt, Inline-Buttons wie „Nach oben“, „Nach unten“ und „Entfernen“, Datumsfelder als Freitext. Der Wechsel zwischen Training und den anderen Tabs wirkt dadurch wie zwei verschiedene Apps.

## What Changes

- **Gemeinsame Bedienmuster als Bausteine:** Sheet mit Griff und Wischen-zum-Schließen, wischbare Listenzeile mit Bestätigung, Abschnittsüberschrift mit Zähler, Datumszeile mit Datumsauswahl-Sheet. Die Bausteine entstehen in `ui/core/components/` aus den vorhandenen Trainingsumsetzungen.
- **Heute:** Ohne Untertitel; Kennzahlen als gruppierte Karten im Stil der Trainingsstatistik; Zeitraumwahl als Segment.
- **Check-in und Apple Health:** „Check-in eintragen“ als „+“-Toolbar-Aktion, Ziel bearbeiten über das Menü bzw. Antippen der Zielkarte, Verlauf als gruppierte Liste mit Wischen zum Löschen, sofern Löschen bereits möglich ist; Datumsfelder als Datumszeilen.
- **Essen:** Datumsnavigation in der Toolbar, Lebensmittel hinzufügen als „+“-Toolbar-Aktion, Mahlzeiten als gruppierte Karten; Einträge per Antippen bearbeiten, per Wischen löschen, per langem Drücken Kontext-Sheet (Verschieben, Entfernen); Inline-Buttons entfallen.
- **Mehr, Sync, Coach, Anmeldung, Kontoverwaltung:** Gruppierte Listenzeilen mit Chevron statt gestapelter Akzent-Buttons, Erklärtexte als Fußnoten unter Gruppen, primäre Aktion als Toolbar- oder Abschluss-Pille.
- Fachliches Verhalten, Datenflüsse und Texte der Fachlogik bleiben unverändert.

### Non-Goals

- Keine neuen Funktionen, keine Änderungen an Backend, Sync-Protokoll oder Datenmodellen.
- Keine Änderung der Trainings-Screens außer der Übernahme gemeinsamer Bausteine.
- Kein Umbau der Web-PWA.

## Capabilities

- **Neu:** `app-interaction-patterns` – gemeinsame Bedien- und Layoutmuster für alle Tabs.

## Impact

- Flutter: `ui/core/components/`, `ui/features/{progress,body,nutrition,coach,sync,access}`, `ui/core/shell/`.
- Tests: Widget-Tests der Fachlogik bleiben inhaltlich gleich; wo Inline-Buttons durch Gesten ersetzt werden, werden Finder auf die neue Geste umgestellt. Golden-Tests in Hell und Dunkel werden neu erzeugt.
