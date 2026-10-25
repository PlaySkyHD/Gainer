## MODIFIED Requirements

### Requirement: Update nötig ohne Datenverlust

Die App MUST bei jeder Registrierung, auch bei der Geräteübergabe, sowie bei Push und Pull dieselbe aktuelle Protokollversion nennen. Unbekannte Ressourcentypen und `upgrade_required` MUST sie als „Bitte App aktualisieren“ melden, ohne Cursor oder lokale Daten zu ändern. Wegen `upgrade_required` angehaltene Einträge SHALL sie nur nach einem App-Update erneut senden.

#### Scenario: Unbekannter Typ in der neuen App

- **GIVEN** der Server liefert einen Ressourcentyp, den die App nicht kennt
- **WHEN** die App den Batch anwenden will
- **THEN** rollt sie ihn zurück, behält den Cursor, zählt die davor angewendeten Batches im Bericht und zeigt „Bitte App aktualisieren“

#### Scenario: Nach dem Update

- **GIVEN** eine ältere App hat offene Einträge wegen `upgrade_required` angehalten
- **WHEN** die aktualisierte App sich erfolgreich mit höherer Protokollversion registriert
- **THEN** sendet sie diese Einträge wieder

#### Scenario: Ohne Update keine Schleife

- **GIVEN** der Server lehnt einen Eintrag beim Push mit `upgrade_required` ab
- **WHEN** dieselbe App-Version erneut synchronisiert
- **THEN** sendet sie den Eintrag nicht erneut, und der Hinweis „Bitte App aktualisieren“ bleibt, bis ein Lauf den Server erfolgreich erreicht

#### Scenario: Gerätewechsel nach dem ersten Wasser

- **GIVEN** auf dem Konto ist Wasser erfasst
- **WHEN** das neue iPhone die Übergabe abschließt
- **THEN** registriert es sich mit der aktuellen Protokollversion, der Server nimmt es an und es wird Schreibgerät
