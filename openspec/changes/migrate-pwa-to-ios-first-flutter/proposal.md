## Why

Gainer soll seine bestehende Offline-First-Kernreise als Flutter-App auf dem iPhone anbieten und native Apple-Funktionen für Training und Erfassung nutzen. Die PWA bleibt während des kontrollierten Übergangs verfügbar; Android folgt nach der iOS-Abnahme.

## What Changes

- Neues Flutter-Frontend unter `apps/mobile` mit vollständiger fachlicher Parität zu den aktiven PWA-Changes: Zugang/Einladungen/Operator, Körpertracking, Trainingsplanung, Workout/Historie/Timer, Ernährung einschließlich Smart Meals und Labelscan, Fortschritt und lesender Coach.
- Native, kontoisolierte Persistenz mit transaktionaler Outbox und unverändertem Sync-Protokoll v2; überprüfbarer PWA-zu-App-Übergang ohne Verlust ausstehender Änderungen.
- iOS zuerst: Systemtypografie, Cupertino-Navigation, Zurück-Geste, Safe Areas, Haptik, VoiceOver, große Schrift und reduzierte Bewegung.
- Native Kamera/Barcode, Fotoauswahl, Keychain-Sitzungsschutz und lokale Pausentimer-Benachrichtigungen.
- Verbindlich für den ersten iOS-Release: HealthKit (geprüfter Gewichtsimport und expliziter Workout-Export), WidgetKit (Trainingseinstieg), ActivityKit (Workout/Pausentimer) und App Intents (Shortcuts zum Öffnen zentraler Journeys). Nutzung und Berechtigungen sind freiwillig.
- iOS-Build-/Geräteprüfungen und private Beta-Verteilung vorbereiten. Android erhält anschließend eigene Plattformadapter und Abnahme; es blockiert den iOS-Release nicht.
- **BREAKING für bereits migrierte Konten:** Nach der ersten erfolgreichen abgesicherten Übergabe wird direkte Writer-Übernahme über den bisherigen `takeOverWriting=true`-Pfad dauerhaft verweigert; weiterer Gerätewechsel benötigt Handover. Alte PWA-Versionen müssen vor einer Rückübernahme aktualisiert werden. Für noch nicht migrierte Konten bleibt das bestehende Verhalten erhalten. HTTP-Vertragsformen bleiben kompatibel, der neue Fehlerzustand wird dokumentiert. Native App und PWA teilen keinen lokalen Speicher.

## Capabilities

### New Capabilities

- `native-mobile-client`: Fachliche Parität, native Session-/API-Anbindung, Apple-Design und Plattformpriorität.
- `native-offline-migration`: Kontoisolierte native Persistenz, Sync-Parität und kontrollierter Wechsel des Hauptgeräts.
- `apple-native-training`: Kamera, Fotoauswahl, Haptik, Pausentimer, Live Activities, Widgets und Shortcuts.
- `apple-health-integration`: Freiwilliger, kontrollierter HealthKit-Gewichtsimport und Workout-Export.
- `mobile-quality-release`: Reproduzierbare Toolchain, unabhängige Qualitätsprüfungen, private iOS-Beta und nachrangige Android-Abnahme.

### Modified Capabilities

Keine archivierten Main-Specs vorhanden. Die neuen Capabilities ergänzen die bestehenden, noch aktiven Changes, ohne deren Anforderungen umzuschreiben. Überschneidungen und noch offene Akzeptanzaufgaben werden im Design als Abhängigkeiten geführt.

## Impact

- Frontend: neues `apps/mobile`; begrenzte Übergangshilfe in `apps/web`; spätere Anpassung von README, OpenSpec-Kontext und CI. Bestehende uncommitted Änderungen werden nicht überschrieben.
- APIs: bestehende `/api/v1/auth/*`, Einladungs-/Operator-, Sync-, Ernährungs-, Fortschritts- und Coach-Verträge aus `contracts/openapi/Gainer.Api.json`. Native Cookie-/Antiforgery-Anbindung wird vor Features mit echten API-Tests bewiesen; kein neuer Auth-Token-Endpunkt. Geplant sind additive, authentifizierte `/api/v1/sync/handovers`-Operationen für Beginn, Abschluss und Abbruch einer abgesicherten Geräteübergabe; diese existieren heute noch nicht.
- Backend: ASP.NET Core Identity, Request-Security, SyncClientRegistry/MutationProcessor/ChangeFeed und Verträge bleiben maßgeblich. Ergänzt werden ein temporärer Handover-Datensatz und eine gemeinsam mit Writer-Übernahme und Mutationen serialisierte Übergabesperre. PostgreSQL und der modulare Monolith bleiben bestehen. Keine neue AI-/Analytics-Implementierung im Client.
- Lokale Modelle: Fachdaten, Outbox, Tombstones, Konflikte, Sync-Cursor und historische Snapshots; zusätzlich kontoisolierte HealthKit-Zuordnungen/Exportstatus und minimierte Extension-Snapshots. Keine HealthKit-IDs in bestehende HTTP-Verträge einschleusen.
- Native Targets: Swift-Brücken, Widget-/Live-Activity-Extension, App Groups, HealthKit-Entitlement und passende Berechtigungsbeschreibungen. Abhängigkeiten werden begründet und versioniert.
- Security: Cookies ausschließlich API-hostgebunden und geschützt, keine gespeicherten Passwörter, keine Sitzungstoken in Widgets/App Groups; Berechtigungen bedarfsgerecht, keine sensiblen Daten in Logs. Health-Daten werden nur nach ausdrücklicher Bestätigung zu Gainer-Check-ins und damit in den nutzergebundenen Server-Sync übernommen.
- Non-Goals: öffentliche Registrierung/Veröffentlichung, Bezahlung, Social/Sharing, Watch-App, automatisches Ernährungs-/Kalorienmanagement, automatische HealthKit-Hintergrundimporte, garantierter Hintergrund-Sync, RAG, Backend-Neuschreibung und Flutter-Web-Parität. Veröffentlichung/Uploads sind eigene Freigabeaktionen, keine Wirkung dieses Planungsauftrags.
