## Context

Das Vorhaben ist Greenfield; Motivation und fachlicher Umfang stehen in [proposal.md](./proposal.md), die beobachtbaren Verträge in den Delta-Spezifikationen unter [specs](./specs). Die Architektur muss vor allem vier Randbedingungen zusammenbringen: eine auf iPhones brauchbare Offline-PWA, strikt nutzergebundene Daten, einen kleinen selbst betriebenen Linux-VPS und eine KI-Grenze, an der OpenAI nur bereits kontrollierte Daten interpretieren darf.

Der Betreiber stellt Infrastruktur und Datenbank bereit und kann diese technisch administrieren. Die Anwendung bietet ihm trotzdem keinen fachlichen Zugriff auf Fitnessdaten anderer Konten. Das ist ein Autorisierungsversprechen der Anwendung, kein Zero-Knowledge-Modell.

## Goals / Non-Goals

**Goals:**

- Eine lokal gut entwickelbare und als wenige Container reproduzierbar auslieferbare Architektur
- Ein deploybarer ASP.NET-Core-Monolith mit fachlich erkennbaren Modulgrenzen
- IndexedDB als primäre Datenquelle der Tracking-UI und ein verlusttoleranter, testbarer Sync-Vertrag
- Durchgängige Nutzerbindung in API, Datenbankzugriff, Synchronisation, Analytics und KI-Werkzeugen
- Deterministische, versionierte Kennzahlen als gemeinsame Quelle für UI und AI Coach
- Ein sicherer, kostenseitig begrenzbarer OpenAI-Adapter ohne schreibende Werkzeuge
- Nachvollziehbare Migrationen, Health Checks, Telemetrie, Backups und Rollback auf einem VPS

**Non-Goals:**

- Microservices, Message Broker, Redis, separater Analytics-/AI-Worker oder verteilte Transaktionen
- Server Rendering persönlicher Fitnessdaten, Next.js Server Actions oder ein zweites Node-BFF
- PostgreSQL-RLS als MVP-Sicherheitsgrenze; es bleibt eine spätere zusätzliche Härtungsoption
- Automatisches Zusammenführen paralleler Offline-Änderungen mehrerer Geräte
- Kryptografische Absicherung lokaler Browserdaten gegen eine Person mit Zugriff auf das entsperrte Gerät
- Providerseitiger Conversation State, persistente Chat-Historie, RAG, Dokumente, `pgvector` oder OpenAI Hosted Tools

## Decisions

### 1. Ein modularer Monolith und eine gemeinsame Origin

Die Produktionsform besteht aus drei dauerhaft laufenden Containern:

```text
Browser / installierte PWA
          │ HTTPS, eine Origin
          ▼
   Caddy + statische PWA ── /api/v1/* ──► ASP.NET Core API ──► OpenAI
                                                   │
                                                   ▼
                                              PostgreSQL
```

Caddy terminiert TLS, liefert den statischen Frontend-Build aus und leitet `/api/v1/*` an die API weiter. PostgreSQL bleibt ausschließlich im internen Compose-Netz. Eine gemeinsame Origin vermeidet produktives CORS und erlaubt sichere Cookie-Sitzungen.

Das Repository erhält folgende grobe Struktur:

```text
apps/web/                    Next.js-, React- und PWA-Code
src/Gainer.Api/              Composition Root, Endpoints, Middleware
src/Gainer.Core/             Domäne und Anwendungsfälle nach Modulen
  Modules/Access/
  Modules/BodyTracking/
  Modules/Training/
  Modules/Sync/
  Modules/Insights/
  Modules/AiCoach/
src/Gainer.Infrastructure/   EF Core, Identity, OpenAI und externe Adapter
src/Gainer.Contracts/        HTTP-DTOs und versionierte Vertragsmodelle
src/Gainer.AppHost/          Aspire-Anwendungsmodell
src/Gainer.ServiceDefaults/  Health Checks, Service Discovery, OpenTelemetry
tests/                       Unit-, Integrations-, Architektur- und Browsertests
```

Alle Backend-Module laufen in einem API-Prozess und verwenden eine PostgreSQL-Datenbank. Modulgrenzen werden über interne Schnittstellen und Architekturtests geschützt, nicht über Netzwerkgrenzen. `Sync` dispatcht typisierte Befehle an Fachmodule und enthält keine eigene Fachlogik. `Insights` darf strukturierte Fachdaten lesen; `AiCoach` darf nur die nutzergebundenen Read-Ports von `Insights` aufrufen.

Ein Microservice-Schnitt hätte für die private Nutzerzahl keinen Laufzeitnutzen, würde aber Authentifizierung, atomare Sync-Transaktionen, Deployment und Fehlersuche deutlich verteuern. Ein Projekt pro Capability wird ebenfalls verworfen; wenige Projekte mit Feature-Modulen halten die Navigierbarkeit hoch, ohne die Domänengrenzen aufzugeben.

### 2. Statische Next.js-PWA mit IndexedDB-first-Zugriff

Next.js wird mit App Router als statischer Export gebaut. Persönliche Ansichten sind Client Components und laden weder über Server Components noch über Server Actions Nutzerdaten. Der Produktionsbetrieb benötigt dadurch keinen Node-Prozess; falls später SSR zwingend wird, kann ein Next-Standalone-Container ergänzt werden, ohne die API- oder Sync-Verträge zu ändern.

`@serwist/next` erzeugt den Service Worker und precached ausschließlich versionierte App-Shell- und öffentliche statische Assets. `/api/*`, Auth-Antworten und persönliche Inhalte sind `NetworkOnly` und erhalten serverseitig `Cache-Control: no-store`. Übungskatalog und Fachdaten werden bewusst in IndexedDB statt im HTTP-Cache gespeichert. Serwist wird eingesetzt, weil es den Next.js-Build und den Service-Worker-Lebenszyklus integriert; eine handgeschriebene Precache-Pipeline wäre fehleranfälliger. Hintergrund-Sync-Plugins werden nicht verwendet. Siehe [Serwist für Next.js](https://serwist.pages.dev/docs/next).

Dexie kapselt IndexedDB, Schema-Upgrades und Transaktionen. Die Dependency ist gerechtfertigt, weil Fachänderung und Outbox-Eintrag über mehrere Object Stores atomar geschrieben werden müssen. Dexie Cloud oder ein Sync-Plugin wird nicht verwendet; der Sync-Vertrag bleibt vollständig anwendungseigen. Siehe [Dexie API und Transaktionen](https://dexie.org/docs/API-Reference).

Pro Konto wird eine eigene lokale Datenbank geöffnet. Ein globaler, nicht fachlicher Store kennt nur die zufällige Installations-ID und lokale Profilzuordnungen. Nutzerbezogene Stores sind:

- `syncMeta`, `outbox`, `conflicts` und `tombstones`
- `goals`, `checkIns`, `customExercises`, `templates` und `rotation`
- `workouts` als lokale Aggregate mit vollständigem Snapshot und Sätzen
- `exerciseCatalog` als versionierte, nur lesbare Kopie des Basiskatalogs
- `analyticsCache` ausschließlich für serverberechnete Werte samt `asOfRevision`

Ein veränderliches lokales Aggregat hält Server-Snapshot, Working Copy, Serverversion und Sync-Zustand getrennt. Jede UI-Änderung validiert die Working Copy und schreibt Fachstand plus unveränderliche Outbox-Mutation in genau einer Dexie-Transaktion. Erst nach dem Commit meldet die UI Erfolg. Nach einem Fehler wird kein optimistischer Erfolg vorgetäuscht.

Alle Tracking-Schreibpfade gehen auch online zuerst über lokale Repositories und Outbox. Ein paralleler direkter CRUD-Pfad zur API wird nicht angeboten. Dashboard-Kennzahlen werden nicht in TypeScript nachimplementiert; offline zeigt die UI höchstens die zuletzt serverseitig berechnete Projektion mit Datenstand. Rohe lokal vorhandene Zeitreihen dürfen weiterhin visualisiert werden.

Beim Logout werden Datenbankhandles, Queries und UI-State sofort geschlossen. Lokale Daten werden zur Vermeidung unbemerkten Verlusts nicht automatisch gelöscht, sind aber erst nach erneuter Anmeldung desselben Kontos wieder erreichbar. Eine ausdrückliche Aktion kann lokale Daten nach Warnung über ausstehende Änderungen entfernen. Ohne App-Verschlüsselung bleiben Daten für eine Person mit Zugriff auf Browserprofil oder Gerätespeicher technisch lesbar; das entspricht der vereinbarten Sicherheitsgrenze.

Service-Worker- und IndexedDB-Versionen werden getrennt migriert. Ein Update aktiviert sich nicht mitten in einer lokalen Schreibtransaktion oder einem laufenden Workout. Scheitert ein IndexedDB-Upgrade, bleibt die alte Datenbank unangetastet und die Anwendung fordert zum Retry auf; Outbox-Einträge dürfen nie still verworfen werden.

### 3. Cookie-Sitzungen, CSRF-Schutz und getrennte Kontoverwaltung

ASP.NET Core Identity verwendet ein `__Host-`-Cookie mit `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/` und ohne `Domain`. Zugangstokens werden weder in Local Storage noch in IndexedDB abgelegt. Alle mutierenden Requests, einschließlich Login, Logout, Einladungsannahme und Sync-Push, benötigen ein Antiforgery-Token in einem eigenen Header. Dieses wird erst beim Senden ergänzt und niemals Teil einer Outbox-Mutation. Zusätzlich werden `Origin` beziehungsweise `Referer` geprüft; GET und HEAD verändern keinen Zustand.

Produktion deaktiviert CORS. Lokal erlaubt die API ausschließlich die konkrete, vom AppHost konfigurierte Frontend-Origin mit Credentials. ASP.NET-Data-Protection-Schlüssel liegen auf dem VPS in einem persistenten, gesicherten Volume, damit Neustarts nicht unkontrolliert Cookies und Einladungstokens ungültig machen.

Öffentliche Registrierung existiert nicht. Ein Account-Operator kann Identitätsmetadaten, Einladungen und Kontostatus über eine eigene Policy verwalten, die keinerlei Fitness-Repositories oder Insights freischaltet. Einladungen verwenden zufällige, nur gehasht gespeicherte, ablaufende Einmaltokens; der Link wird im MVP manuell geteilt, sodass kein E-Mail-Dienst nötig ist. Ein deaktiviertes Konto erhält einen aktualisierten Security Stamp und verliert bestehende Sitzungen. Das initiale Betreiberkonto entsteht über einen expliziten einmaligen Provisionierungsschritt aus einem externen Secret, nie aus produktiven Seed-Zugangsdaten im Repository.

JWT im Browser wurde verworfen, weil Lebenszyklus, sichere Ablage und Widerruf für diese gleich-originige PWA unnötig komplexer wären. Ein allgemeiner Admin mit fachlichem Lesezugriff wurde verworfen, weil er dem Produktvertrag widerspricht.

### 4. Nutzerbindung als Defense in Depth

Ein request-scoped `IUserContext` liest die Nutzer-ID ausschließlich aus dem authentifizierten Principal. Fach-DTOs, Sync-Verträge und AI-Tools enthalten keine maßgebliche `UserId`. Neue Entitäten erhalten ihre Nutzerbindung serverseitig.

Alle nutzereigenen Tabellen und auch deren Kindtabellen tragen `UserId`. Nutzergebundene Repository-Methoden und EF-Core-Query-Filter begrenzen Lesezugriffe. Ein SaveChanges-Interceptor setzt die Nutzer-ID neuer Datensätze und verwirft fehlende oder abweichende Bindungen. Zusammengesetzte Fremdschlüssel mit `UserId` verhindern, soweit das Modell es zulässt, Cross-User-Beziehungen bereits in PostgreSQL. Fremde Ressourcen-IDs ergeben ein nicht unterscheidbares `404`.

`IgnoreQueryFilters`, rohe Fach-SQL-Abfragen und die direkte Nutzung des DbContext außerhalb der Infrastruktur sind nicht erlaubt und werden durch Architekturtests kontrolliert. Query-Filter allein gelten nicht als Autorisierung. Integrationstests mit zwei echten Nutzern prüfen Listen, Details, Counts, Pagination, Schreiben, Sync, Konflikte, Analytics, AI-Tools und Operatorrollen.

PostgreSQL-RLS wurde für den MVP verworfen, weil nur das Backend Datenbankzugriff besitzt und RLS Session-Kontext, Migrationen sowie Tests erweitert. Es kann später als zusätzliche Schutzschicht eingeführt werden, ersetzt aber auch dann nicht die Anwendungsautorisierung.

### 5. Relationales PostgreSQL-Modell und unveränderliche Workouts

Ein gemeinsamer `AppDbContext` basiert auf dem Identity-Kontext. Dadurch können Fachänderung, Idempotenzbeleg und Sync-Revision in derselben PostgreSQL-Transaktion committed werden. Mehrere DbContexts wurden verworfen, weil sie genau diese zentrale Konsistenzgrenze komplizieren würden. Entity-Konfigurationen bleiben nach Modul getrennt; Tabellen werden in den Schemas `identity`, `tracking`, `training`, `sync` und `ai` gruppiert.

Wesentliche Tabellen sind:

- `tracking.body_goals` und `tracking.daily_check_ins`
- `training.exercises` für globale Basisübungen (`owner_user_id IS NULL`) und eigene Übungen
- `training.workout_templates`, `workout_template_items`, `workout_rotations` und `workout_rotation_items`
- `training.workouts`, `workout_exercises` und `workout_sets`
- `sync.clients`, `sync.user_state`, `sync.processed_mutations`, `sync.change_batches` und `sync.change_items`
- `ai.request_usage` nur mit technischem Status, Modell, Tokenanzahl, Dauer und Zeitstempel, ohne Prompt oder Antwort

Wichtige Constraints und Indizes sind ein partieller Unique Index für höchstens ein aktives Ziel, Unique `(user_id, local_date)` für Check-ins, Unique-Positionen innerhalb geordneter Templates und Rotationen, `(user_id, completed_at DESC)` für Historie, `(user_id, source_exercise_id, completed_at)` für Previous Performance sowie `(user_id, mutation_id)` für Idempotenz. Häufige fachliche Indizes beginnen mit `UserId`.

Alle veränderlichen Aggregate besitzen eine explizite `version bigint`; PostgreSQL-`xmin` wird nicht als öffentlicher Sync-Vertrag verwendet. Ressourcen- und Mutations-IDs sind vom Client erzeugte UUIDv4. Physische Ereigniszeitpunkte werden als UTC-`timestamptz`, fachliche Tage als `date` und die Nutzerzeitzone als IANA-ID gespeichert. Kanonische Einheiten sind Kilogramm, Gramm, Kilokalorien, ganze Schritte und Schlafminuten.

Beim Start eines Workouts kopiert der Server beziehungsweise die lokale Domänenschicht Template- und Übungsdaten in einen relational normalisierten Snapshot. `workout_exercises` hält damaligen Namen, Reihenfolge, Vorgaben, Pause und Notizen; `workout_sets` hält die ausgeführten Werte. Template- und Exercise-IDs bleiben nur Herkunftsreferenzen. Historische Anzeigen dürfen nie aktuelle Namen oder Vorgaben nachladen. Nach `completed` lehnt der Domain-Handler reguläre Änderungen ab. Workout-Abschluss und Fortschreibung der Rotation sind eine atomare Fachmutation und erzeugen einen gemeinsamen Change-Batch.

Der Basiskatalog wird nicht zur Laufzeit aus einem fremden Repository geladen. Nach Lizenzprüfung wird ein kuratierter Metadaten-Snapshot mit stabilen, im Repository festgehaltenen IDs importiert; Bilder und Animationen bleiben ausgeschlossen. Scheitert die Lizenzfreigabe des vorgesehenen Datensatzes, erfüllt ein kleiner eigener Metadatenkatalog denselben Vertrag.

### 6. Getrennter Push-/Pull-Sync mit Ressourcen- und Nutzerrevisionen

Der versionierte Sync-Vertrag besteht aus zwei Operationen:

```http
PUT /api/v1/sync/mutations/{mutationId}
GET /api/v1/sync/changes?after={revision}&limit=200
```

Eine Push-Mutation enthält `protocolVersion`, `clientId`, `clientSequence`, einen typisierten Operationsnamen, betroffene Ressourcen mit `resourceId` und `baseVersion`, optional `dependsOnMutationId` sowie einen schema-validierten Payload. Sie enthält keine Nutzer-ID. Operationen wie `completeWorkout` dürfen mehrere Aggregate atomar verändern.

Der Server berechnet selbst einen SHA-256-Hash über den kanonisierten Mutationsinhalt. `processed_mutations` speichert pro Nutzer Mutation-ID, Hash und vollständiges stabiles Ergebnis. Gleiche ID plus gleicher Hash liefert dasselbe Ergebnis mit `replayed=true`; gleiche ID plus anderer Hash ergibt `409 mutation_id_reused`. Idempotenzbeleg, Fachänderung, neue Ressourcen-Versionen und Change-Batch werden in einer Transaktion committed.

Push-Antworten unterscheiden:

- `200` für angewendet oder identisch wiederholt
- `401` für eine ungültige Sitzung ohne jede Mutation
- `409` für veraltete Basisversion, inaktives Schreibgerät, unveränderliches Workout oder wiederverwendete Mutation-ID
- `422` für einen dauerhaften fachlichen Validierungsfehler
- `429`, `5xx`, Timeout oder Transportfehler als unveränderten Retry-Fall

Der lokale Sync sendet die jeweils älteste Mutation eines Aggregats zuerst. Nachfolgende Mutationen sind von der erwarteten neuen Version abhängig und bleiben nach einem Konflikt oder Validierungsfehler blockiert, bis der Nutzer den Vorgänger behebt oder verwirft. Unabhängige Aggregate können weiter synchronisieren.

`sync.user_state` hält die nächste monoton steigende Revision des Nutzers. Jede Servertransaktion erzeugt einen `change_batch`, der mehrere Ressourcen-Snapshots oder Tombstones enthalten kann und bei der Pull-Paginierung nie geteilt wird. Pull liefert streng nach Revision geordnete Batches, `nextCursor` und `hasMore`. Der Client wendet vollständigen Batch und Cursor in einer Dexie-Transaktion an; bei Abbruch bleibt der alte Cursor bestehen. Trifft ein Tombstone auf eine lokale Pending Mutation, entsteht ein sichtbarer Konflikt statt einer stillen Wiederbelebung.

Ressourcen-Version und Nutzer-Revision haben getrennte Zwecke: Die Version verhindert Lost Updates, die Revision steuert den inkrementellen Feed. Im privaten MVP bleiben Mutation Receipts und Change-Batches vollständig erhalten. Eine spätere Kompaktierung benötigt zuerst einen Full-Resync-Vertrag und bestätigte Client-Watermarks.

Der Sync startet bei App-Start, Rückkehr in den Vordergrund, `online`-Event, kurzer Verzögerung nach lokaler Mutation und manuellem Retry. Ein IndexedDB-Lease verhindert parallele Sync-Loops mehrerer Tabs; `BroadcastChannel` ist nur ein Komfortsignal. Service Worker und Timer übernehmen keine garantierte Hintergrundausführung.

Bei `401` bleiben alle Outbox-Einträge erhalten, der Status wechselt auf `auth-blocked` und erst die erneute Anmeldung desselben Kontos setzt den Sync fort. Ein anderes Konto öffnet eine andere lokale Datenbank. `sync.clients` und `sync.user_state.active_client_id` setzen die MVP-Regel eines aktiven Schreibgeräts um: Ein Zweitgerät ist zunächst read-only; eine ausdrückliche Online-Übernahme warnt vor ausstehenden Änderungen des bisherigen Geräts. Komplexes Merging wird nicht simuliert.

Jede Sync-Payload trägt eine Protokollversion. Der Server unterstützt während eines Rollouts mindestens die aktuelle und die unmittelbar vorherige Version. Ein zu alter Client erhält `upgrade_required`, ohne dass seine Outbox gelöscht wird.

Ein kombinierter Push-/Pull-Batch wurde verworfen: Getrennte Requests machen HTTP-Fehler, idempotente Retries und Pull-Paginierung unabhängig und wesentlich leichter testbar. Zeitstempel werden nicht als Konfliktauflösung verwendet, weil Clientuhren unzuverlässig sind.

### 7. Deterministische Analytics als eigener Backend-Port

`Insights` berechnet Kennzahlen auf Anfrage aus PostgreSQL; Materialized Views, Cronjobs und ein Cache-Service sind bei der privaten Nutzerzahl unnötig. Mehrteilige Dashboard- oder Coach-Abfragen laufen in einer konsistenten Lesetransaktion. Jede Antwort enthält Zeitraum, Einheit, Datenabdeckung, Algorithmusversion und `asOfRevision`.

Für Version 1 gelten:

- `weight-average-v1`: arithmetisches Mittel ausschließlich vorhandener Tageswerte
- `weight-trend-ols-v1`: lineare Regression über lokale Kalendertage, Steigung × 7; unter drei Beobachtungen `insufficient_data`
- `nutrition-average-v1`: Mittel je Kennzahl nur über Tage, an denen genau diese Kennzahl erfasst wurde
- `training-volume-v1`: Summe `Gewicht × Wiederholungen` geeigneter abgeschlossener Sätze
- `e1rm-epley-v1`: Epley-Formel `Gewicht × (1 + Wiederholungen / 30)` für positive Gewichte und 1 bis 12 Wiederholungen

Null und fehlend bleiben verschieden. Laufende oder abgebrochene Workouts fließen nicht ein. Rundung findet erst im Ausgabeformat statt; Berechnungen verwenden die kanonischen Dezimalwerte. Golden Tests sichern Formeln, Zeitzonen, Fenstergrenzen und fehlende Daten. UI und AI Coach konsumieren dieselben Query-Services und DTOs.

### 8. OpenAI als schreibgeschützter Adapter hinter dem Backend

Nur `Gainer.Infrastructure` verwendet den offiziellen OpenAI-.NET-Client. Modell, Timeout, Ausgabetokenlimit und Kostengrenzen kommen aus externer Konfiguration. Die API verwendet die Responses API, keinen providerseitigen Conversation State und keinen Background Mode.

Der Ablauf einer Coach-Anfrage ist:

1. Sitzung, Rate Limit und Eingabegrenzen prüfen.
2. Minimale Ziel- und Datenverfügbarkeitsmetadaten zusammenstellen.
3. Eine Responses-Anfrage mit `store=false` und ausschließlich streng schema-validierten Function Tools senden.
4. Höchstens drei Tool-Runden ausführen; Werkzeugname, Argumente, Zeiträume und Ergebnisgröße serverseitig prüfen.
5. Tools über die gleichen nutzergebundenen Insights-Ports wie die UI ausführen.
6. Eine strukturierte Antwort mit `summary`, `observations`, `factIds`, `dataGaps`, `suggestions` und optionalem Sicherheitshinweis validieren.

Function Tools sind rein lesend und auf aktuelles Ziel, Gewichtstrend, Ernährungsdurchschnitte, letzte Workouts, Kraftübersicht, einzelne freigegebene Übungs-IDs und Zeitraumvergleiche begrenzt. Sie akzeptieren weder Nutzer-ID, SQL, URL, Tabellenname noch beliebige Datenbankfilter. Web Search, File Search, MCP, Code Interpreter und schreibende Tools werden nicht angeboten. Die [offizielle Function-Calling-Dokumentation](https://developers.openai.com/api/docs/guides/function-calling) bestätigt JSON-Schema-basierte Function Tools; das Backend behandelt trotzdem jeden Modelloutput als untrusted input.

Tool-Ergebnisse bestehen aus begrenzten Fakten mit stabilen `factId`s. Die UI rendert numerische Evidenz direkt aus diesen Backend-Fakten; Modelltext referenziert sie nur. Unbekannte Faktenreferenzen oder ungültige strukturierte Ausgaben verwerfen die Antwort kontrolliert. Das Modell darf weder Fachwerte mutieren noch ohne freigegebene deterministische Regel eine konkrete numerische Kalorien- oder Trainingsänderung anweisen.

Prompts enthalten weder E-Mail noch Auth-Daten, freie Workout-Notizen oder nicht benötigte Rohreihen. Logs enthalten Request-/Trace-ID, Modell, Dauer, Tokenanzahl und Ergebniscode, aber keine Prompts, Antworten oder Tool-Payloads. Jeder Request setzt `store=false`. Das deaktiviert den für die Antwort benötigten providerseitigen Anwendungszustand, ist aber keine Zusage von Zero Data Retention oder Ende-zu-Ende-Verschlüsselung; mögliche Abuse-Monitoring-Aufbewahrung und gesonderte Kontrollen sind in den [OpenAI Data Controls](https://developers.openai.com/api/docs/guides/your-data#default-usage-policies-by-endpoint) beschrieben.

Timeouts, Rate Limits, ungültige Tool-Aufrufe und Providerfehler ergeben stabile, retry-fähige Coach-Fehler. OpenAI ist weder Readiness-Abhängigkeit noch Voraussetzung für Tracking oder Insights. Eine dauerhafte Chat-Historie wird im MVP nicht angelegt; jede Frage ist eine eigenständige Auswertung. Direkter SQL-Zugriff wurde wegen Autorisierung, Prompt Injection und fehlender Fachvalidierung verworfen.

### 9. Versionierte HTTP-Verträge und Fehler

Alle Endpunkte liegen unter `/api/v1`. Neben Auth und Sync gibt es einen versionierten Basiskatalog, nutzergebundene Insights, `POST /api/v1/coach/responses` und getrennte Account-Operator-Endpunkte. EF-Entitäten werden nie serialisiert. ASP.NET OpenAPI ist die Vertragsquelle; daraus werden TypeScript-Typen für die PWA generiert.

Fachfehler verwenden `application/problem+json` mit stabilen maschinenlesbaren Codes. Listen und Change Feeds sind begrenzt und paginiert. Requestgrößen, Freitextfelder, Sync-Payloads und AI-Fragen besitzen feste Obergrenzen. ASP.NET Core Rate Limiting schützt Anmeldung, Einladungsannahme und Coach pro IP beziehungsweise Nutzer.

### 10. Aspire als Anwendungsmodell, Docker Compose als Laufzeit

Der AppHost beschreibt lokal PostgreSQL, API und den Next.js-Dev-Prozess, injiziert Referenzen und wartet auf Readiness. `ServiceDefaults` enthält ausschließlich Health-, Service-Discovery-, Resilience- und OpenTelemetry-Konfiguration, keine Fachlogik.

Für Produktion enthält der AppHost ein Docker-Compose-Environment und die Ressourcen `edge`, `api` und `postgres`. `aspire publish --environment production` erzeugt das Compose-Artefakt; Images entstehen aus eingecheckten reproduzierbaren Dockerfiles. Aspire dokumentiert dieses Publish-Modell und die generierten Compose-/Environment-Artefakte in [Deploy to Docker Compose](https://aspire.dev/deployment/docker-compose/). Der AppHost und das Aspire Dashboard laufen nicht dauerhaft auf dem VPS; Service Discovery erfolgt dort über Compose-DNS.

Health Checks werden getrennt:

- `/health/live`: Prozess lebt, ohne externe Abhängigkeiten
- `/health/ready`: PostgreSQL erreichbar und erwartete Schema-Version vorhanden
- OpenAI ist ausdrücklich kein Readiness-Kriterium

OpenTelemetry instrumentiert HTTP, EF/Npgsql und OpenAI-Aufrufmetadaten, aber keine Bodies, Fitnessrohwerte, Prompts oder Antworten. Lokal gehen Signale an das Aspire Dashboard. Produktion schreibt strukturierte Logs nach stdout und kann optional einen internen OTLP-Endpunkt erhalten; kein Telemetrie- oder Dashboard-Port wird öffentlich exponiert.

Caddy ist Traefik für diesen festen Ein-VPS-Aufbau vorzuziehen, weil Routing und automatische TLS-Verwaltung mit weniger beweglichen Teilen auskommen. Nur Ports 80/443 und ein eingeschränkter SSH-Zugang sind öffentlich. Forwarded Headers werden nur vom bekannten Proxy akzeptiert und HSTS wird nach erfolgreichem TLS-Test aktiviert.

Secrets liegen als root-lesbare Dateien außerhalb von Repository, Images und generiertem unbefüllten Environment-Artefakt. Dazu zählen Datenbankpasswort, OpenAI-Key und Provisionierungssecret. Persistente Volumes existieren für PostgreSQL, Data Protection und Caddy-Zertifikate; sie ersetzen keine Backups.

### 11. Gezielt wenige Dependencies und reale Integrationstests

Runtime-Dependencies bleiben auf die bereits vorgegebenen Frameworks sowie folgende begründete Ergänzungen beschränkt:

- Npgsql/EF Core für den vorgegebenen PostgreSQL-Zugriff
- Dexie für typsichere IndexedDB-Transaktionen und Migrationen
- Serwist für Next.js-PWA-Build und App-Shell-Caching
- Recharts für die wenigen interaktiven Fortschrittsdiagramme
- offizieller OpenAI-.NET-Client hinter einem eigenen Adapter
- OpenTelemetry-Integrationen aus `ServiceDefaults`

MediatR, AutoMapper, FluentValidation, Redis, Message Bus und generische Repository-Frameworks werden nicht vorsorglich eingeführt. Fachhandler, explizite Mappings und Validierung bleiben zunächst normaler Anwendungscode. Versionen werden zentral beziehungsweise über Lockfiles fixiert und automatisiert aktualisiert.

Unit Tests decken Domänenregeln und Analytics-Golden-Vektoren ab. API-Integrationstests laufen gegen echtes PostgreSQL und mindestens zwei Nutzer. Sync-Tests prüfen verlorene Bestätigungen, gleiche Mutation mit anderem Hash, Abbruch zwischen Pull und lokalem Commit, Tombstones, Konflikte, Konto- und Gerätewechsel sowie Protokoll-Upgrades. Browser-E2E-Tests prüfen Installation, Offline-Schalter, Reload, Service-Worker-Update und IndexedDB-Migration. Die Kernreise wird zusätzlich auf einem physischen iPhone getestet. Der OpenAI-Adapter wird standardmäßig gefakt; eine kleine opt-in Eval-Suite prüft typische, datenarme, manipulative und medizinische Fragen ohne Bestandteil des normalen CI-Geheimnisses zu sein.

## Risks / Trade-offs

- **IndexedDB wird durch Browserbereinigung, Speicherknappheit oder Nutzeraktion entfernt** → Persistenzberechtigung best-effort anfragen, Pending-Zahl sichtbar halten, zeitnah im Vordergrund synchronisieren und nie behaupten, lokaler Speicher sei ein Backup.
- **iOS suspendiert Timer und Sync** → Timer aus absolutem Zielzeitpunkt rekonstruieren; Outbox beim nächsten Vordergrundzeitpunkt fortsetzen; keine Hintergrundgarantie anzeigen.
- **Ein veralteter PWA-Client trifft auf ein neues Schema** → versionierter Sync-Vertrag, Unterstützung von N und N−1, Expand/Contract und `upgrade_required` ohne Outbox-Verlust.
- **Cross-User-Leak durch einen fehlerhaften Query-Pfad** → zentraler Nutzerkontext, nutzergebundene Repositories, SaveChanges-Prüfung, zusammengesetzte Constraints und verpflichtende Zwei-Nutzer-Tests.
- **Lokale Datenreste auf einem gemeinsam genutzten Gerät** → getrennte Datenbanken, sofortiges Schließen beim Logout und explizite Löschfunktion; verbleibendes Browserprofil-Risiko transparent dokumentieren.
- **Mehrere Offline-Geräte erzeugen Konflikte** → ein aktives Schreibgerät, Basisversionen und sichtbare manuelle Auflösung; kein Last-Write-Wins.
- **Mutation Receipts und Change Feed wachsen dauerhaft** → für die kleine Beta zunächst akzeptieren und messen; erst mit Full-Resync-/Watermark-Vertrag kompaktieren.
- **Statischer Next.js-Export begrenzt Serverfeatures** → bewusster MVP-Trade-off; späterer Standalone-Container verändert weder lokale Daten- noch API-Grenze.
- **OpenAI halluziniert oder ist nicht erreichbar** → serverseitige Fakten, strukturierte Ausgabe, nur Read-only-Tools, harte Tool-/Zeitlimits und vollständige Entkopplung der Kernfunktionen.
- **`store=false` wird als vollständige Nichtaufbewahrung missverstanden** → Datenschutzhinweis benennt die tatsächliche Grenze und Daten werden weiterhin minimiert.
- **Ein VPS ist Single Point of Failure** → Restart Policies, Health Monitoring, verschlüsselte Offsite-Backups und geprobter Restore; Hochverfügbarkeit bleibt außerhalb des MVP.
- **Schema-Migration verhindert Anwendungsrollback** → expliziter Migrator, Expand/Contract, Backup vor Migration und unveränderliche Image-Tags.
- **Exercise-Dataset oder Medien dürfen nicht verwendet werden** → Lizenz-Gate vor Import, keine Medien und eigener kleiner Metadaten-Snapshot als Fallback.

## Migration Plan

Es gibt keine bestehenden Produktionsdaten zu migrieren. Der erste Rollout erfolgt dennoch als reproduzierbarer Deployment-Prozess:

1. AppHost, Images, Compose-Artefakt und Datenbankmigration in CI bauen; Unit-, Integrations-, Architektur- und Browser-Smoke-Tests ausführen.
2. Basiskatalog-Metadaten nach dokumentierter Lizenzprüfung als versionierten Seed in die Migration aufnehmen.
3. VPS mit Docker, Firewall, DNS, root-lesbaren Secrets, persistenten Volumes und verschlüsseltem Offsite-Backupziel vorbereiten.
4. Vor dem Schemawechsel ein Backup erstellen und anschließend einen einmaligen EF-Migrator aus dem API-Image ausführen; Migrationen laufen nicht konkurrierend beim API-Start.
5. Neue unveränderliche Image-Tags mit Compose starten und Live-/Ready-, Login-, Sync-, Isolation- und Restore-Smoke-Tests durchführen.
6. Zuerst nur das Betreiberkonto provisionieren und die vollständige iPhone-/Offline-Kernreise testen; erst danach Kollegen einladen.

Für ein Anwendungsrollback werden die vorherigen Image-Tags reaktiviert. Migrationen folgen Expand/Contract, damit die vorige Anwendungsversion möglichst weiterarbeiten kann. Ist ein Schema nicht rückwärtskompatibel, wird vor dem Rollback das geprüfte Backup wiederhergestellt; der mögliche Datenverlust seit diesem Backup muss dabei ausdrücklich akzeptiert werden. Regelmäßige `pg_dump`-Backups werden zusätzlich verschlüsselt offsite übertragen und Restore-Tests schließen Data-Protection-Schlüssel sowie notwendige Konfiguration ein.

## Open Questions

- Welcher Domainname und welches S3-kompatible Offsite-Ziel werden für den ersten VPS verwendet? Beides sind Deploymentparameter ohne Einfluss auf Verträge oder Modulstruktur.
- Welches OpenAI-Modell und welche konkreten Nutzer-/Kostenlimits werden nach einer kleinen Qualität-, Latenz- und Kosten-Evaluation konfiguriert? Der Adapter und die Tests bleiben modellunabhängig.
- Soll Produktion zunächst nur strukturierte Containerlogs nutzen oder zusätzlich an einen vorhandenen internen OTLP-Empfänger senden? Die Instrumentierung ist in beiden Fällen identisch.
