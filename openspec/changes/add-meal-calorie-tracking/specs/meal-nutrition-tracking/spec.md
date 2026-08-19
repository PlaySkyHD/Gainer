## Purpose

Diese Capability ermöglicht ein nutzergebundenes, offline-first Ernährungstagebuch mit vier Mahlzeiten, stabilen Nährwert-Snapshots und deterministischen Tagesaggregaten.

## ADDED Requirements

### Requirement: Ernährungstag mit vier Mahlzeiten

Das System MUST pro Nutzer und lokalem Kalendertag die festen Mahlzeiten `Breakfast`, `Lunch`, `Dinner` und `Snacks` bereitstellen. Ein Ernährungseintrag MUST genau einer Mahlzeit zugeordnet sein und SHALL innerhalb seiner Mahlzeit eine stabile Position besitzen.

#### Scenario: Leeren Ernährungstag öffnen

- **GIVEN** ein authentifizierter Nutzer besitzt am gewählten lokalen Kalendertag noch keine Ernährungseinträge
- **WHEN** er das Ernährungstagebuch öffnet
- **THEN** zeigt die Anwendung die vier leeren Mahlzeiten und Tageswerte von null, ohne Datensätze anderer Nutzer anzuzeigen

#### Scenario: Eintrag einer Mahlzeit zuordnen

- **GIVEN** ein Nutzer wählt ein Lebensmittel und die Mahlzeit `Breakfast`
- **WHEN** er den Eintrag speichert
- **THEN** erscheint der Eintrag ausschließlich an diesem Tag unter Frühstück und fließt genau einmal in dessen Mahlzeiten- und Tagessumme ein

### Requirement: Nährwert-Snapshot pro Eintrag

Jeder Ernährungseintrag MUST eine stabile ID, Produktname, Menge, Mengeneinheit, Kilokalorien sowie optional Protein, Kohlenhydrate und Fett als Snapshot speichern. Ein externer Eintrag SHALL zusätzlich Anbieter, Barcode, Bezugsbasis der Nährwerte und Abrufzeitpunkt speichern. Spätere Änderungen der externen Quelle MUST bestehende Ernährungseinträge unverändert lassen.

#### Scenario: Open-Food-Facts-Produkt übernehmen

- **GIVEN** ein Produkt liefert gültige Nährwerte pro 100 Gramm
- **WHEN** der Nutzer 150 Gramm davon in eine Mahlzeit übernimmt
- **THEN** speichert das System Produkt- und Quellen-Snapshot sowie die für 150 Gramm deterministisch berechneten Nährwerte

#### Scenario: Externer Produktdatensatz ändert sich später

- **GIVEN** ein Ernährungseintrag enthält einen gespeicherten Produkt-Snapshot
- **WHEN** Open Food Facts Name oder Nährwerte desselben Barcodes später ändert
- **THEN** bleibt der historische Ernährungseintrag unverändert und eine erneute Auswahl verwendet einen neuen Snapshot

### Requirement: Menge und Nährwerte deterministisch berechnen

Das System MUST bei grammbezogenen Produktdaten die Eintragswerte proportional aus Menge und Nährwerten pro 100 Gramm berechnen und mit einer dokumentierten Rundungsregel speichern. Menge und Kilokalorien MUST positiv und endlich sein; optionale Makros MUST nicht negativ und endlich sein. Produkte mit fehlender verwertbarer Energieangabe DÜRFEN nicht ohne manuelle Ergänzung übernommen werden.

#### Scenario: Grammmenge ändern

- **GIVEN** ein Eintrag enthält 250 kcal und 20 g Protein pro 100 g
- **WHEN** der Nutzer die Menge auf 150 g setzt
- **THEN** berechnet das System 375 kcal und 30 g Protein nach der festgelegten Rundungsregel

#### Scenario: Produkt ohne Energieangabe

- **GIVEN** ein externer Treffer enthält keine verwertbare Kilokalorienangabe
- **WHEN** der Nutzer ihn übernehmen möchte
- **THEN** fordert die Anwendung eine gültige manuelle Energieangabe oder verweigert das Speichern und erfindet keinen Wert

### Requirement: Einträge bearbeiten, verschieben und löschen

Ein Nutzer SHALL eigene Ernährungseinträge bearbeiten, zwischen Mahlzeiten verschieben, neu anordnen und löschen können. Jede Änderung MUST die aktuelle Basisversion prüfen; eine Löschung MUST über den Sync als Tombstone übertragen werden.

#### Scenario: Eintrag zu Snacks verschieben

- **GIVEN** ein eigener Eintrag befindet sich unter Mittagessen
- **WHEN** der Nutzer ihn zu Snacks verschiebt
- **THEN** ändern sich Mahlzeitenzuordnung und Summen atomar, ohne einen zweiten Eintrag zu erzeugen

#### Scenario: Veraltete Bearbeitung

- **GIVEN** ein Eintrag wurde seit dem lokalen Laden auf dem aktiven Gerät verändert
- **WHEN** eine Änderung mit veralteter Basisversion synchronisiert wird
- **THEN** lehnt der Server sie als sichtbaren Konflikt ab und überschreibt keinen Stand still

### Requirement: Manuelle und wiederverwendbare Lebensmittel

Die Anwendung MUST einen manuellen Eintrag mit frei benanntem Lebensmittel und validierten Nährwerten ermöglichen. Sie SHALL zuletzt beziehungsweise häufig verwendete eigene Snapshots lokal anbieten, ohne dafür eine externe Suche auszulösen oder Daten anderer Nutzer einzubeziehen.

#### Scenario: Produkt fehlt extern

- **GIVEN** Barcode-Lookup und Produktsuche liefern keinen geeigneten Treffer
- **WHEN** der Nutzer Name, Menge und Kilokalorien manuell eingibt
- **THEN** kann er den Eintrag ohne Open-Food-Facts-Abhängigkeit speichern und später wiederverwenden

#### Scenario: Zuletzt verwendetes Lebensmittel offline wählen

- **GIVEN** ein eigener früherer Snapshot ist lokal vorhanden und das Gerät ist offline
- **WHEN** der Nutzer ihn erneut auswählt und die Menge ändert
- **THEN** wird ein neuer lokaler Ernährungseintrag mit eigenem Snapshot und Outbox-Mutation angelegt

### Requirement: Mahlzeiten- und Tagessummen

Das System MUST Kilokalorien und vorhandene Makros pro Mahlzeit und Tag deterministisch aus den eigenen Ernährungseinträgen summieren. Für Analytics SHALL an einem Tag mit mindestens einem Ernährungseintrag die Tagebuchsumme gelten; andernfalls darf der vorhandene manuelle Check-in-Tageswert als Legacy-Fallback dienen. Beide Quellen DÜRFEN niemals addiert und als eine Tagesaufnahme ausgegeben werden.

#### Scenario: Tagebuchsumme statt manuellem Legacy-Wert

- **GIVEN** ein Tag besitzt Ernährungseinträge und zusätzlich einen älteren manuellen Kalorienwert im Check-in
- **WHEN** Dashboard oder Coach die Tagesernährung abfragt
- **THEN** verwendet das System nachvollziehbar die Tagebuchsumme und addiert den manuellen Wert nicht hinzu

#### Scenario: Tag ohne Mahlzeiteneinträge

- **GIVEN** ein Tag besitzt keine Ernährungseinträge, aber einen manuellen Check-in-Wert
- **WHEN** die Ernährungskennzahl berechnet wird
- **THEN** bleibt der manuelle Wert als Legacy-Fallback verfügbar und wird als solche Quelle gekennzeichnet

### Requirement: Offline-Erfassung und idempotenter Sync

Die PWA MUST lokal verfügbare Ernährungstage und eigene Lebensmittel-Snapshots offline anzeigen. Anlegen, Bearbeiten, Verschieben und Löschen MUST jeweils atomar mit stabiler Mutation-ID in der kontogetrennten IndexedDB-Outbox gespeichert und idempotent synchronisiert werden. Externe Produktsuche und Barcode-Lookup MUST offline eindeutig als nicht verfügbar gelten.

#### Scenario: Frühstück offline erfassen

- **GIVEN** das Gerät ist offline und ein zuletzt verwendetes Lebensmittel ist lokal verfügbar
- **WHEN** der Nutzer es zum Frühstück hinzufügt
- **THEN** erscheinen Eintrag und neue Summen sofort lokal und bleiben nach Reload bis zum späteren Sync erhalten

#### Scenario: Sitzung läuft vor Upload ab

- **GIVEN** Ernährungsmutationen warten in der Outbox und die Sitzung läuft ab
- **WHEN** die PWA synchronisieren möchte
- **THEN** bleiben sie dem ursprünglichen Konto zugeordnet, werden nicht gesendet und erst nach dessen erneuter Anmeldung fortgesetzt

#### Scenario: Verlorene Bestätigung

- **GIVEN** der Server hat eine Ernährungsmutation gespeichert, aber die Bestätigung geht verloren
- **WHEN** derselbe Request mit derselben Mutation-ID erneut eintrifft
- **THEN** bestätigt der Server denselben Stand und erzeugt weder doppelten Eintrag noch doppelte Tagessumme

### Requirement: Nutzerisolation

Listen, Details, Mutationen, Summen, zuletzt verwendete Lebensmittel, Sync-Changes, Analytics und AI-Fakten MUST ausschließlich an den authentifizierten Nutzer gebunden sein. Eine übermittelte UserId DARF die serverseitige Zuordnung nicht bestimmen.

#### Scenario: Fremden Ernährungstag adressieren

- **GIVEN** Nutzer A kennt eine Eintrags-ID von Nutzer B
- **WHEN** Nutzer A sie liest, ändert oder löscht
- **THEN** behandelt das Backend sie wie eine nicht vorhandene Ressource und verändert keine Daten von Nutzer B

