# meal-tracking

## MODIFIED Requirements

### Requirement: Einträge bearbeiten, verschieben und löschen

Ein Nutzer SHALL eigene Ernährungseinträge bearbeiten, zwischen Mahlzeiten verschieben, neu anordnen und löschen können. Jede Änderung MUST die aktuelle Basisversion prüfen; eine Löschung MUST über den Sync als Tombstone übertragen werden.

#### Scenario: Eintrag zu Snacks verschieben

- **GIVEN** ein eigener Eintrag befindet sich unter Mittagessen
- **WHEN** der Nutzer ihn zu Snacks verschiebt
- **THEN** ändern sich Mahlzeitenzuordnung und Summen atomar, ohne einen zweiten Eintrag zu erzeugen

#### Scenario: Veraltete Bearbeitung

- **GIVEN** ein Eintrag wurde seit dem lokalen Laden auf dem aktiven Gerät verändert
- **WHEN** eine Änderung mit veralteter Basisversion synchronisiert wird
- **THEN** lehnt der Server sie als sichtbaren Konflikt ab und überschreibt keinen Stand still

#### Scenario: Ersten Eintrag löschen

- **GIVEN** unter Frühstück liegen drei Einträge auf den Positionen 0, 1 und 2
- **WHEN** der Nutzer den ersten löscht und die übrigen auf 0 und 1 nachrücken
- **THEN** übernimmt der Server den Stand mit denselben Eintrags-IDs und meldet keinen Konflikt

#### Scenario: Einträge umsortieren

- **GIVEN** zwei Einträge einer Mahlzeit tauschen ihre Positionen oder ein neuer Eintrag kommt an Position 0
- **WHEN** der Tag synchronisiert wird
- **THEN** speichert der Server die neue Reihenfolge atomar und meldet keinen Konflikt
