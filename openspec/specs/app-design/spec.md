# app-design Specification

## Purpose
Einheitliches visuelles System und gemeinsame Bedienmuster der iPhone-App: Farbrollen in Hell und Dunkel, Karten, Typografie, Tableiste, Toolbar, Sheets, Dialoge, Gesten und Barrierefreiheit.

## Requirements

### Requirement: Hell- und Dunkelmodus nach Systemeinstellung

Die App MUST ein helles und ein dunkles Erscheinungsbild besitzen und standardmäßig der iOS-Einstellung folgen. Ein Wechsel der Systemeinstellung SHALL ohne Neustart und ohne Verlust eingegebener Werte übernommen werden.

#### Scenario: Systemwechsel während der Eingabe
- **GIVEN** der Nutzer tippt im hellen Modus ein Gewicht in eine Satzzeile
- **WHEN** iOS auf den Dunkelmodus wechselt
- **THEN** stellt die App sofort dunkel dar, das Feld bleibt fokussiert und der eingegebene Wert bleibt erhalten

### Requirement: Farbrollen

Die App SHALL Farben ausschließlich über benannte Rollen verwenden: Hintergrund, Fläche, erhöhte Fläche, Trenner, Primärtext, Sekundärtext, Platzhaltertext, Akzent (Türkis), Akzent-Inhalt, Warnung/Timer-Stopp (Orange) und Destruktiv (Rot). Im Dunkelmodus MUST der Hintergrund Schwarz sein; Flächen sind dunkle neutrale Grautöne.

#### Scenario: Dunkelmodus-Grundfarben
- **GIVEN** der Dunkelmodus ist aktiv
- **WHEN** ein beliebiger Hauptbereich angezeigt wird
- **THEN** ist der Hintergrund schwarz, Karten sind dunkelgraue Flächen, Hauptaktionen und aktive Elemente türkis und destruktive Aktionen rot

#### Scenario: Keine fest codierten Farben
- **GIVEN** ein beliebiger Screen der App
- **WHEN** zwischen Hell- und Dunkelmodus gewechselt wird
- **THEN** wechseln alle Flächen-, Text- und Akzentfarben gemeinsam und es bleiben keine Elemente in der Farbe des anderen Modus stehen

### Requirement: Kontrast und Lesbarkeit

Primär- und Sekundärtext MUST in beiden Modi ein Kontrastverhältnis von mindestens 4,5:1 zu ihrer Fläche erreichen, Akzent auf Fläche mindestens 3:1. Platzhalter für Vorwerte MUST sich deutlich von eingetragenen Werten unterscheiden und dürfen den Zustand nicht allein über Farbe vermitteln.

#### Scenario: Vorwert und eingetragener Wert
- **GIVEN** eine Satzzeile mit einem eingetragenen Wert und einer mit Vorwert-Platzhalter
- **WHEN** VoiceOver beide Felder vorliest
- **THEN** wird der eingetragene Wert als Wert und der Platzhalter als „Vorwert“ angesagt

### Requirement: Flächen, Karten und Rundungen

Inhalte SHALL in gruppierten Karten auf dem Hintergrund liegen: große Rundung (etwa 20 pt) für Karten und Sheets, Pillenform für Buttons und Toolbar-Aktionen, Kreisform für Icon-Buttons. Zeilen innerhalb einer Karte werden durch feine Trenner getrennt, nicht durch eigene Rahmen.

#### Scenario: Gruppierte Einstellungen
- **GIVEN** eine Liste zusammengehöriger Einstellungen
- **WHEN** sie angezeigt wird
- **THEN** stehen die Zeilen in einer gemeinsamen gerundeten Karte mit feinen Trennern und optionaler grauer Gruppenüberschrift darüber

### Requirement: Typografie

Die App MUST die iOS-Systemschrift mit Dynamic Type verwenden: große, fette Seitentitel am Listenanfang, die beim Scrollen in eine kompakte Titelleiste übergehen, hervorgehobene Karten- und Übungstitel, normale Eingabewerte sowie kleine graue Feldlabels. Zeit- und Countdown-Anzeigen SHALL Ziffern mit fester Breite verwenden.

#### Scenario: Großer Titel beim Scrollen
- **GIVEN** das Tagebuch ist am Listenanfang mit großem Titel geöffnet
- **WHEN** der Nutzer nach unten scrollt
- **THEN** wechselt der Titel in eine kompakte Titelleiste und die Aktionen bleiben erreichbar

#### Scenario: Große Schrift
- **GIVEN** der Nutzer hat in iOS eine der größten Textgrößen aktiviert
- **WHEN** eine Satzzeile angezeigt wird
- **THEN** sind Gewicht, Wiederholungen und Satzlabel vollständig lesbar und nicht abgeschnitten

### Requirement: Schwebende Tableiste

Die Hauptnavigation SHALL eine schwebende, stark gerundete Leiste am unteren Rand mit dauerhaft beschrifteten Icons sein. Der aktive Tab MUST durch eine hinterlegte Fläche und Akzentfarbe markiert sein. Die Leiste enthält in dieser Reihenfolge die Bereiche Übersicht, Check-in, Essen, Training und Mehr.

#### Scenario: Tab wechseln
- **GIVEN** der Tab „Übersicht“ ist aktiv
- **WHEN** der Nutzer „Training“ antippt
- **THEN** wird der Trainingsbereich angezeigt und „Training“ ist mit Fläche und Akzentfarbe hervorgehoben

#### Scenario: Aktives Training minimiert
- **GIVEN** ein minimiertes aktives Training
- **WHEN** ein beliebiger Tab angezeigt wird
- **THEN** liegt die kompakte Trainingsleiste direkt über der Tableiste, ohne Inhalte oder Tabs zu verdecken

### Requirement: Toolbar-Aktionen

Seitenaktionen SHALL als runde oder pillenförmige Buttons auf einer eigenen Fläche oben links und rechts erscheinen (z. B. „Bearbeiten“, „+“, „…“). Die primäre Abschlussaktion eines Kontexts MUST als gefüllte Akzent-Pille dargestellt werden.

#### Scenario: Primäraktion im Training
- **GIVEN** ein aktives Training ist geöffnet
- **WHEN** die obere Leiste angezeigt wird
- **THEN** ist „Beenden“ eine gefüllte türkise Pille und Minimieren, Timer und Menü sind runde Buttons

### Requirement: Sheets und Kontextmenüs

Kontextaktionen SHALL in einem gerundeten Bottom-Sheet mit Titel und Schließen-Button erscheinen. Die häufigsten Aktionen stehen als Reihe gleich breiter Icon-Text-Buttons oben, destruktive Aktionen rot; weitere Aktionen folgen in gruppierten Karten mit Icon rechts.

#### Scenario: Übungsmenü
- **GIVEN** ein Übungsblock im Training
- **WHEN** der Nutzer dessen Menü öffnet
- **THEN** zeigt ein Sheet mit dem Übungsnamen oben die Reihe „Verschieben“, „Ersetzen“, „Löschen“ (rot) und darunter Gruppen für Notiz, Verlauf, Graphen, Rekorde und Gewichtseinheit

#### Scenario: Sheet schließen
- **GIVEN** ein offenes Kontext-Sheet
- **WHEN** der Nutzer nach unten wischt oder X tippt
- **THEN** schließt das Sheet ohne Änderung und der Fokus kehrt zum auslösenden Element zurück

### Requirement: Bestätigungsdialoge

Entscheidungen mit mehreren Ausgängen SHALL als zentrierter, gerundeter Dialog mit Titel, Erklärung und vertikal gestapelten, vollbreiten Aktionen erscheinen. Destruktive Bestätigungen MUST rot beschriftet sein und dürfen nicht die vorausgewählte Aktion sein.

#### Scenario: Training löschen bestätigen
- **GIVEN** der Nutzer wählt „Löschen“ für ein Training
- **WHEN** der Bestätigungsdialog erscheint
- **THEN** ist „Löschen“ rot beschriftet, „Abbrechen“ ist verfügbar und ein versehentliches Bestätigen per Return-Taste ist nicht möglich

### Requirement: Alle Bereiche im gemeinsamen Design

Alle Screens (Übersicht, Check-in, Essen, Coach, Mehr, Sync, Apple Health, Anmeldung, Kontoverwaltung) MUST die gemeinsamen Farbrollen, Karten, Toolbar-Aktionen, Sheets und Dialoge verwenden.

#### Scenario: Ernährungstag im Dunkelmodus
- **GIVEN** der Ernährungstag eines Nutzers mit Einträgen
- **WHEN** er im Dunkelmodus angezeigt wird
- **THEN** stehen Mahlzeiten als gerundete Karten auf schwarzem Hintergrund und Aktionen sind türkis

### Requirement: Einheitlicher Screen-Aufbau

Jeder Tab-Screen SHALL wie der Trainings-Tab aufgebaut sein: großer Titel ohne Untertitel, Seitenaktionen in der Toolbar, Inhalte in gruppierten Karten mit Überschrift und optionaler Fußnote. Gefüllte Akzent-Pillen im Inhalt MUST auf die Abschlussaktion eines Formulars oder Sheets beschränkt sein.

#### Scenario: Check-in eintragen
- **GIVEN** der Check-in-Tab ist geöffnet
- **WHEN** der Nutzer einen Check-in anlegen will
- **THEN** findet er dafür einen „+“-Button oben rechts und keinen großen Akzent-Button im Inhalt

#### Scenario: Kein Untertitel
- **GIVEN** einer der Tabs Übersicht, Check-in, Essen oder Mehr
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
- **THEN** öffnet ein Neuordnen-Sheet mit Ziehgriffen, das die neue Reihenfolge speichert

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

### Requirement: Funktionen bleiben erreichbar

Jede Funktion eines Bereichs MUST über Antippen, Geste, Kontext-Sheet, Toolbar oder Bearbeiten-Modus erreichbar sein.

#### Scenario: Funktion ohne Inline-Button
- **GIVEN** eine Listenzeile ohne Inline-Buttons
- **WHEN** der Nutzer sie verschieben oder löschen will
- **THEN** findet er die Aktion im Kontext-Sheet per langem Drücken oder per Wischen
