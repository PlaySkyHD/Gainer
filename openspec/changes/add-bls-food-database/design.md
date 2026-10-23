# Design

## D1 Datenquelle und Lizenz

- **Quelle:** Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0, https://doi.org/10.25826/Data20251217-134202-0, Download über blsdb.de. Lizenz CC BY 4.0.
- **Generator:** `apps/mobile/tool/extract_bls.py <BLS_4_0_2025_DE.zip>` liest `BLS_4_0_Daten_2025_DE.xlsx` nur mit `zipfile` und `xml.etree`.
  - Er prüft die Spaltenköpfe: `A` BLS Code, `B` Lebensmittelbezeichnung, `G` ENERCC (kcal), `M` PROT625, `P` FAT, `S` CHO, `V` FIBT, `DQ` NACL. Weicht ein Kopf ab, bricht er ab.
  - Er erwartet genau 7.140 Zeilen.
  - `-`, leer, `TR` und Werte mit `<` werden `null`. Unbekannt bleibt so von 0 getrennt.
  - Zahlen werden auf zwei Nachkommastellen gerundet.
- **Format:** ein JSON-Objekt mit `source`, `url`, `license`, `version`, `fields` und `foods` als Liste von Arrays `[code, name, kcal, protein, carbs, fat, fiber, salt]`. Etwa 545 KB (komprimiert 176 KB), als Asset mitgeliefert.
- Das ZIP wird nicht eingecheckt, nur das erzeugte Asset.
- **Abdeckung im BLS 4.0:** kcal und Salz bei allen 7.140 Lebensmitteln, Ballaststoffe bei 7.087, Eiweiß bei 7.117, Fett bei 7.112, Kohlenhydrate bei allen.
- **Namensnennung:**
  - An jedem Treffer steht die Herkunft „BLS 4.0“.
  - Der Kontobereich (`mobile_shell.dart`, Gruppe „Weitere Bereiche“) erhält eine Zeile „Lizenzen“. Sie öffnet eine eigene Cupertino-Seite, weil Flutters Lizenzseite Material-Lokalisierungen braucht, die die App nicht lädt. Dort steht neben Open Food Facts der vollständige Quellentext mit Lizenz, DOI und dem Hinweis „Auszug: sechs Nährwerte, auf zwei Nachkommastellen gerundet“.
  - Es gibt keinen Hinweis, der eine Billigung durch das Max Rubner-Institut nahelegt.

## D2 Ort: in der App, nicht auf dem Server

Der Katalog liegt als Asset in der App.
- Gainer ist Offline-first, und die Suche nach allgemeinen Lebensmitteln soll ohne Netz funktionieren.
- Ergebnisse beim Tippen brauchen lokale Antwortzeiten.
- Es ändert sich kein API-Vertrag, und der Server wird nicht belastet.

Geladen wird bei der ersten Suche einmal pro App-Start. Das Parsen läuft in einem Isolate (`compute`), danach liegt ein Suchindex im Speicher.

## D3 Suchlogik

Die Suchlogik liegt in einer reinen Dart-Klasse ohne Flutter-Abhängigkeit, damit sie per Unit-Test prüfbar ist.

**Normalisierung** gilt für Namen und Anfrage gleich:
- Kleinschreibung, `ß` → `ss`.
- `ä/ö/ü` → `a/o/u`. Getippte `ae/oe/ue` werden ebenso gefaltet.
- Alles außer Buchstaben und Ziffern trennt Wörter.

**Varianten:** Ein Anfragewort gilt zusätzlich ohne die Endungen `en`, `n`, `s` oder `e`, wenn danach mindestens 4 Buchstaben bleiben.

**Treffer pro Wort im Namen:**

| Art | Punkte |
| --- | --- |
| ganzes Wort | 4 |
| Wortende („ei“ in „huhnerei“) | 3 |
| Wortanfang | 2 |
| im Wort | 1 |

- Treffer im ersten Wort des Namens erhalten +1.
- Varianten mit weniger als 3 Buchstaben zählen nur als ganzes Wort oder Wortende. So findet „Ei“ nicht „Reis“.

**Tippfehler:** Wörter ab 5 Buchstaben dürfen genau eine Abweichung (Levenshtein ≤ 1) zu einem Wort des Katalogs haben, wenn sie sonst nichts finden.

**Zusammengesetzte Wörter:**
- Findet ein Anfragewort nichts direkt, wird es in Wörter des Katalogs mit je mindestens 3 Buchstaben zerlegt („haferflocken“ → hafer + flocken).
- Ein Name muss alle Teile enthalten.
- Der letzte Teil, das Grundwort, zählt doppelt.

**Rangfolge:**
1. Anzahl getroffener Anfragewörter.
2. Punkte.
3. Kürzerer Name.

Es werden höchstens 20 Treffer angezeigt. Treffen nicht alle Anfragewörter, steht über der Gruppe „Teiltreffer“.

**Leistung:** Eine Suche über 7.140 Namen dauert auf dem Gerät unter 50 ms. Bei Bedarf wird ein Wortindex aufgebaut; ein Test sichert die Grenze im Debug-Modus mit Spielraum ab.

## D4 Oberfläche

- Das Suchfeld heißt „Lebensmittel, Produkt oder Marke“.
- **Lebensmittel (BLS):**
  - Ab 2 Zeichen nach kurzer Verzögerung (150 ms).
  - Zeile: Name, darunter „BLS 4.0 · 343 kcal / 100 g“.
- **Produkte (Open Food Facts):**
  - Erscheint erst nach dem Absenden, wie bisher. Absenden zeigt auch die BLS-Treffer sofort.
  - Ohne Online-Anbindung steht statt der Gruppe der Hinweis „Produktsuche braucht Internet.“ Scheitert die Produktsuche am Netz, lautet der Fehler „Die Produktsuche braucht Internet. Lebensmittel aus dem BLS findest du auch offline.“
  - Eine neue Eingabe verwirft ältere Produkttreffer, weil sie nicht mehr zur Eingabe passen.
- Ein Treffer öffnet wie heute die Mengeneingabe. Werte und Herkunft sind dieselben wie bei anderen Treffern.
- Leere BLS-Gruppe: keine eigene Meldung, solange Open Food Facts noch kommen kann.

## D5 Speicherung

Ein BLS-Eintrag ist ein normaler Eintrag.

| Feld | Wert |
| --- | --- |
| `ProductName` | BLS-Name |
| `Brand` | leer |
| `Provider` | „BLS 4.0“ |
| `Barcode` | leer |
| `RetrievedAtUtc` | leer |
| `BasisGrams` | 100 |
| Werte | pro 100 g aus dem Katalog, inklusive Ballaststoffe und Salz |

- Fehlende Makros bleiben leer.
- Der Eintrag ist ein Snapshot. Ein späteres App-Update mit neuem Katalog ändert bestehende Einträge nicht.
- „Zuletzt“ dedupliziert wie bisher über Name, Marke und Barcode.
- **Fehlende kcal:** Laut Abdeckung haben alle BLS-Lebensmittel kcal. Fehlt sie trotzdem, wird das Lebensmittel nicht im Asset aufgenommen; der Generator meldet die Anzahl.
