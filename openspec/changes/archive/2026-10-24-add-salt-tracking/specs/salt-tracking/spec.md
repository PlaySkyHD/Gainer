# salt-tracking

## ADDED Requirements

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

### Requirement: Salzobergrenze in der Zielphase

Zielphasen SHALL eine Salzobergrenze pro Tag haben. Ohne eigenen Wert SHALL 6 g gelten. Die Tageskarte SHALL „Salz x / y g“ zeigen und den Balken ab der Grenze in Warnfarbe darstellen.

#### Scenario: Standardgrenze
- **GIVEN** eine Zielphase ohne eigene Salzgrenze
- **WHEN** der Tag 4,2 g Salz enthält
- **THEN** zeigt die Tageskarte „Salz 4,2 / 6 g“

#### Scenario: Eigene Grenze
- **GIVEN** der Nutzer setzt in der Zielphase „Salz höchstens 5 g“
- **WHEN** der Tag 5,5 g Salz enthält
- **THEN** zeigt die Tageskarte den Salzbalken in Warnfarbe

### Requirement: Salz aus Barcode, Suche und Etikett

Produkte aus Open Food Facts SHALL Salz pro 100 g mitbringen. Fehlt Salz, SHALL das System Natrium × 2,5 verwenden. Der Etiketten-Scan SHALL Salz oder Natrium ablesen und auf 100 g umrechnen. Fehlendes Salz MUST NOT die Übernahme eines Etiketts verhindern.

#### Scenario: Nur Natrium angegeben
- **GIVEN** ein Etikett mit „Natrium 0,4 g“ pro 100 g
- **WHEN** der Scan ausgewertet wird
- **THEN** zeigt die Prüfung „Salz 1 g“ mit Status `Converted`
