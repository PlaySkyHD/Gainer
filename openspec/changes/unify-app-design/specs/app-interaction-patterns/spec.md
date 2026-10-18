# app-interaction-patterns

## ADDED Requirements

### Requirement: Einheitlicher Screen-Aufbau

Jeder Tab-Screen SHALL wie der Trainings-Tab aufgebaut sein: großer Titel ohne Untertitel, Seitenaktionen in der Toolbar, Inhalte in gruppierten Karten mit Überschrift und optionaler Fußnote. Gefüllte Akzent-Pillen im Inhalt MUST auf die Abschlussaktion eines Formulars oder Sheets beschränkt sein.

#### Scenario: Check-in eintragen
- **GIVEN** der Check-in-Tab ist geöffnet
- **WHEN** der Nutzer einen Check-in anlegen will
- **THEN** findet er dafür einen „+“-Button oben rechts und keinen großen Akzent-Button im Inhalt

#### Scenario: Kein Untertitel
- **GIVEN** einer der Tabs Heute, Check-in, Essen oder Mehr
- **WHEN** er angezeigt wird
- **THEN** folgt auf den großen Titel direkt der Inhalt ohne erklärenden Untertitel

### Requirement: Listenzeilen und Gesten

Listeneinträge SHALL per Antippen geöffnet, per Wischen nach links nach Bestätigung gelöscht und per langem Drücken mit einem Kontext-Sheet bedient werden. Inline-Textbuttons wie „Nach oben“, „Nach unten“ oder „Entfernen“ MUST NOT in Listenzeilen erscheinen.

#### Scenario: Lebensmittel löschen
- **GIVEN** ein Lebensmitteleintrag in einer Mahlzeit
- **WHEN** der Nutzer ihn nach links wischt und „Löschen“ bestätigt
- **THEN** wird der Eintrag entfernt; bei „Abbrechen“ bleibt er unverändert

#### Scenario: Kontext-Sheet
- **GIVEN** ein Lebensmitteleintrag
- **WHEN** der Nutzer lange darauf drückt
- **THEN** öffnet ein Sheet mit dem Namen als Titel und den Aktionen des Eintrags, Löschen rot

#### Scenario: Reihenfolge ändern
- **GIVEN** eine Mahlzeit mit mehreren Einträgen
- **WHEN** der Nutzer „Verschieben“ wählt
- **THEN** öffnet ein Neuordnen-Sheet mit Ziehgriffen, dessen Ergebnis dieselbe Reihenfolge speichert wie bisher

### Requirement: Sheets mit Griff

Alle Bottom-Sheets SHALL einen Griff oben zeigen und per Wischen nach unten, per X oder per Tippen auf den Hintergrund schließen. Ein kurzes Ziehen MUST zurückfedern.

#### Scenario: Sheet wegwischen
- **GIVEN** ein offenes Sheet außerhalb des Trainings
- **WHEN** der Nutzer es schnell nach unten wischt
- **THEN** schließt das Sheet ohne Änderung

### Requirement: Datumsauswahl

Datum und Uhrzeit SHALL über eine Zeile mit aktuellem Wert rechts gewählt werden, die eine Datumsauswahl im Sheet öffnet. Freitexteingaben im Format JJJJ-MM-TT MUST entfallen.

#### Scenario: Zeitraum für Apple Health
- **GIVEN** die Apple-Health-Prüfung
- **WHEN** der Nutzer „Von“ antippt
- **THEN** öffnet eine Datumsauswahl und der gewählte Tag erscheint in der Zeile

### Requirement: Fachliches Verhalten unverändert

Die Umstellung MUST rein gestalterisch bleiben: alle bisherigen Funktionen, Werte, Validierungen und Datenflüsse der Bereiche bleiben erhalten und erreichbar.

#### Scenario: Funktion bleibt erreichbar
- **GIVEN** eine Funktion, die vorher per Inline-Button erreichbar war
- **WHEN** der Screen umgestellt ist
- **THEN** ist sie per Geste, Kontext-Sheet, Toolbar oder Bearbeiten-Modus weiterhin erreichbar
