# Spec Delta

## Purpose

Diese Capability definiert das einheitliche visuelle System der iPhone-App für alle Bereiche: Farbrollen in Hell und Dunkel, Flächen und Rundungen, Typografie, schwebende Tableiste, Sheets, Kontextmenüs und Barrierefreiheit.

## ADDED Requirements

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

Die Hauptnavigation SHALL eine schwebende, stark gerundete Leiste am unteren Rand mit dauerhaft beschrifteten Icons sein. Der aktive Tab MUST durch eine hinterlegte Fläche und Akzentfarbe markiert sein. Die Leiste enthält die bestehenden Bereiche Heute, Check-in, Essen, Training und Mehr.

#### Scenario: Tab wechseln
- **GIVEN** der Tab „Heute“ ist aktiv
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

### Requirement: Bestehende Bereiche im neuen Design

Alle bestehenden Screens (Heute, Check-in, Essen, Coach, Mehr, Sync, Apple Health, Anmeldung, Kontoverwaltung) MUST auf die gemeinsamen Farbrollen, Karten, Toolbar-Aktionen, Sheets und Dialoge umgestellt werden, ohne ihr fachliches Verhalten zu ändern.

#### Scenario: Ernährungstag im neuen Design
- **GIVEN** der Ernährungstag eines Nutzers mit Einträgen
- **WHEN** er im Dunkelmodus angezeigt wird
- **THEN** stehen Mahlzeiten als gerundete Karten auf schwarzem Hintergrund, Aktionen sind türkis und alle bisherigen Funktionen und Werte sind unverändert vorhanden
