## MODIFIED Requirements

### Requirement: Gerichtskomponenten über das gemeinsame Hinzufügen-Sheet

Der Gerichtseditor MUST zum Hinzufügen einer Komponente dasselbe Hinzufügen-Sheet mit denselben Wegen wie die Mahlzeiten verwenden, soweit Netz und Gerät sie unterstützen. Ein bestätigtes Ergebnis MUST als unabhängiger Komponenten-Snapshot in den lokalen Gerichtsentwurf übernommen werden und DARF keinen Ernährungstag verändern. Der Nutzer MUST die Komponenten vor dem Speichern einzeln bearbeiten, entfernen und umordnen können.

#### Scenario: Lebensmittel über Suche zum Gericht hinzufügen

- **GIVEN** ein Nutzer bearbeitet ein Gericht in der eigenständigen Gerichtebibliothek
- **WHEN** er den gemeinsamen Hinzufügen-Dialog öffnet, über Open Food Facts ein Lebensmittel auswählt und Menge sowie Nährwerte bestätigt
- **THEN** erscheint das Lebensmittel als eigenständige bearbeitbare Komponentenzeile im Gerichtsentwurf und es wird kein Ernährungstag angelegt oder verändert

#### Scenario: Lebensmittel manuell zum Gericht hinzufügen

- **GIVEN** ein Nutzer bearbeitet ein Gericht und das gewünschte Lebensmittel ist nicht im Katalog vorhanden
- **WHEN** er im gemeinsamen Dialog die manuelle Erfassung wählt und gültige Werte bestätigt
- **THEN** wird daraus genau eine neue Komponentenzeile im Gerichtsentwurf, die vor dem Speichern weiter bearbeitet werden kann

#### Scenario: Mehrteilige AI-Schätzung zum Gericht hinzufügen

- **GIVEN** ein Nutzer startet aus einem Gerichtsentwurf eine AI-Schätzung und erhält mehrere Komponenten
- **WHEN** er ausgewählte Komponenten prüft, korrigiert und ausdrücklich bestätigt
- **THEN** werden sie als getrennte, geordnete Komponentenzeilen in den Gerichtsentwurf übernommen und weder ein Ernährungstag noch ein persistierter AI-Entwurf erzeugt

#### Scenario: Online-Erfassungsweg ist offline nicht verfügbar

- **GIVEN** der Nutzer bearbeitet ein Gericht ohne Netzwerkverbindung
- **WHEN** er den gemeinsamen Hinzufügen-Dialog öffnet
- **THEN** kennzeichnet die Anwendung Suche, Barcode-Auflösung und AI-Schätzung als online erforderlich und lässt `Zuletzt`, lokal verfügbare Snapshots sowie manuelle Erfassung weiterhin verwenden

### Requirement: Gericht als atomare Deep Copy hinzufügen

Beim Hinzufügen eines Gerichts MUST der Nutzer Zieltag, eine der vier Mahlzeiten und einen positiven Portionsfaktor wählen können. Die Anwendung MUST jede Gerichtskomponente deterministisch skalieren und mit neuer stabiler ID als selbständigen Snapshot des Ernährungseintrags in die gewählte Mahlzeit kopieren. Es DARF keine Live-Referenz vom Ernährungstag zum Gericht entstehen; die gesamte Übernahme MUST lokal atomar mit der Outbox-Mutation des Ernährungstags gespeichert werden.

#### Scenario: Gericht mit halber Portion hinzufügen

- **GIVEN** ein Gericht enthält 200 g Reis und 150 g Hähnchen pro Standardportion
- **WHEN** der Nutzer es mit Faktor 0,5 zum Abendessen hinzufügt
- **THEN** entstehen unabhängige Einträge für 100 g Reis und 75 g Hähnchen mit deterministisch skalierten Nährwerten

#### Scenario: Eine Komponente kann nicht gespeichert werden

- **GIVEN** ein Gericht besitzt mehrere gültige Komponenten
- **WHEN** die lokale Transaktion bei einer Komponente oder der Outbox-Mutation fehlschlägt
- **THEN** wird keine Komponente als hinzugefügt angezeigt und der Nutzer kann die komplette Übernahme erneut versuchen

#### Scenario: Derselbe Sync wird wiederholt

- **GIVEN** eine Gerichtübernahme wurde serverseitig bereits als Ernährungstag gespeichert und die Bestätigung ging verloren
- **WHEN** dieselbe Mutation-ID erneut gesendet wird
- **THEN** bestätigt der Server denselben Stand und erzeugt weder doppelte Komponenten noch eine doppelte Tagessumme

### Requirement: Vorlage und eingefügte Einträge bleiben unabhängig

Änderungen an Name, Reihenfolge, Menge oder Nährwerten eines Gerichts DÜRFEN bereits eingefügte oder historische Ernährungseinträge nicht verändern. Umgekehrt DÜRFEN Bearbeiten, Verschieben oder Löschen kopierter Ernährungseinträge das zugrunde liegende Gericht nicht verändern. Eine Aktualisierung des Gerichts aus einem Ernährungstag MUST eine separate, ausdrückliche Aktion sein und ist nicht vorgesehen.

#### Scenario: Gericht nach Verwendung bearbeiten

- **GIVEN** ein Gericht wurde gestern zum Mittagessen hinzugefügt
- **WHEN** der Nutzer heute die Reismenge der Vorlage erhöht
- **THEN** bleibt der gestrige Snapshot des Ernährungseintrags unverändert und nur zukünftige Übernahmen verwenden die neue Menge

#### Scenario: Kopierte Komponente anpassen

- **GIVEN** ein Gericht wurde mit drei Komponenten zum Frühstück hinzugefügt
- **WHEN** der Nutzer nur die kopierte Obstmenge für diesen Tag ändert
- **THEN** ändern sich ausschließlich dieser Eintrag und die Tagessumme; die Gerichtsvorlage bleibt unverändert
