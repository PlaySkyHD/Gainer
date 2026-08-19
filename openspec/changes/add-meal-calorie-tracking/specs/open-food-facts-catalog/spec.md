## Purpose

Diese Capability stellt einen begrenzten, rein lesenden Lebensmittelkatalog aus Open Food Facts für Barcode-Lookup und bewusst ausgelöste Produktsuchen bereit.

## ADDED Requirements

### Requirement: Barcode-Lookup mit manuellem Fallback

Die Anwendung SHALL einen Barcode per Kamera erfassen oder manuell eingeben und online über den Backend-Adapter nachschlagen können. Kamera-Zugriff MUST erst nach einer Nutzeraktion angefordert werden; eine verweigerte Berechtigung DARF die manuelle Eingabe nicht blockieren.

#### Scenario: Bekannten Barcode scannen

- **GIVEN** der Nutzer erlaubt den Kamerazugriff und Open Food Facts kennt den gescannten Barcode
- **WHEN** der Scan abgeschlossen ist
- **THEN** zeigt die Anwendung einen normalisierten Produktvorschlag mit Quelle und verfügbaren Nährwerten zur ausdrücklichen Übernahme an

#### Scenario: Kamera wird abgelehnt

- **GIVEN** der Nutzer verweigert oder das Gerät unterstützt keinen Kamerazugriff
- **WHEN** er ein Produkt hinzufügen möchte
- **THEN** bleiben manuelle Barcodeeingabe, explizite Produktsuche und manueller Lebensmitteleintrag verfügbar

#### Scenario: Unbekannter Barcode

- **GIVEN** Open Food Facts liefert für den Barcode kein Produkt
- **WHEN** der Lookup endet
- **THEN** zeigt die Anwendung einen Nicht-gefunden-Zustand und bietet einen manuellen Eintrag an, ohne den Barcode zu erfinden oder extern zu schreiben

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

Die UI MUST Open Food Facts als Quelle benennen, auf mögliche Unvollständigkeit beziehungsweise Fehler hinweisen und die für verwendete Daten und gegebenenfalls Bilder erforderliche Attribution bereitstellen. Der erste MVP SHALL keine Produktbilder übernehmen, solange deren CC-BY-SA-Darstellung und Caching nicht vollständig umgesetzt sind.

#### Scenario: Externes Produkt anzeigen

- **GIVEN** ein normalisierter Open-Food-Facts-Treffer wird angezeigt
- **WHEN** der Nutzer dessen Details öffnet
- **THEN** sieht er Quelle, Datenstand und einen Hinweis, Nährwerte bei Bedarf mit der Verpackung abzugleichen

