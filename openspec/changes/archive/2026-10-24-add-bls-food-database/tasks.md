# Tasks

Voraussetzung: `add-fiber-tracking` ist gemergt (PR #86).

## 1. Daten

- [x] 1.1 `apps/mobile/tool/extract_bls.py` mit Kopf- und Zeilenprüfung (D1); Asset `assets/food/bls_4_0.json` erzeugen und in `pubspec.yaml` eintragen.
- [x] 1.2 Abschnitt BLS in `THIRD_PARTY_NOTICES.md` und `deploy/THIRD_PARTY_POLICY.md`.

## 2. App

- [x] 2.1 Lokaler Katalog: Laden im Isolate, Modell, Suchlogik (D2, D3); Unit-Tests für alle Szenarien aus der Spec und Leistungsgrenze.
- [x] 2.2 `NutritionRepository`: lokale Suche getrennt von der Online-Suche, offline nicht mehr gesperrt; Übernahme mit Herkunft „BLS 4.0“ (D5); Tests inkl. „Zuletzt“.
- [x] 2.3 Suche im Hinzufügen-Sheet mit zwei Gruppen und Offline-Hinweis (D4); Widget-Tests, Goldens, Vorschau bei Textgröße 1. Die Trefferzeilen sind dieselben wie bei „Zuletzt“.
- [x] 2.4 Zeile „Lizenzen“ im Kontobereich mit eigener Seite für BLS und Open Food Facts (D1); Widget-Test, Golden des Mehr-Menüs.

## 3. Abschluss

- [x] 3.1 `openspec validate add-bls-food-database --strict`, lokal Analyse, Format und Flutter-Tests grün.
- [x] 3.2 CI-Checks im PR grün.
- [x] 3.3 TestFlight; auf dem iPhone online und im Flugmodus suchen und eintragen, danach Sync prüfen.
