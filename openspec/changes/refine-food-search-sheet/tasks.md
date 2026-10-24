# Tasks

## 1. App

- [x] 1.1 Übernehmen schließt das Sheet bei Erfolg; Zurücksetzen beim Schließen (Suche, Treffer, Menge, Quelle). Widget-Tests.
- [x] 1.2 Mahlzeit-Tabs nur auf der Startseite. Widget-Test.
- [x] 1.3 Eine Trefferliste mit Quelle je Zeile, Filter „Alle · BLS · Produkte“, Schaltfläche „In Open Food Facts suchen“. Widget-Tests, Golden, Vorschau.

- [x] 1.4 „Mehrere hinzufügen“ per langem Drücken auf „Hinzufügen“ und Plus; Sheet bleibt offen, Haken schließt. `GainerSheetHeader.compactTrailing` für den Haken. Widget-Test, Golden.
- [x] 1.5 Startseite in drei Gruppen; Unterseiten beginnen oben. Widget-Test, Golden; `integration_test/ui_design_flow.dart` scrollt zu „Manuell erfassen“.

## 2. Abschluss

- [x] 2.1 `openspec validate refine-food-search-sheet --strict`, lokal Analyse, Format und Flutter-Tests grün.
- [ ] 2.2 CI-Checks im PR grün, TestFlight.
