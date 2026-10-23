# Proposal

## Why

Die Suche findet heute nur Produkte aus Open Food Facts. Das klappt bei Markenartikeln mit Barcode, aber schlecht bei allgemeinen Lebensmitteln wie „Reis gekocht“, „Hähnchenbrust“ oder „Banane“. Treffer sind dort oft Einzelprodukte mit lückenhaften Werten. Außerdem braucht die Suche Internet und startet erst nach dem Absenden.

Der Bundeslebensmittelschlüssel (BLS) 4.0 des Max Rubner-Instituts enthält 7.140 allgemeine Lebensmittel mit geprüften Nährwerten pro 100 g. Er steht unter CC BY 4.0 und darf mit Quellenangabe in der App mitgeliefert werden.

## What Changes

- Die App liefert einen **Auszug des BLS 4.0** als Asset mit: Code, Name, kcal, Eiweiß, Kohlenhydrate, Fett, Ballaststoffe und Salz pro 100 g. Komprimiert sind das etwa 180 KB.
- Die **Suche** unter „Hinzufügen“ zeigt zwei Gruppen:
  - **Lebensmittel (BLS):** lokal, schon beim Tippen, auch ohne Internet.
  - **Produkte (Open Food Facts):** wie bisher nach dem Absenden und nur online.
- Eine **deutsche Suchlogik** für den BLS findet Treffer trotz Umlauten, Plural, einem Tippfehler und zusammengesetzten Wörtern. „Haferflocken“ findet „Hafer Flocken“, „Ei“ findet „Hühnerei roh“, aber nicht „Reis“.
- Ein BLS-Treffer wird wie ein Open-Food-Facts-Treffer mit Menge übernommen. Der Eintrag trägt die Herkunft „BLS 4.0“ und erscheint danach unter „Zuletzt“.
- Die App nennt die Quelle am Treffer („BLS“) und vollständig auf einer neuen Seite „Lizenzen“ im Kontobereich. Die App hat bisher keine solche Seite.

### Non-Goals

- Kein BLS auf dem Server und keine Nutzung durch die KI-Schätzung. Das kann später folgen, wenn sich der lokale Katalog bewährt.
- Keine Mikronährstoffe, kein Zucker, keine englischen Namen.
- Keine Synonymliste über die Normalisierung hinaus.
- Keine automatische Umrechnung zwischen roh und gekocht; der BLS-Name nennt den Zustand.
- Keine Aktualisierung des Katalogs ohne App-Update.

## Capabilities

- **Neu:** `bls-food-database`.

## Einordnung

Private Kernjourney Ernährung. Setzt `add-fiber-tracking` voraus, damit Ballaststoffe aus dem BLS gespeichert werden können.

## Impact

- **App:**
  - Asset `assets/food/bls_4_0.json` und Generator `tool/extract_bls.py` (nur Python-Standardbibliothek, wie `generate_timer_sounds.py`).
  - Neuer lokaler Katalog mit Suche in `data/repositories/nutrition`.
  - `NutritionRepository.searchFoods` trennt lokale und Online-Suche; die Suche ist offline nicht mehr komplett gesperrt.
  - Suche im Hinzufügen-Sheet, Zeile „Lizenzen“ im Kontobereich.
- **Backend:** keine Änderung. Einträge mit Herkunft „BLS 4.0“ laufen über den bestehenden Sync; `Provider` ist ein freies Feld.
- **Dependencies:** keine neuen Pakete.
- **Lizenz:** CC BY 4.0 ist laut `deploy/THIRD_PARTY_POLICY.md` erlaubt. `THIRD_PARTY_NOTICES.md` und die Policy erhalten einen Abschnitt zum BLS.
- **Security:** keine Auswirkung. Der Katalog ist statisch, enthält keine Nutzerdaten, und Suchbegriffe verlassen für den BLS das Gerät nicht.
- **Breaking Changes:** keine. Ältere App-Versionen zeigen BLS-Einträge aus dem Sync wie jeden anderen Eintrag.
