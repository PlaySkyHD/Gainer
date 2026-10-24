# fiber-tracking

## ADDED Requirements

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

### Requirement: Ballaststoffziel in der Zielphase

Zielphasen SHALL ein Ballaststoffziel pro Tag als Mindestwert haben. Ohne eigenen Wert SHALL 30 g gelten. Das Ziel SHALL für Trainings- und Ruhetage gleich gelten. Die Tageskarte SHALL „Ballaststoffe x / y g“ zeigen. Der Balken MUST NOT eine Warnfarbe verwenden und SHALL ab dem Ziel voll sein.

#### Scenario: Standardziel
- **GIVEN** eine Zielphase ohne eigenes Ballaststoffziel
- **WHEN** der Tag 18 g Ballaststoffe enthält
- **THEN** zeigt die Tageskarte „Ballaststoffe 18 / 30 g“

#### Scenario: Ziel überschritten
- **GIVEN** eine Zielphase mit „Ballaststoffe mindestens 25 g“
- **WHEN** der Tag 34 g Ballaststoffe enthält
- **THEN** zeigt die Tageskarte „Ballaststoffe 34 / 25 g“ mit vollem Balken ohne Warnfarbe

#### Scenario: Bestehende Phase bleibt unverändert
- **GIVEN** eine vor dieser Änderung gespeicherte Zielphase
- **WHEN** der Server sie nach der Migration liest
- **THEN** ist ihr Ballaststoffziel leer, der wirksame Wert 30 g und die Phase gilt beim Abgleich als unverändert

### Requirement: Ballaststoffe aus Barcode, Suche, Etikett und Schätzung

Produkte aus Open Food Facts SHALL Ballaststoffe pro 100 g aus `fiber_100g` mitbringen. Der Etiketten-Scan SHALL gedruckte Ballaststoffe ablesen und auf 100 g umrechnen. Die KI-Schätzung SHALL Ballaststoffe je Bestandteil liefern oder leer lassen. Fehlende Ballaststoffe MUST NOT die Übernahme eines Produkts, Etiketts oder einer Schätzung verhindern.

#### Scenario: Barcode mit Ballaststoffen
- **GIVEN** ein Open-Food-Facts-Produkt mit `fiber_100g` = 6,5
- **WHEN** der Nutzer den Barcode scannt
- **THEN** zeigt der Entwurf 6,5 g Ballaststoffe pro 100 g

#### Scenario: Etikett pro Portion
- **GIVEN** ein Etikett mit „Ballaststoffe 3 g“ pro Portion von 40 g
- **WHEN** der Scan ausgewertet wird
- **THEN** zeigt die Prüfung 7,5 g Ballaststoffe pro 100 g

#### Scenario: Etikett ohne Ballaststoffe
- **GIVEN** ein Etikett ohne Ballaststoffangabe mit vollständigen kcal und Makros
- **WHEN** der Scan ausgewertet wird
- **THEN** kann der Nutzer den Entwurf bestätigen und Ballaststoffe bleiben leer

#### Scenario: Schätzung mit Ballaststoffen
- **GIVEN** die Beschreibung „Linsensuppe, ein Teller“
- **WHEN** die KI-Schätzung zurückkommt
- **THEN** zeigt jeder Bestandteil mit Schätzwert „~x g Ballaststoffe“ und Bestandteile ohne Wert zeigen keine Ballaststoffe

### Requirement: Ballaststoffe in Durchschnitten, Kalender und Coach

Durchschnitte SHALL Ballaststoffe über Tage mit Angabe mitteln. Der Kalender SHALL Ballaststoffe wie die Tageskarte zeigen. Das Coach-Tool `get_nutrition_summary` SHALL Ballaststoffe nur aus Daten des angemeldeten Nutzers ausgeben.

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
