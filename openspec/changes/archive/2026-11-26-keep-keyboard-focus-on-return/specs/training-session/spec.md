## MODIFIED Requirements

### Requirement: Zahleneingabe mit Navigationsleiste

Darüber bleibt die kompakte Timerleiste sichtbar. Kehrt die App nach dem Sperren oder einem App-Wechsel zurück, MUST das zuvor fokussierte Feld den Fokus behalten, wenn beim Verlassen die Tastatur offen war; sonst MUST kein Feld den Fokus haben.

#### Scenario: Durch Sätze navigieren
- **GIVEN** das Wdh.-Feld von Satz 1 ist fokussiert und 6 ist eingetragen
- **WHEN** der Nutzer „weiter“ tippt
- **THEN** wird das Kg-Feld von Satz 2 fokussiert und der Wert 6 ist gespeichert

#### Scenario: Rückkehr mit offener Tastatur
- **GIVEN** das Kg-Feld von Satz 1 ist fokussiert und die Tastatur ist offen
- **WHEN** der Nutzer das iPhone sperrt und über die Live Activity zurückkehrt
- **THEN** hat das Kg-Feld weiter den Fokus und die Leiste mit dem Button zum Ausblenden der Tastatur ist sichtbar

#### Scenario: Rückkehr ohne offene Tastatur
- **GIVEN** ein Zahlenfeld hat den Fokus, die Tastatur ist aber nicht sichtbar
- **WHEN** die App zurückkehrt
- **THEN** hat kein Feld den Fokus und iOS blendet keine Tastatur ein
