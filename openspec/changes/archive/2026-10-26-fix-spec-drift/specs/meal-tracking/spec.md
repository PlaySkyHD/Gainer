## MODIFIED Requirements

### Requirement: Menge und Nährwerte deterministisch berechnen

Das System MUST bei grammbezogenen Produktdaten die Eintragswerte proportional aus Menge und Nährwerten pro 100 Gramm berechnen und mit einer dokumentierten Rundungsregel speichern. Die Menge MUST positiv und endlich sein, Kilokalorien MUST endlich und nicht negativ sein, denn 0 kcal sind erlaubt (etwa bei „Selbst gesalzen“). Optionale Makros MUST nicht negativ und endlich sein. Produkte mit fehlender verwertbarer Energieangabe DÜRFEN nicht ohne manuelle Ergänzung übernommen werden.

#### Scenario: Grammmenge ändern

- **GIVEN** ein Eintrag enthält 250 kcal und 20 g Protein pro 100 g
- **WHEN** der Nutzer die Menge auf 150 g setzt
- **THEN** berechnet das System 375 kcal und 30 g Protein nach der festgelegten Rundungsregel

#### Scenario: Produkt ohne Energieangabe

- **GIVEN** ein externer Treffer enthält keine verwertbare Kilokalorienangabe
- **WHEN** der Nutzer ihn übernehmen möchte
- **THEN** fordert die Anwendung eine gültige manuelle Energieangabe oder verweigert das Speichern und erfindet keinen Wert
