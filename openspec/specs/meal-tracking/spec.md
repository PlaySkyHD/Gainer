# meal-tracking Specification

## Purpose
Offline-first Ernährungstagebuch mit vier Mahlzeiten und Nährwert-Snapshots je Eintrag, Stückzahlen, Salz und Ballaststoffen, Tages- und Durchschnittswerten und dem gemeinsamen Hinzufügen-Sheet.

## Requirements

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

#### Scenario: Ersten Eintrag löschen

- **GIVEN** unter Frühstück liegen drei Einträge auf den Positionen 0, 1 und 2
- **WHEN** der Nutzer den ersten löscht und die übrigen auf 0 und 1 nachrücken
- **THEN** übernimmt der Server den Stand mit denselben Eintrags-IDs und meldet keinen Konflikt

#### Scenario: Einträge umsortieren

- **GIVEN** zwei Einträge einer Mahlzeit tauschen ihre Positionen oder ein neuer Eintrag kommt an Position 0
- **WHEN** der Tag synchronisiert wird
- **THEN** speichert der Server die neue Reihenfolge atomar und meldet keinen Konflikt

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

Die App MUST lokal verfügbare Ernährungstage und eigene Lebensmittel-Snapshots offline anzeigen. Anlegen, Bearbeiten, Verschieben und Löschen MUST jeweils atomar mit stabiler Mutation-ID in der kontogetrennten lokalen Datenbank und Outbox gespeichert und idempotent synchronisiert werden. Die lokale BLS-Suche MUST offline funktionieren; Produktsuche und Barcode-Lookup bei Open Food Facts MUST offline eindeutig als nicht verfügbar gelten.

#### Scenario: Frühstück offline erfassen
- **GIVEN** das Gerät ist offline und ein zuletzt verwendetes Lebensmittel ist lokal verfügbar
- **WHEN** der Nutzer es zum Frühstück hinzufügt
- **THEN** erscheinen Eintrag und neue Summen sofort lokal und bleiben nach einem Neustart der App bis zum späteren Sync erhalten

#### Scenario: Sitzung läuft vor Upload ab
- **GIVEN** Ernährungsmutationen warten in der Outbox und die Sitzung läuft ab
- **WHEN** die App synchronisieren möchte
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

### Requirement: Menge in Stück

Der Nutzer SHALL die Menge eines Lebensmittels mit bekanntem Stückgewicht als Anzahl eingeben können. Die App SHALL die Grammzahl als Anzahl × Stückgewicht berechnen und den Eintrag in der Liste mit der Anzahl anzeigen. Ein Stückgewicht SHALL aus Open Food Facts, der KI-Schätzung, der manuellen Eingabe oder einem früheren Eintrag stammen können.

#### Scenario: Vier Eier
- **GIVEN** „Ei, gekocht“ mit 50 g pro Stück in „Zuletzt verwendet“
- **WHEN** der Nutzer bei „Anzahl“ 4 wählt und das Ei antippt
- **THEN** entsteht ein Eintrag mit 200 g, und die Liste zeigt „4 Stk · 310 kcal“

#### Scenario: Manuell mit Stückgewicht
- **GIVEN** das manuelle Formular
- **WHEN** der Nutzer „Gewicht pro Stück“ 50 g und „Anzahl“ 4 eingibt
- **THEN** steht bei „Menge“ 200 g, und beim nächsten Mal kennt „Zuletzt verwendet“ das Stückgewicht

#### Scenario: Kein Stückgewicht bekannt
- **GIVEN** ein Lebensmittel ohne Stückgewicht
- **WHEN** der Nutzer eine Anzahl wählt und es antippt
- **THEN** zeigt die App „Für … ist kein Stückgewicht bekannt. Gib die Menge in g ein.“ und speichert nichts

### Requirement: Stückzahl passt zur Menge

Server und App MUST einen Eintrag ablehnen, dessen Grammzahl nicht Stückzahl × Stückgewicht entspricht, und eine Stückzahl ohne Stückgewicht. Bei der KI-Schätzung SHALL eine unpassende Stückangabe verworfen werden, die Schätzung in Gramm bleibt erhalten.

#### Scenario: KI zählt Eier
- **GIVEN** die Beschreibung „4 Eier“
- **WHEN** die KI 4 Stück zu je 55 g und 220 g liefert
- **THEN** zeigt der Vorschlag „4 Stk · 220 g · …“

### Requirement: Salz je Eintrag und Tag

Einträge und Gerichtsbestandteile SHALL optional Salz in Gramm pro 100 g speichern. Das System SHALL Salz mit der Menge skalieren und zur Tagessumme addieren. Einträge ohne Salzangabe MUST NOT als 0 g zählen, sondern bleiben leer.

#### Scenario: Brot mit Salzangabe
- **GIVEN** ein Brot mit 1,25 g Salz pro 100 g
- **WHEN** der Nutzer 50 g einträgt
- **THEN** zählt der Eintrag 0,63 g Salz zur Tagessumme

#### Scenario: Eintrag ohne Salz
- **GIVEN** ein Apfel ohne Salzangabe und ein Brot mit 0,63 g Salz
- **WHEN** die Tagessumme berechnet wird
- **THEN** beträgt sie 0,63 g Salz

### Requirement: Selbst gesalzen

Der Nutzer SHALL Salz, das er selbst ans Essen gibt, als eigenen Eintrag einer Mahlzeit oder als Bestandteil eines Gerichts hinzufügen können: per Schnellwahl (Prise 0,5 g, halber Teelöffel 3 g, Teelöffel 6 g) oder mit eigener Menge. Dieser Eintrag MUST 0 kcal haben und nur zum Salz des Tages zählen. Einträge mit 0 kcal SHALL dafür allgemein gültig sein.

#### Scenario: Hähnchen mit Reis und Gemüse, selbst gewürzt
- **GIVEN** das Mittagessen enthält Hähnchen, Reis und Gemüse
- **WHEN** der Nutzer unter „Hinzufügen“ für Mittag „Salz hinzufügen“ wählt und „Teelöffel“ übernimmt
- **THEN** enthält das Mittagessen einen Eintrag „Salz 6 g · 0 kcal“, und das Salz des Tages steigt um 6 g

### Requirement: Ballaststoffe je Eintrag und Tag

Einträge, Tagesvorlagen-Einträge und Gerichtsbestandteile SHALL optional Ballaststoffe in Gramm pro 100 g speichern. Das System SHALL Ballaststoffe mit der Menge skalieren und zur Tagessumme addieren. Einträge ohne Angabe MUST NOT als 0 g zählen, sondern bleiben leer. Werte unter 0 g oder über 100 g pro 100 g MUST abgelehnt werden.

#### Scenario: Haferflocken mit Angabe
- **GIVEN** Haferflocken mit 10 g Ballaststoffen pro 100 g
- **WHEN** der Nutzer 80 g einträgt
- **THEN** zählt der Eintrag 8 g Ballaststoffe zur Tagessumme

#### Scenario: Eintrag ohne Angabe
- **GIVEN** ein Eintrag ohne Ballaststoffangabe und Haferflocken mit 8 g Ballaststoffen
- **WHEN** die Tagessumme berechnet wird
- **THEN** beträgt sie 8 g Ballaststoffe

#### Scenario: Ungültiger Wert
- **GIVEN** das manuelle Formular
- **WHEN** der Nutzer 120 g Ballaststoffe pro 100 g eingibt
- **THEN** wird der Eintrag nicht gespeichert und das Feld zeigt einen Fehler

#### Scenario: Gericht übernimmt Ballaststoffe
- **GIVEN** ein Gericht mit einem Bestandteil von 6 g Ballaststoffen pro 100 g und 200 g Standardportion
- **WHEN** der Nutzer das Gericht mit Faktor 1 zu einem Tag hinzufügt
- **THEN** enthält der neue Eintrag 12 g Ballaststoffe

### Requirement: Ballaststoffe in Durchschnitten, Übersicht und Coach

Durchschnitte SHALL Ballaststoffe über Tage mit Angabe mitteln. Die Übersicht SHALL Ballaststoffe wie die Tageskarte zeigen. Das Coach-Tool `get_nutrition_summary` SHALL Ballaststoffe nur aus Daten des angemeldeten Nutzers ausgeben.

#### Scenario: Durchschnitt über Tage mit Angabe
- **GIVEN** sieben erfasste Tage, davon drei mit 20, 25 und 30 g Ballaststoffen und vier ohne Angabe
- **WHEN** der Nutzer die 7-Tage-Durchschnitte öffnet
- **THEN** zeigt die Zeile „Ballaststoffe“ 25 g

#### Scenario: Nutzerisolation im Coach
- **GIVEN** Nutzer A und Nutzer B mit unterschiedlichen Ballaststoffwerten
- **WHEN** Nutzer A den Coach nach seinen Ballaststoffen fragt
- **THEN** enthält die Tool-Antwort nur die Werte von Nutzer A

### Requirement: Kompatibilität mit älteren Apps

Der Server SHALL Sync-Payloads ohne Ballaststofffelder annehmen und die Werte leer lassen. Die App SHALL Ballaststoffe nur senden, wenn ein Wert gesetzt ist.

#### Scenario: Alte App sendet Eintrag
- **GIVEN** eine App-Version ohne Ballaststoffe
- **WHEN** sie einen Tag mit einem Eintrag synchronisiert
- **THEN** speichert der Server den Eintrag mit leeren Ballaststoffen und meldet keinen Konflikt

### Requirement: Durchschnitt aus lokalen Tagen

Die App SHALL für die letzten 7 und 30 Kalendertage Ø Kalorien, Protein, Kohlenhydrate und Fett je erfasstem Tag aus den lokalen Ernährungstagen berechnen, ohne Netzwerk. Tage ohne Einträge MUST NOT als 0 kcal zählen. Heute MUST nur zählen, wenn es Einträge hat; sonst endet das Fenster gestern.

#### Scenario: Arbeitsbeispiel 7 Tage
- **GIVEN** heute ist der 19.10.2026 mit 1.900 kcal (Protein 130 g, Kohlenhydrate 200 g, Fett 60 g); erfasst sind außerdem 13.10. mit 2.000 kcal (120/250/70), 14.10. mit 2.300 (150/260/80), 15.10. mit 2.530 (160/300/90) und 17.10. mit 2.070 (140/230/70); 16.10. und 18.10. sind leer
- **WHEN** der Nutzer „7 Tage“ wählt
- **THEN** zeigt die App „Ø 2.160 kcal“ (10.800 / 5), „5 von 7 Tagen erfasst“, Protein 140 g (700 / 5), Kohlenhydrate 248 g (1.240 / 5), Fett 74 g (370 / 5)

#### Scenario: Heute ohne Einträge
- **GIVEN** dieselben Daten, aber heute hat keinen Eintrag
- **WHEN** der Nutzer „7 Tage“ wählt
- **THEN** reicht das Fenster vom 12.10. bis 18.10., „4 von 7 Tagen erfasst“, Ø 2.225 kcal (8.900 / 4)

#### Scenario: 30 Tage
- **GIVEN** zusätzlich der 1.10. mit 3.000 kcal
- **WHEN** der Nutzer „30 Tage“ wählt
- **THEN** zählt der 1.10. mit und es sind „6 von 30 Tagen erfasst“

### Requirement: Zielvergleich

Gilt ein Zielplan, SHALL die App das Kalorienziel des jeweiligen Tages verwenden und die erfassten Tage mit |kcal − Ziel| ≤ 10 % des Ziels als „im Zielbereich“ zählen (Grenze inklusive). Ohne Zielplan MUST der Vergleich ausgeblendet sein.

#### Scenario: Grenzen im Arbeitsbeispiel
- **GIVEN** das Ziel 2.300 kcal und das Arbeitsbeispiel 7 Tage
- **WHEN** die App vergleicht
- **THEN** zeigt sie „Ziel Ø 2.300 kcal“ und „3 von 5 Tagen im Zielbereich ±10 %“ (2.300 exakt, 2.530 = +10 % und 2.070 = −10 % zählen; 2.000 und 1.900 nicht)

#### Scenario: Zielwechsel im Zeitraum
- **GIVEN** Ziel 2.000 kcal bis 15.10. und 2.500 kcal ab 16.10.; erfasst sind 15.10. und 16.10. je mit 2.000 kcal
- **WHEN** die App vergleicht
- **THEN** ist Ø Ziel 2.250 kcal und 1 von 2 Tagen im Zielbereich

### Requirement: Einstieg und Ansicht

Der Tab „Essen“ SHALL unter der Tageskarte eine Zeile „Durchschnitt“ mit Kurzwerten zeigen, die das Sheet „Durchschnitt“ mit Umschalter 7 Tage / 30 Tage öffnet. Ohne Einträge MUST die Zeile „Noch keine Einträge“ zeigen und nichts öffnen. Das Diagramm MUST leere Tage ohne Balken darstellen und beschriften.

#### Scenario: Leerer Zustand
- **GIVEN** keine Einträge in den letzten 30 Tagen
- **WHEN** der Nutzer den Tab „Essen“ öffnet
- **THEN** zeigt die Zeile „Noch keine Einträge“ ohne Pfeil

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

### Requirement: Wassermenge pro Tag

Das System SHALL pro Nutzer und lokalem Kalendertag höchstens eine getrunkene Wassermenge in ganzen Millilitern speichern. Die Menge MUST zwischen 0 und 10.000 ml liegen. „Menge hinzufügen“ MUST mindestens 1 ml addieren und DARF die Obergrenze nicht überschreiten. „Tagesmenge setzen“ SHALL jeden Wert von 0 bis 10.000 ml erlauben. Beide Änderungen MUST die Basisversion prüfen und die Version erhöhen. Ein Tag mit 0 ml SHALL als Stand erhalten bleiben.

#### Scenario: Erstes Glas des Tages

- **GIVEN** für den 25.10.2026 ist noch keine Wassermenge gespeichert
- **WHEN** der Nutzer 300 ml hinzufügt
- **THEN** speichert das System für diesen Tag 300 ml mit Version 1

#### Scenario: Weitere Menge hinzufügen

- **GIVEN** für den Tag sind 1.250 ml mit Version 3 gespeichert
- **WHEN** eine Mutation mit Basisversion 3 weitere 500 ml hinzufügt
- **THEN** beträgt die Tagesmenge 1.750 ml mit Version 4

#### Scenario: Obergrenze

- **GIVEN** für den Tag sind 9.800 ml gespeichert
- **WHEN** eine Mutation 300 ml hinzufügen oder die Menge auf 10.001 ml setzen will
- **THEN** lehnt der Server sie als ungültig ab und die Menge bleibt 9.800 ml

#### Scenario: Auf 0 ml zurücksetzen

- **GIVEN** für den Tag sind 800 ml gespeichert
- **WHEN** der Nutzer die Tagesmenge auf 0 ml setzt
- **THEN** speichert das System 0 ml als neue Version und überträgt keinen Löschvorgang

#### Scenario: Veraltete Basisversion

- **GIVEN** die Wassermenge des Tages hat auf dem Server Version 4
- **WHEN** eine Mutation mit Basisversion 3 eintrifft
- **THEN** antwortet der Server mit `stale_base_version` und ändert die Menge nicht

### Requirement: Wassermenge synchronisieren

Die App MUST jede Änderung der Wassermenge atomar mit Mutation-ID in der Outbox des Kontos speichern und offline sofort anzeigen. Wartet eine ungesendete Änderung, SHALL sie die neue Summe senden statt einer Differenz. Der Server MUST jede Änderung mit Snapshot im Change-Feed veröffentlichen, damit sie im Datenexport erscheint. Fremde Daten DÜRFEN weder lesbar noch änderbar sein.

#### Scenario: Offline mehrfach tippen

- **GIVEN** das Gerät ist offline und für heute sind 0 ml gespeichert
- **WHEN** der Nutzer nacheinander „+500 ml“, „+500 ml“ und „+300 ml“ tippt
- **THEN** zeigt die Karte sofort 1.300 ml, es wartet genau eine Änderung für den Tag, und nach dem Sync speichert der Server 1.300 ml

#### Scenario: Fremden Tag adressieren

- **GIVEN** Nutzer A kennt die ID der Wassermenge von Nutzer B
- **WHEN** Nutzer A für diese ID Wasser hinzufügt
- **THEN** behandelt der Server sie wie eine nicht vorhandene Ressource und die Menge von Nutzer B bleibt unverändert

#### Scenario: Datenexport

- **GIVEN** der Nutzer hat für zwei Tage Wasser erfasst
- **WHEN** er seine Daten exportiert
- **THEN** enthält der Export beide Tage als Ressource `WaterIntakeDay` mit ihrer aktuellen Menge

### Requirement: Wasser-Karte im Ernährungstag

Ist „Wasser erfassen“ eingeschaltet, SHALL der Ernährungstag unter der Tageskarte eine Karte „Wasser“ mit „Menge / Ziel ml“ in deutscher Zahlenformatierung, einem Fortschrittsbalken und den Schnellknöpfen „+200 ml“, „+300 ml“ und „+500 ml“ zeigen. Ein Schnellknopf, der die Obergrenze überschreiten würde, MUST deaktiviert sein. Antippen der Menge SHALL ein Sheet öffnen, in dem der Nutzer die Tagesmenge korrigieren oder auf 0 ml zurücksetzen kann. Bei Textgröße 2 DARF nichts überlaufen.

#### Scenario: Schnellknopf

- **GIVEN** „Wasser erfassen“ ist an, das Ziel ist 2.500 ml und heute sind 750 ml erfasst
- **WHEN** der Nutzer „+500 ml“ tippt
- **THEN** zeigt die Karte „1.250 / 2.500 ml“

#### Scenario: Korrigieren

- **GIVEN** die Karte zeigt „1.300 / 2.500 ml“
- **WHEN** der Nutzer die Menge antippt, 800 eingibt und sichert
- **THEN** schließt das Sheet und die Karte zeigt „800 / 2.500 ml“

#### Scenario: Ungültige Eingabe

- **GIVEN** das Sheet „Wasser“ ist offen
- **WHEN** der Nutzer 12000 eingibt
- **THEN** zeigt das Feld „Erlaubt sind 0 bis 10.000 ml.“, „Sichern“ ist gesperrt und nichts wird gespeichert

#### Scenario: Grenze erreicht

- **GIVEN** heute sind 9.800 ml erfasst
- **WHEN** der Nutzer die Karte ansieht
- **THEN** sind „+300 ml“ und „+500 ml“ deaktiviert und „+200 ml“ ist verfügbar, weil es genau 10.000 ml ergibt

### Requirement: Wasser in den Ernährungs-Einstellungen

Das Menü (…) der Ernährung SHALL den Eintrag „Einstellungen“ anbieten. Dort SHALL der Schalter „Wasser erfassen“ stehen, standardmäßig aus, und bei eingeschaltetem Schalter das Tagesziel in ml zwischen 250 und 10.000, standardmäßig 2.500 ml. Die Einstellungen MUST gerätelokal und an das angemeldete Konto gebunden gespeichert werden und DÜRFEN keine Sync-Mutation erzeugen. Ausschalten SHALL nur die Karte ausblenden und gespeicherte Mengen erhalten.

#### Scenario: Standard

- **GIVEN** ein Nutzer hat die Ernährungs-Einstellungen nie geöffnet
- **WHEN** er den Ernährungstag öffnet
- **THEN** ist keine Wasser-Karte zu sehen

#### Scenario: Einschalten mit eigenem Ziel

- **GIVEN** die Ernährungs-Einstellungen sind offen
- **WHEN** der Nutzer „Wasser erfassen“ einschaltet und als Tagesziel 3000 eingibt
- **THEN** zeigt der Ernährungstag die Karte mit „0 / 3.000 ml“

#### Scenario: Anderes Konto

- **GIVEN** Nutzer A hat auf dem Gerät „Wasser erfassen“ eingeschaltet
- **WHEN** sich Nutzer B auf demselben Gerät anmeldet
- **THEN** ist für Nutzer B die Wasser-Karte ausgeblendet
