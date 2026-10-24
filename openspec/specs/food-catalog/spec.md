# food-catalog Specification

## Purpose
Lebensmittelquellen für das Ernährungstagebuch: mitgelieferter BLS-Auszug für die lokale Suche, Open Food Facts für Barcode und Produktsuche über den Server und das Lesen von Nährwertetiketten per Foto.

## Requirements

### Requirement: Barcode-Lookup mit manuellem Fallback

Die App SHALL einen Barcode mit der nativen iPhone-Kamera erfassen oder manuell eingeben und online über den Backend-Adapter nachschlagen können. Der Scanner MUST mindestens EAN-8, EAN-13, UPC-A und UPC-E erkennen. Kamera-Zugriff MUST erst nach einer Nutzeraktion angefordert werden; eine verweigerte Berechtigung DARF die manuelle Eingabe nicht blockieren. Nach einem Treffer MUST der Scanner schließen.

#### Scenario: Bekannten Barcode scannen
- **GIVEN** der Nutzer erlaubt den Kamerazugriff und Open Food Facts kennt den gescannten Barcode
- **WHEN** der Scan abgeschlossen ist
- **THEN** schließt der Scanner und die App zeigt einen normalisierten Produktvorschlag mit Quelle und verfügbaren Nährwerten zur ausdrücklichen Übernahme an

#### Scenario: Kamera wird abgelehnt
- **GIVEN** der Nutzer verweigert den Kamerazugriff
- **WHEN** er ein Produkt hinzufügen möchte
- **THEN** bleiben manuelle Barcodeeingabe, Suche und manueller Lebensmitteleintrag verfügbar

#### Scenario: Unbekannter Barcode
- **GIVEN** Open Food Facts liefert für den Barcode kein Produkt
- **WHEN** der Lookup endet
- **THEN** zeigt die App einen Nicht-gefunden-Zustand und bietet einen manuellen Eintrag an, ohne den Barcode zu erfinden oder extern zu schreiben

### Requirement: Bewusst ausgelöste Produktsuche

Die Anwendung SHALL eine textbasierte Produktsuche erst nach ausdrücklichem Absenden eines nicht leeren, begrenzten Suchtexts ausführen. Sie DARF keine externe Search-as-you-type-Abfrage bei jedem Tastendruck senden und MUST Ergebnisse begrenzen und paginieren beziehungsweise gezielt nachladen.

#### Scenario: Produktsuche absenden

- **GIVEN** der Nutzer hat einen gültigen Produkt- oder Markensuchtext eingegeben
- **WHEN** er die Suche ausdrücklich absendet
- **THEN** sendet das Backend höchstens eine begrenzte externe Suchanfrage und liefert eine begrenzte normalisierte Trefferliste

#### Scenario: Schnell wiederholt suchen

- **GIVEN** ein Nutzer oder mehrere Nutzer überschreiten das interne Suchbudget
- **WHEN** eine weitere Suche angefordert wird
- **THEN** antwortet die Anwendung kontrolliert mit Retry-Hinweis oder einem frischen Cachetreffer und riskiert keinen ungebremsten externen Requeststrom

### Requirement: Begrenztes normalisiertes Produktmodell

Der Katalog MUST nur die für das Ernährungstagebuch erforderlichen Felder normalisieren: Barcode, Produktname, optionale Marke, Bezugsmenge beziehungsweise Portion, Kilokalorien, Protein, Kohlenhydrate, Fett, Quelle und Datenqualitätsindikatoren. Fehlende oder nicht numerische Werte MUST als fehlend behandelt und DÜRFEN nicht zu null umgedeutet werden.

#### Scenario: Teilweise vorhandene Makros

- **GIVEN** ein Produkt besitzt Energie und Protein, aber keine Kohlenhydrat- oder Fettangabe
- **WHEN** es angezeigt wird
- **THEN** kennzeichnet die Anwendung die beiden fehlenden Werte und berechnet sie weder aus anderen Feldern noch mit einem Sprachmodell

#### Scenario: Kilojoule und Kilokalorien vorhanden

- **GIVEN** Open Food Facts liefert Energie in mehreren Einheiten
- **WHEN** der Adapter das Produkt normalisiert
- **THEN** verwendet er die explizite Kilokalorienangabe oder eine dokumentierte deterministische Umrechnung und kennzeichnet die Bezugsbasis

### Requirement: Serverseitiger read-only Providerzugriff

Alle Open-Food-Facts-Abfragen MUST über einen gekapselten serverseitigen Read-Adapter mit identifizierendem `User-Agent`, Timeout, begrenzter Antwortgröße und kontrollierter Fehlerabbildung erfolgen. Der Adapter DARF keine Produkte, Bilder oder Korrekturen an Open Food Facts schreiben und SHALL Suchtexte, Barcodes und Ernährungseinträge nicht in normalen Logs speichern.

#### Scenario: Provider ist nicht erreichbar

- **GIVEN** Open Food Facts antwortet nicht, mit `429`, `503` oder ungültigen Daten
- **WHEN** Lookup oder Suche ausgeführt wird
- **THEN** liefert die API einen stabilen temporären Fehlerzustand mit Retry-Möglichkeit und lokale beziehungsweise manuelle Erfassung bleibt nutzbar

#### Scenario: Providerantwort ist zu groß

- **GIVEN** eine externe Antwort überschreitet die konfigurierte Größen- oder Treffergrenze
- **WHEN** der Adapter sie verarbeitet
- **THEN** bricht er kontrolliert ab, gibt keine Teilantwort als vollständig aus und protokolliert keine Payload

### Requirement: Cache und Rate-Limit-schonende Nutzung

Der Backend-Adapter MUST Barcodeergebnisse und begrenzte Suchresultate mit angemessener Ablaufzeit cachen, gleichzeitige identische Requests zusammenfassen und interne Budgets unterhalb der veröffentlichten Providergrenzen erzwingen. Cacheeinträge DÜRFEN keine nutzerbezogenen Ernährungseinträge enthalten.

#### Scenario: Derselbe Barcode wird erneut angefragt

- **GIVEN** ein frischer normalisierter Cacheeintrag existiert
- **WHEN** derselbe Barcode erneut nachgeschlagen wird
- **THEN** liefert das Backend den Cachewert ohne einen weiteren Providerrequest und kennzeichnet dessen Abrufzeitpunkt

#### Scenario: Cache ist abgelaufen und Provider offline

- **GIVEN** nur ein abgelaufener Cachewert existiert und Open Food Facts ist nicht erreichbar
- **WHEN** der Nutzer den Barcode abfragt
- **THEN** darf die Anwendung den alten Wert klar als veraltet anbieten, darf ihn aber nicht als frisch darstellen

### Requirement: Quelle, Qualität und Lizenzhinweis

Die UI MUST Open Food Facts als Quelle benennen, auf mögliche Unvollständigkeit beziehungsweise Fehler hinweisen und die für verwendete Daten und gegebenenfalls Bilder erforderliche Attribution bereitstellen. Die App SHALL keine Produktbilder übernehmen, solange deren CC-BY-SA-Darstellung und Caching nicht umgesetzt sind.

#### Scenario: Externes Produkt anzeigen

- **GIVEN** ein normalisierter Open-Food-Facts-Treffer wird angezeigt
- **WHEN** der Nutzer dessen Details öffnet
- **THEN** sieht er Quelle, Datenstand und einen Hinweis, Nährwerte bei Bedarf mit der Verpackung abzugleichen

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

### Requirement: Nährwerttabelle per Foto lesen

Der Server SHALL ein Foto einer Nährwerttabelle mit dem OpenAI-Bildmodell lesen und kcal, Eiweiß, Kohlenhydrate und Fett pro 100 g als Vorschlag zurückgeben. Das Modell MUST nur gedruckte Werte mit Textbeleg liefern. Die Umrechnung auf 100 g MUST der Server deterministisch vornehmen. Ein Scan MUST NOT etwas speichern; erst die Bestätigung in der App legt einen Eintrag an.

#### Scenario: Etikett pro 100 g
- **GIVEN** ein Foto mit „Energie 1580 kJ / 377 kcal, Eiweiß 13,5 g“ pro 100 g
- **WHEN** die App das Foto an `/nutrition/label-scans` sendet
- **THEN** antwortet der Server mit Bezug `Per100Grams`, 377 kcal und 13,5 g Eiweiß pro 100 g, jeweils mit Status `Confirmed`, und `canConfirm` ist wahr

#### Scenario: Nur Portionswerte
- **GIVEN** ein Etikett mit 120 kcal pro Portion zu 30 g
- **WHEN** der Server das Etikett liest
- **THEN** meldet er 400 kcal pro 100 g mit Status `Converted` und Originalwert 120

#### Scenario: Portion ohne Gewicht
- **GIVEN** ein Etikett nur mit Werten pro Portion und ohne Portionsgewicht
- **WHEN** der Server das Etikett liest
- **THEN** sind die Werte pro 100 g leer und `canConfirm` ist falsch

### Requirement: Unplausible Werte und fehlende Tabelle

Der Server SHALL Werte über 950 kcal oder über 100 g Makro pro 100 g als `Implausible` markieren und `canConfirm` verweigern, wenn kcal fehlt oder die Makrosumme 105 g übersteigt. Zeigt das Foto keine Nährwerttabelle, SHALL der Server 422 mit `no_nutrition_label` antworten, und die App MUST einen verständlichen Hinweis zeigen.

#### Scenario: Fehllesung
- **GIVEN** das Modell liest 3770 kcal pro 100 g
- **WHEN** der Server die Antwort prüft
- **THEN** ist kcal `Implausible` und der Vorschlag kann nicht übernommen werden

#### Scenario: Kein Etikett
- **GIVEN** ein Foto eines Tellers
- **WHEN** die App es scannen lässt
- **THEN** zeigt sie „Auf dem Foto wurde keine Nährwerttabelle erkannt.“

### Requirement: Salz aus Barcode, Suche und Etikett

Produkte aus Open Food Facts SHALL Salz pro 100 g mitbringen. Fehlt Salz, SHALL das System Natrium × 2,5 verwenden. Der Etiketten-Scan SHALL Salz oder Natrium ablesen und auf 100 g umrechnen. Fehlendes Salz MUST NOT die Übernahme eines Etiketts verhindern.

#### Scenario: Nur Natrium angegeben
- **GIVEN** ein Etikett mit „Natrium 0,4 g“ pro 100 g
- **WHEN** der Scan ausgewertet wird
- **THEN** zeigt die Prüfung „Salz 1 g“ mit Status `Converted`

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
