# food-search-sheet

## ADDED Requirements

### Requirement: Übernehmen schließt und setzt zurück

Übernimmt der Nutzer einen Treffer aus Zuletzt, Suche oder Barcode, einen manuellen Eintrag oder Salz in eine Mahlzeit, SHALL das Sheet nach erfolgreichem Speichern schließen. Schlägt das Speichern fehl, MUST das Sheet offen bleiben und den Fehler zeigen. Jedes Öffnen SHALL auf der Startseite mit leerer Suche, ohne alte Treffer, mit 100 g und Quelle „Alle“ beginnen.

#### Scenario: Treffer übernehmen
- **GIVEN** die Suche zeigt „Hafer Flocken“
- **WHEN** der Nutzer den Treffer antippt
- **THEN** ist der Eintrag in der Mahlzeit gespeichert und das Sheet geschlossen

#### Scenario: Nächstes Öffnen
- **GIVEN** der Nutzer hat zuvor „Haferflocken“ gesucht und übernommen
- **WHEN** er das Sheet erneut öffnet und „Lebensmittel suchen“ wählt
- **THEN** ist das Suchfeld leer und es stehen keine Treffer da

### Requirement: Mahlzeit-Tabs nur auf der Startseite

Die Auswahl der Mahlzeit SHALL nur auf der Startseite „Hinzufügen“ erscheinen und MUST NOT auf den Unterseiten stehen.

#### Scenario: Unterseite Suche
- **GIVEN** das Sheet zeigt die Startseite mit Mahlzeit-Tabs
- **WHEN** der Nutzer „Lebensmittel suchen“ wählt
- **THEN** stehen auf der Unterseite keine Mahlzeit-Tabs

### Requirement: Eine Trefferliste mit Quellenfilter

Die Suche SHALL BLS- und Open-Food-Facts-Treffer in einer Liste zeigen, jede Zeile mit ihrer Quelle. Ein Filter „Alle · BLS · Produkte“ SHALL die Liste auf eine Quelle beschränken.

#### Scenario: Nur Produkte
- **GIVEN** Treffer aus beiden Quellen
- **WHEN** der Nutzer den Filter „Produkte“ wählt
- **THEN** zeigt die Liste nur Produkte von Open Food Facts

### Requirement: Online-Suche sichtbar starten

Solange für die aktuelle Eingabe nicht online gesucht wurde und eine Online-Anbindung besteht, SHALL über der Liste „In Open Food Facts suchen“ stehen. Der Filter „Produkte“ SHALL diese Suche ebenfalls starten. Ohne Online-Anbindung SHALL er „Produktsuche braucht Internet.“ zeigen.

#### Scenario: Produkte ergänzen
- **GIVEN** der Nutzer hat „Banane“ eingegeben und sieht BLS-Treffer
- **WHEN** er „In Open Food Facts suchen“ antippt
- **THEN** stehen die Produkte unter den BLS-Treffern in derselben Liste, mit „Open Food Facts“ in der Zeile

#### Scenario: Neue Eingabe
- **GIVEN** Produkte für „Banane“ werden angezeigt
- **WHEN** der Nutzer „Hafer“ eingibt
- **THEN** verschwinden die Produkte, und „In Open Food Facts suchen“ steht wieder über der Liste

### Requirement: Mehrere hinzufügen

Langes Drücken auf „Hinzufügen“ einer Mahlzeit oder auf das Plus der Ernährung SHALL „Mehrere hinzufügen“ anbieten. In diesem Modus SHALL das Sheet nach jedem erfolgreichen Eintrag offen bleiben, Suche, Treffer und Menge leeren und den Eintrag bestätigen. Ein Haken im Kopf SHALL das Sheet schließen.

#### Scenario: Zwei Lebensmittel zum Mittagessen
- **GIVEN** der Nutzer drückt lange auf „Hinzufügen“ beim Mittagessen und wählt „Mehrere hinzufügen“
- **WHEN** er nacheinander „Hafer Flocken“ und „Banane roh“ über die Suche übernimmt
- **THEN** enthält das Mittagessen beide Einträge, das Sheet ist noch offen und das Suchfeld leer

#### Scenario: Fertig
- **GIVEN** das Sheet ist im Modus „Mehrere hinzufügen“ offen
- **WHEN** der Nutzer den Haken antippt
- **THEN** schließt das Sheet

### Requirement: Gegliederte Startseite

Die Startseite des Sheets SHALL die Wege gruppieren: „Finden“ (Lebensmittel suchen, Zuletzt verwendet, Barcode), „Mit KI“ (Mahlzeit schätzen, Etikett erfassen) und „Selbst eintragen“ (Gespeicherte Gerichte, Manuell erfassen, Salz hinzufügen). Eine Unterseite SHALL oben beginnen, auch wenn die Startseite gescrollt war.

#### Scenario: Reihenfolge
- **GIVEN** das Sheet „Hinzufügen“ ist offen
- **WHEN** der Nutzer die Startseite ansieht
- **THEN** steht „Lebensmittel suchen“ zuerst und „Salz hinzufügen“ zuletzt

