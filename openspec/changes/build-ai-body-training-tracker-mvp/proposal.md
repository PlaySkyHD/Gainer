## Why

Training, Körpergewicht und Ernährung werden heute oft in getrennten Apps oder Notizen erfasst. Dadurch fehlt eine verlässliche Sicht darauf, ob sich Gewicht und Leistung passend zum gewählten Ziel entwickeln und welche nächsten Schritte aus den eigenen Daten ableitbar sind.

Der erste MVP soll diese Kernreise in einer privaten, installierbaren Anwendung zusammenführen: Ziel festlegen, tägliche Werte erfassen, Training planen und protokollieren, Fortschritt verstehen und eine vorsichtige KI-Zusammenfassung erhalten. Die Anwendung wird zunächst selbst betrieben und kann ausgewählten Kollegen per Einladung bereitgestellt werden. Jeder Nutzer darf ausschließlich seine eigenen Daten in der Anwendung sehen.

## What Changes

- Eine installierbare, responsive Offline-first-PWA und ein zugehöriges ASP.NET-Core-Backend werden als neue Anwendung aufgebaut.
- Nutzerkonten werden ausschließlich eingeladen oder administrativ angelegt. Es gibt keine öffentliche Registrierung und keine fachliche Admin-Ansicht auf Fitnessdaten anderer Nutzer.
- Nutzer können ein Körperziel (Aufbau, Halten oder Abnehmen) führen und tägliche Check-ins mit Körpergewicht sowie optionalen Ernährungswerten erfassen und korrigieren.
- Nutzer können Übungen verwalten, Trainingsvorlagen und Rotationen erstellen sowie Trainingseinheiten inklusive Sätzen, Wiederholungen, Gewicht, Notizen und Pausentimer protokollieren. Abgeschlossene Einheiten bleiben als unveränderliche historische Momentaufnahme erhalten.
- Die Kernreise funktioniert ohne Netzverbindung. Lokale Änderungen werden nachvollziehbar und idempotent mit dem Server synchronisiert; der aktuelle Synchronisationszustand und behebbare Konflikte werden sichtbar gemacht.
- Fortschrittskennzahlen für Gewicht, Ernährung und Kraft werden deterministisch aus strukturierten Daten berechnet. Die KI formuliert daraus verständliche, zurückhaltende Zusammenfassungen und darf nur freigegebene, nutzergebundene Leseoperationen verwenden.
- Der Betrieb wird für einen einzelnen Linux-VPS vorbereitet: PostgreSQL bleibt intern erreichbar, HTTPS terminiert vor der Anwendung, Secrets liegen außerhalb des Quellcodes und Backups werden außerhalb des Servers abgelegt. .NET Aspire beschreibt und beobachtet die lokale Entwicklungs-Topologie; die Produktionsausführung erfolgt containerisiert, ohne den Aspire AppHost als Produktions-Runtime vorauszusetzen.

### Non-Goals

- Öffentliche Registrierung, Bezahlung, soziale Funktionen, Coaching anderer Nutzer, Datenfreigaben und Impersonation
- Ende-zu-Ende- beziehungsweise Zero-Knowledge-Verschlüsselung; der Betreiber behält den technisch notwendigen Zugriff auf Datenbank und Backups, erhält aber keine Ansicht dafür in der Anwendung
- Automatische Kalorien- oder Trainingsentscheidungen, medizinische Beratung oder Diagnosen
- Dokument-Upload, semantische Suche, RAG und `pgvector`; diese Funktionen werden erst nach der strukturierten Kernreise bewertet
- Garantierte Hintergrundsynchronisation auf iOS, vollständige konfliktfreie Mehrgerätebearbeitung sowie native App-Store-Apps
- Wearables, HealthKit/Health Connect, Community-Funktionen und lizenzpflichtige Übungsmedien

### Security and Privacy

- Jede nutzerbezogene Entität wird serverseitig an die authentifizierte Nutzer-ID gebunden; eine vom Client oder vom KI-Modell gelieferte Nutzer-ID ist niemals maßgeblich.
- Autorisierungs- und Integrationstests mit mindestens zwei Nutzern müssen Cross-User-Zugriffe auf Lesen, Schreiben und Synchronisieren verhindern.
- Die OpenAI-Integration läuft ausschließlich serverseitig, übermittelt nur die für die konkrete Antwort erforderlichen Daten, verwendet keine freien SQL-Werkzeuge und speichert Prompts oder Antworten nicht in normalen Anwendungslogs. API-Anfragen werden mit deaktivierter Speicherung ausgeführt.
- Sensible Konfiguration, Datenbank, Backups und Transportwege werden für den privaten VPS-Betrieb abgesichert. Es wird nicht behauptet, dass der Betreiber die Rohdaten technisch nicht einsehen könne.

### Breaking Changes

Keine. Das Vorhaben ist eine Greenfield-Anwendung ohne bestehende öffentliche Verträge oder persistierte Produktionsdaten.

## Capabilities

### New Capabilities

- `private-user-access`: Einladung beziehungsweise administrative Kontoanlage, Anmeldung, Sitzungsverwaltung und strikte Isolation aller fachlichen Daten pro Nutzer.
- `body-goal-tracking`: Verwaltung eines aktiven Körperziels sowie tägliche Gewichts- und optionale Ernährungs-Check-ins mit validierten Korrekturen.
- `exercise-and-plan-management`: Eigener Übungskatalog, Trainingsvorlagen und eine einfache Rotation als Grundlage geplanter Einheiten.
- `workout-execution`: Offline-taugliche Durchführung von Einheiten mit Satzprotokoll, vorherigen Leistungen, Pausentimer und unveränderlicher Trainingshistorie.
- `offline-data-sync`: Lokale Speicherung, Outbox-basierte idempotente Synchronisation, Löschmarkierungen, Revisionsfortschritt sowie verständlicher Sync- und Konfliktstatus.
- `progress-insights`: Deterministisch berechnete Trends für Körpergewicht, Ernährung und Kraft mit klarer Behandlung fehlender oder unzureichender Daten.
- `ai-progress-coach`: OpenAI-gestützte, rein lesende Fortschrittszusammenfassung auf Basis freigegebener Kennzahlen und Daten des angemeldeten Nutzers.

### Modified Capabilities

Keine; es bestehen noch keine Basisspezifikationen.

## Impact

- Neue Frontend-Anwendung auf Basis von Next.js, React und TypeScript als PWA mit IndexedDB-basierter lokaler Datenhaltung.
- Neue modular-monolithische ASP.NET-Core-Anwendung auf .NET 10 mit EF Core/Npgsql, klar getrennten Domänenmodulen und HTTP-/Synchronisationsverträgen.
- Neues PostgreSQL-Schema für Identität, Ziele, Check-ins, Übungen, Pläne, Trainingseinheiten, Synchronisationsmetadaten und KI-Nutzungsmetadaten.
- Neue serverseitige OpenAI-Responses-API-Integration mit strukturierten, schreibgeschützten Werkzeugen und deaktivierter Anbieter-Speicherung.
- Neue Aspire-Projekte für lokale Orchestrierung, Service Discovery, Health Checks und OpenTelemetry sowie Container- und Reverse-Proxy-Konfiguration für einen einzelnen Linux-VPS.
- Neue automatisierte Tests für Domänenregeln, API-Verträge, Offline-Synchronisation und insbesondere die Isolation zweier Nutzer; zusätzlich reale PWA-Tests auf einem iPhone.
