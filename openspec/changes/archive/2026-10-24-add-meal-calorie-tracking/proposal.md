## Why

Der bestehende Daily Check-in erlaubt nur manuell eingetragene Tageswerte und macht eine alltagstaugliche Ernährungserfassung unnötig aufwendig. Ein mahlzeitenbezogenes Tagebuch mit Barcode- und Produktsuche über Open Food Facts soll Kalorien und Makros schnell erfassbar machen, ohne die Offline-First- und Nutzerisolationsgarantien der privaten Kernjourney aufzugeben.

## What Changes

- Ergänzt ein Ernährungstagebuch pro lokalem Kalendertag mit den festen Bereichen `Frühstück`, `Mittagessen`, `Abendessen` und `Snacks`.
- Nutzer können Einträge mit Produkt, Menge beziehungsweise Portion, Kilokalorien, Protein, Kohlenhydraten und Fett anlegen, bearbeiten, verschieben und löschen; Tages- und Mahlzeitensummen werden deterministisch berechnet.
- Ergänzt einen serverseitigen, read-only Open-Food-Facts-Adapter für Barcode-Lookup und ausdrücklich abgesendete Produktsuchen. Keine Suche wird bei jedem Tastendruck ausgelöst.
- Speichert bei Übernahme eines externen Produkts einen nutzereigenen Nährwert-Snapshot mit Quelle, Barcode und Abrufzeitpunkt, damit spätere Änderungen bei Open Food Facts historische Einträge nicht rückwirkend verändern.
- Unterstützt manuelle Lebensmittel als Fallback sowie die Wiederverwendung zuletzt beziehungsweise häufig verwendeter eigener Einträge.
- Integriert Ernährungseinträge in IndexedDB, Outbox, idempotenten Sync, Konfliktbehandlung und die bestehenden deterministischen Tages-/Dashboardkennzahlen.
- Kennzeichnet Open-Food-Facts-Daten als externe Community-Daten, die unvollständig oder fehlerhaft sein können, und dokumentiert ODbL- sowie gegebenenfalls CC-BY-SA-Anforderungen.
- Begrenzt und cached externe Abfragen, sendet einen identifizierenden `User-Agent`, behandelt `429`/`503` kontrolliert und hält die lokale Erfassung bei einem Provider-Ausfall funktionsfähig.

### Non-Goals

- Automatische Ernährungsentscheidungen, Kalorienvorgaben, medizinische Bewertung oder Diätberatung
- Schreiben, Korrigieren oder Hochladen von Produkten beziehungsweise Bildern zu Open Food Facts
- Vollständige Restaurantdatenbank, Rezeptverwaltung, Einkaufslisten oder automatische Bilderkennung von Mahlzeiten
- Search-as-you-type gegen Open Food Facts oder massenhafter Import des Gesamtdatenbestands
- Garantierte Richtigkeit oder Vollständigkeit externer Produkt- und Nährwertdaten

### Security and Privacy

- Mahlzeiten, Mengen und Nährwert-Snapshots bleiben strikt an den authentifizierten Nutzer gebunden und werden nicht an Open Food Facts übertragen.
- An Open Food Facts gehen nur die vom Nutzer ausgelöste Suchphrase oder der Barcode sowie technische Request-Metadaten; normale Logs enthalten weder Suchtexte noch Barcodewerte noch persönliche Ernährungseinträge.
- Der Backend-Adapter besitzt ausschließlich Lesezugriff und keine Open-Food-Facts-Schreibzugangsdaten.

### Breaking Changes

Keine. Bestehende Check-ins und optionale manuelle Tageswerte bleiben lesbar. Die neue Mahlzeitensumme wird als nachvollziehbare zusätzliche Quelle eingeführt; eine Migration darf vorhandene Tageswerte nicht still überschreiben.

## Capabilities

### New Capabilities

- `meal-nutrition-tracking`: Nutzergebundenes, offline-first Ernährungstagebuch mit vier Mahlzeiten, Nährwert-Snapshots, Tagesaggregaten und Synchronisation.
- `open-food-facts-catalog`: Begrenzter read-only Produkt- und Barcode-Lookup über Open Food Facts mit Cache, Quellenangabe, Fehlerbehandlung und manueller Alternative.

### Modified Capabilities

Keine bereits synchronisierte Basisspezifikation wird geändert; die Integration in Check-in, Sync und Insights wird innerhalb der neuen Capability-Verträge beschrieben.

## Impact

- Neue PostgreSQL-Entitäten und EF-Migrationen für Ernährungstage, Einträge und unveränderliche Produkt-Snapshots
- Neue typisierte Sync-Mutationen, Change-Snapshots und IndexedDB-Stores für Ernährungseinträge
- Neue ASP.NET-Endpunkte beziehungsweise Query-Ports für Produktsuche, Barcode-Lookup und Ernährungstage
- Neuer gekapselter HTTP-Adapter zu `world.openfoodfacts.org` mit API v3.6 für Produktabrufe, expliziter Suche, Timeout, Cache und Resilience-Regeln
- Erweiterungen an Daily-Check-in-, Dashboard-, Insights- und AI-Faktenprojektionen, ohne numerische Berechnung an OpenAI zu delegieren
- Neue mobile PWA-Ansichten für Tagesnavigation, Mahlzeitenabschnitte, Produktübernahme, Mengenbearbeitung und Tagesfortschritt
- Zusätzliche Unit-, PostgreSQL-, API-, Offline- und Browsertests sowie Lizenz-/Attributionshinweise
- Die Funktion gehört zur privaten Kernjourney; Rezepte, Bilderkennung und weitergehende Ernährungsautomatisierung bleiben spätere Phasen.
