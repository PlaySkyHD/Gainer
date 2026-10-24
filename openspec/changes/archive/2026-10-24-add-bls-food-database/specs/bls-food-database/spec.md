# bls-food-database

## ADDED Requirements

### Requirement: Mitgelieferter BLS-Katalog

Die App SHALL einen Auszug des BLS 4.0 mit Code, Name sowie kcal, Eiweiß, Kohlenhydraten, Fett, Ballaststoffen und Salz pro 100 g mitliefern. Unbekannte Werte MUST leer bleiben und MUST NOT als 0 gespeichert werden. Der Generator MUST abbrechen, wenn Spaltenköpfe oder Zeilenzahl nicht dem BLS 4.0 entsprechen.

#### Scenario: Wert mit Spurenangabe
- **GIVEN** ein BLS-Lebensmittel mit `TR` als Fettwert
- **WHEN** der Generator das Asset erzeugt
- **THEN** ist der Fettwert dieses Lebensmittels leer

#### Scenario: Geänderte Quelldatei
- **GIVEN** eine Quelldatei, in der Spalte `V` nicht mit „FIBT“ beginnt
- **WHEN** der Generator läuft
- **THEN** bricht er mit einem Fehler ab und schreibt kein Asset

### Requirement: Lokale Suche nach allgemeinen Lebensmitteln

Die Suche SHALL BLS-Treffer lokal und ohne Internet liefern, ab 2 Zeichen während der Eingabe. Sie SHALL Umlaute, Plural, einen Tippfehler bei Wörtern ab 5 Buchstaben und zusammengesetzte Wörter berücksichtigen. Kurze Anfragewörter unter 3 Buchstaben MUST NOT innerhalb eines Wortes treffen. Es SHALL höchstens 20 Treffer geben.

#### Scenario: Zusammengesetztes Wort
- **GIVEN** der BLS enthält „Hafer Flocken“
- **WHEN** der Nutzer „Haferflocken“ eingibt
- **THEN** steht „Hafer Flocken“ unter den ersten drei Treffern

#### Scenario: Kurzes Wort
- **GIVEN** der BLS enthält „Hühnerei roh“ und „Reis poliert, roh“
- **WHEN** der Nutzer „Ei“ eingibt
- **THEN** enthalten die Treffer „Hühnerei roh“ und nicht „Reis poliert, roh“

#### Scenario: Wortanfang schlägt Wortinneres
- **GIVEN** der BLS enthält „Reis poliert, roh“ und „Erdbeereis“
- **WHEN** der Nutzer „Reis“ eingibt
- **THEN** steht „Reis poliert, roh“ vor „Erdbeereis“

#### Scenario: Umlaut als ae und zusammengesetztes Wort
- **GIVEN** der BLS enthält „Hähnchen Brust, ohne Haut, roh“
- **WHEN** der Nutzer „Haehnchenbrust“ eingibt
- **THEN** steht „Hähnchen Brust, ohne Haut, roh“ unter den Treffern

#### Scenario: Ein Tippfehler
- **GIVEN** der BLS enthält „Banane roh“
- **WHEN** der Nutzer „Bananne“ eingibt
- **THEN** steht „Banane roh“ unter den ersten drei Treffern

#### Scenario: Ohne Internet
- **GIVEN** die App hat keine Online-Anbindung
- **WHEN** der Nutzer „Banane“ eingibt
- **THEN** zeigt die Gruppe „Lebensmittel (BLS)“ „Banane roh“, und statt der Produktgruppe steht „Produktsuche braucht Internet.“

### Requirement: Übernahme eines BLS-Treffers

Ein BLS-Treffer SHALL wie andere Treffer mit Menge übernommen werden. Der Eintrag SHALL die Herkunft „BLS 4.0“, Basis 100 g und die Werte des Katalogs als Snapshot speichern und danach unter „Zuletzt“ erscheinen. Ein späterer Katalogstand MUST NOT bestehende Einträge ändern.

#### Scenario: Haferflocken eintragen
- **GIVEN** „Hafer Flocken“ mit 348 kcal und 10,98 g Ballaststoffen pro 100 g im Katalog
- **WHEN** der Nutzer 50 g zum Frühstück hinzufügt
- **THEN** enthält das Frühstück einen Eintrag „Hafer Flocken · 50 g · 174 kcal“ mit 5,5 g Ballaststoffen und Herkunft „BLS 4.0“

#### Scenario: Sync eines BLS-Eintrags
- **GIVEN** ein BLS-Eintrag wurde offline angelegt
- **WHEN** das Gerät wieder online ist und synchronisiert
- **THEN** speichert der Server den Eintrag mit Herkunft „BLS 4.0“ ohne Barcode, und ein erneutes Senden desselben Outbox-Eintrags erzeugt kein Duplikat

### Requirement: Quellenangabe

Die App SHALL an jedem BLS-Treffer die Herkunft „BLS 4.0“ anzeigen und im Kontobereich eine Seite „Lizenzen“ anbieten. Sie SHALL Quelle, Version, DOI, Lizenz CC BY 4.0 und den Hinweis auf den gerundeten Auszug nennen.

#### Scenario: Lizenzen
- **GIVEN** der Nutzer öffnet im Kontobereich „Lizenzen“
- **WHEN** er den Eintrag zum BLS ansieht
- **THEN** steht dort „Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0“ mit DOI und „CC BY 4.0“
