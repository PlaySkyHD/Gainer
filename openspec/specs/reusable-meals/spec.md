# reusable-meals Specification

## Purpose
Nutzergebundene Gerichte aus mehreren Nährwertbestandteilen, die als unabhängige Kopien in einen Ernährungstag übernommen werden.

## Requirements

### Requirement: Nutzergebundene Gerichte verwalten

Die App MUST Gerichte mit stabiler ID, Name, optionaler Beschreibung, positiver Standardportion und mindestens einer geordneten Komponente verwalten. Jede Komponente MUST Name, positive Menge, Kilokalorien und optionale nichtnegative Makros als Snapshot besitzen. Nutzer SHALL eigene Gerichte anlegen, bearbeiten und archivieren können. Archivierte Gerichte DÜRFEN nicht mehr angeboten werden, bleiben aber in bereits erzeugten Einträgen ohne Rückwirkung auflösbar.

#### Scenario: Gericht aus vorhandenen Lebensmitteln erstellen

- **GIVEN** ein Nutzer wählt eigene Snapshots für Reis, Hähnchen und Gemüse
- **WHEN** er daraus ein gültiges Gericht „Chicken Rice Bowl“ speichert
- **THEN** wird ein ausschließlich für ihn verfügbares Gericht mit stabiler ID und der gewählten Komponentenreihenfolge angelegt

#### Scenario: Ungültige Komponente speichern

- **GIVEN** eine Gerichtskomponente enthält keine positive Menge oder negative Kilokalorien
- **WHEN** der Nutzer das Gericht speichert
- **THEN** lehnt die Anwendung die Änderung mit feldbezogener Fehlermeldung ab und erhält den letzten gültigen Stand

#### Scenario: Gericht archivieren

- **GIVEN** ein Gericht wurde bereits an früheren Ernährungstagen verwendet
- **WHEN** der Nutzer es archiviert
- **THEN** verschwindet es aus der normalen Auswahl und alle zuvor kopierten Ernährungseinträge bleiben unverändert erhalten

### Requirement: Gerichte unabhängig vom Ernährungstag pflegen

Die Anwendung MUST im Ernährungsbereich eine eigenständige Gerichtebibliothek bereitstellen, die ohne Öffnen eines Lebensmittel-Hinzufügen-Dialogs erreichbar ist. Dort MUST der Nutzer aktive und archivierte eigene Gerichte anzeigen, neue Gerichte anlegen sowie bestehende Gerichte bearbeiten, duplizieren und archivieren können. Der Hinzufügen-Dialog eines Ernährungstags MUST dieselben aktiven Gerichtsvorlagen verwenden, DARF aber nicht der einzige Zugang zur Pflege sein.

#### Scenario: Gericht ohne geöffneten Ernährungstag anlegen

- **GIVEN** ein Nutzer befindet sich in der eigenständigen Gerichtebibliothek
- **WHEN** er ein gültiges Gericht mit mehreren Komponenten speichert
- **THEN** erscheint es unmittelbar in seiner Bibliothek und steht anschließend in der Gerichteauswahl eines Ernährungstags zur Verfügung

#### Scenario: Gericht duplizieren

- **GIVEN** ein Nutzer besitzt das Gericht „Chicken Rice Bowl“
- **WHEN** er es in der Gerichtebibliothek dupliziert
- **THEN** entsteht ein neues eigenes Gericht mit neuer stabiler ID und unabhängigen Komponenten-Snapshots, das vor dem Speichern bearbeitet werden kann

#### Scenario: Archivierte Gerichte verwalten

- **GIVEN** ein Nutzer hat ein Gericht archiviert
- **WHEN** er in der Gerichtebibliothek archivierte Gerichte einblendet
- **THEN** kann er dessen gespeicherte Komponenten weiterhin ansehen, während das Gericht in keinem Ernährungstag neu angeboten wird

#### Scenario: Komponenten umsortieren oder entfernen

- **GIVEN** ein Gericht hat drei Komponenten
- **WHEN** der Nutzer die erste entfernt oder zwei Komponenten tauscht und speichert
- **THEN** übernimmt der Server den Stand mit denselben Komponenten-IDs und meldet keinen Konflikt

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
- **THEN** werden sie als getrennte, geordnete Komponentenzeilen in den Gerichtsentwurf übernommen und weder ein Nutrition Day noch ein persistierter AI-Entwurf erzeugt

#### Scenario: Online-Erfassungsweg ist offline nicht verfügbar

- **GIVEN** der Nutzer bearbeitet ein Gericht ohne Netzwerkverbindung
- **WHEN** er den gemeinsamen Hinzufügen-Dialog öffnet
- **THEN** kennzeichnet die Anwendung Suche, Barcode-Auflösung und AI-Schätzung als online erforderlich und lässt `Zuletzt`, lokal verfügbare Snapshots sowie manuelle Erfassung weiterhin verwenden

### Requirement: Erfassung und Speicherziel getrennt

Das Sheet MUST Erfassung und Speicherziel trennen: Derselbe geprüfte Entwurf wird je nach Aufrufer Ernährungseintrag einer Mahlzeit oder Komponente eines Gerichts. Quellenmetadaten dürfen als Snapshot gespeichert werden, DÜRFEN aber keine Live-Abhängigkeit zu Open Food Facts, früheren Einträgen oder KI-Entwürfen erzeugen. Abbrechen oder ein Fehler MUST den Gerichtsentwurf unverändert lassen.

#### Scenario: Hinzufügen wird abgebrochen

- **GIVEN** ein Gerichtsentwurf enthält bereits mehrere Komponenten
- **WHEN** der Nutzer den Hinzufügen-Dialog ohne Bestätigung schließt oder eine Übernahme fehlschlägt
- **THEN** bleibt der Gerichtsentwurf unverändert und es entstehen weder teilweise Komponenten noch Fach- oder Sync-Daten

### Requirement: Gericht als atomare Deep Copy hinzufügen

Beim Hinzufügen eines Gerichts MUST der Nutzer Zieltag, eine der vier Mahlzeiten und einen positiven Portionsfaktor wählen können. Die Anwendung MUST jede Gerichtskomponente deterministisch skalieren und mit neuer stabiler ID als selbständigen Nutrition-Entry-Snapshot in die gewählte Mahlzeit kopieren. Es DARF keine Live-Referenz vom Ernährungstag zum Gericht entstehen; die gesamte Übernahme MUST lokal atomar mit der Outbox-Mutation des Ernährungstags gespeichert werden.

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
- **THEN** bleibt der gestrige Nutrition-Entry-Snapshot unverändert und nur zukünftige Übernahmen verwenden die neue Menge

#### Scenario: Kopierte Komponente anpassen

- **GIVEN** ein Gericht wurde mit drei Komponenten zum Frühstück hinzugefügt
- **WHEN** der Nutzer nur die kopierte Obstmenge für diesen Tag ändert
- **THEN** ändern sich ausschließlich dieser Eintrag und die Tagessumme; die Gerichtsvorlage bleibt unverändert

### Requirement: Offline-Verfügbarkeit und Synchronisation von Gerichten

Die App MUST zuletzt synchronisierte eigene Gerichte offline anzeigen und anwendbar machen. Anlegen, Bearbeiten und Archivieren MUST atomar mit stabiler Mutation-ID in der kontogetrennten lokalen Datenbank und Outbox gespeichert und idempotent synchronisiert werden. Konflikte MUST sichtbar bleiben; eine abgelaufene Sitzung MUST den Upload bis zur erneuten Anmeldung desselben Nutzers aussetzen.

#### Scenario: Gericht offline anlegen und verwenden
- **GIVEN** das Gerät ist offline und die benötigten Lebensmittel-Snapshots sind lokal vorhanden
- **WHEN** der Nutzer ein Gericht anlegt und zu Mittagessen hinzufügt
- **THEN** erscheinen Vorlage und kopierte Einträge sofort lokal, überstehen einen Neustart der App und warten mit getrennten stabilen Mutationen auf Sync

#### Scenario: Sitzung läuft vor dem Sync ab
- **GIVEN** ein neues Gericht und seine Verwendung warten in der Outbox und die Sitzung ist abgelaufen
- **WHEN** die Synchronisation startet
- **THEN** bleiben beide dem ursprünglichen Konto zugeordnet, werden nicht unter einem anderen Konto angezeigt und erst nach dessen erneuter Anmeldung übertragen

#### Scenario: Veraltete Gerichtsversion
- **GIVEN** dieselbe Gerichtsvorlage wurde seit dem lokalen Laden auf einem anderen Gerät verändert
- **WHEN** eine Mutation mit veralteter Basisversion synchronisiert wird
- **THEN** lehnt der Server sie als sichtbaren Konflikt ohne Teiländerung ab und verändert bereits kopierte Ernährungseinträge nicht

### Requirement: Strikte Nutzerisolation

Listen, Details, Mutationen, lokale Caches, Sync-Changes und Gerichtübernahmen MUST ausschließlich an die authentifizierte Nutzer-ID gebunden sein. Eine UserId aus Request oder lokalem Snapshot DARF die serverseitige Zuordnung nicht bestimmen.

#### Scenario: Fremdes Gericht adressieren

- **GIVEN** Nutzer A kennt die Gericht-ID von Nutzer B
- **WHEN** Nutzer A das Gericht liest, bearbeitet, archiviert oder zu einem Ernährungstag hinzufügt
- **THEN** behandelt das Backend es wie eine nicht vorhandene Ressource, legt keine Einträge an und offenbart keine Komponenten
