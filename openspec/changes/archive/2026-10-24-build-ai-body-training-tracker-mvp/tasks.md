## 1. Workspace und Qualitätsgrundlage

- [x] 1.1 Lege die .NET-Solution mit `Gainer.Api`, `Gainer.Core`, `Gainer.Infrastructure`, `Gainer.Contracts`, `Gainer.AppHost` und `Gainer.ServiceDefaults` in den vorgesehenen Verzeichnissen an und bestätige einen grünen Backend-Build.
- [x] 1.2 Erzeuge unter `apps/web` eine strikt typisierte Next.js-/React-Anwendung mit App Router, statischem Export, Tailwind CSS und shadcn/ui und bestätige Typecheck, Lint und Produktionsbuild.
- [x] 1.3 Richte zentrale .NET-Paketversionen und einen eingecheckten Frontend-Lockfile ein; ergänze nur die im Design begründeten Runtime-Dependencies Npgsql/EF Core, Dexie, Serwist, Recharts, OpenTelemetry und den offiziellen OpenAI-.NET-Client.
- [x] 1.4 Lege Projekte für Unit-, PostgreSQL-Integrations-, Architektur- und Playwright-Browsertests an und lasse je einen minimalen Test in der lokalen Toolchain erfolgreich laufen.
- [x] 1.5 Richte reproduzierbare Befehle für Restore, Formatprüfung, Build, Typecheck, Unit-, Integrations- und Browsertests sowie eine CI-Pipeline ein, die bei Vertragsdrift oder fehlgeschlagenem Test stoppt.
- [x] 1.6 Dokumentiere in README beziehungsweise CONTRIBUTING die Modulstruktur, den MVP-Scope, die Definition of Done „betroffene Builds und Tests nach jedem Task grün“ und Conventional Commits für alle Implementierungscommits.

## 2. API-, Aspire- und Persistenzfundament

- [x] 2.1 Konfiguriere den Aspire AppHost so, dass PostgreSQL, API und Next.js-Dev-Prozess lokal gemeinsam starten, Referenzen erhalten und in einem Aspire-Integrationstest als Topologie verfügbar sind.
- [x] 2.2 Implementiere in `ServiceDefaults` Service Discovery, Resilience-Grundlagen, strukturierte OpenTelemetry-Instrumentierung sowie getrennte `/health/live`- und `/health/ready`-Checks; teste, dass nur PostgreSQL und Schema, nicht OpenAI, die Readiness beeinflussen.
- [x] 2.3 Richte den API-Composition-Root unter `/api/v1`, Correlation-/Trace-IDs, begrenzte Requestgrößen, `application/problem+json` mit stabilen Fehlercodes und inhaltssparsame Logs ein und decke Erfolg sowie Fehler per API-Test ab.
- [x] 2.4 Implementiere einen gemeinsamen Identity-basierten `AppDbContext` mit den PostgreSQL-Schemas `identity`, `tracking`, `training`, `sync` und `ai` sowie Konventionen für UUID, `UserId`, `version bigint`, UTC-Zeitpunkte und fachliche Kalendertage.
- [x] 2.5 Implementiere `IUserContext`, nutzergebundene Repository-Grenzen, EF-Query-Filter und einen SaveChanges-Interceptor, der neue Nutzerbindungen setzt und abweichende Bindungen verwirft; sichere die erlaubten Abhängigkeiten zusätzlich durch Architekturtests ab.
- [x] 2.6 Implementiere gemeinsame Wertobjekte und Validierungshelfer für Kilogramm, Gramm, Kilokalorien, Schritte, Schlafminuten, RIR, IANA-Zeitzonen und einen injizierbaren `TimeProvider` und decke Grenz- sowie Zeitzonenfälle mit Unit Tests ab.
- [x] 2.7 Definiere die internen Verträge für typisierte Fachmutationen, Basisversionen, atomare Multi-Aggregat-Operationen und Change-Erfassung, ohne bereits einen generischen CRUD- oder SQL-Pfad freizugeben.
- [x] 2.8 Richte explizite EF-Migrationen, Schema-Versionsprüfung und eine isolierbare PostgreSQL-Testfixture mit mindestens zwei Nutzern ein; teste Migration auf leerer Datenbank, wiederholten Start und Reset zwischen Tests.
- [x] 2.9 Etabliere ASP.NET OpenAPI als einzige HTTP-Vertragsquelle, generiere daraus reproduzierbar TypeScript-Typen und lasse CI bei nicht eingecheckter oder inkompatibler Vertragsänderung fehlschlagen.

## 3. Geschlossener Zugang und Nutzerisolation

- [x] 3.1 Konfiguriere ASP.NET Core Identity mit sicherem `__Host-`-Cookie, `Secure`, `HttpOnly`, `SameSite=Lax`, persistierbaren Data-Protection-Schlüsseln und Security-Stamp-Validierung und prüfe die Cookie-Flags per Integrationstest.
- [x] 3.2 Aktiviere Antiforgery-Header und Origin-/Referer-Prüfung für alle Mutationen, deaktiviere produktives CORS und erlaube lokal nur die konkrete AppHost-Frontend-Origin; teste fehlende und falsche CSRF- beziehungsweise Origin-Werte.
- [x] 3.3 Implementiere Login, Logout, Sessionabfrage und generische Anmeldefehler ohne öffentliche Registrierung; teste gültige Anmeldung, unbekanntes Konto, falsches Passwort, Logout und abgelaufene Sitzung mit `401`.
- [x] 3.4 Implementiere eine getrennte Account-Operator-Policy und die einmalige Erstprovisionierung aus einem externen Secret; teste, dass es keine Standardzugangsdaten gibt und diese Policy keine Fitness-Repositories oder Insights erreicht.
- [x] 3.5 Implementiere ablaufende, einmalige und nur gehasht gespeicherte Einladungen mit manueller Linkweitergabe; teste Aktivierung, Ablauf, Wiederverwendung und nutzerneutrale Fehlermeldungen.
- [x] 3.6 Implementiere Deaktivierung und Reaktivierung von Konten inklusive Security-Stamp-Widerruf und teste, dass bestehende Sitzungen enden, eigene Daten erhalten bleiben und Betreiber keine fachlichen Daten erhalten.
- [x] 3.7 Baue Login-, Einladungsannahme- und getrennte Account-Operator-Ansichten in der PWA und prüfe im Browser, dass nach Logout keine geschützte Ansicht oder persönliche HTTP-Cache-Antwort sichtbar ist.
- [x] 3.8 Erstelle eine wiederverwendbare Zwei-Nutzer-Testmatrix für Listen, Details, Counts, Pagination, Create, Update und Delete; fremde IDs müssen `404` liefern und dürfen keine Daten oder Eigentümerinformationen verändern beziehungsweise offenlegen.

## 4. PWA-Shell und lokale Datenhaltung

- [x] 4.1 Ergänze Web-App-Manifest, eigene Icons, Installationsmetadaten und eine Serwist-Service-Worker-Konfiguration, die nur App-Shell und öffentliche Assets precached und `/api/*` strikt `NetworkOnly` behandelt.
- [x] 4.2 Implementiere eine zufällige Installations-ID, einen nicht fachlichen lokalen Profilindex und eine separate versionierte Dexie-Datenbank je Konto mit Stores für Aggregate, Outbox, Konflikte, Tombstones, Sync-Metadaten, Katalog und Analytics-Cache.
- [x] 4.3 Implementiere den lokalen Aggregat-Envelope aus Server-Snapshot, Working Copy, Serverversion, optimistischer Version und Sync-Zustand und teste mehrere aufeinanderfolgende Offline-Änderungen desselben Aggregats.
- [x] 4.4 Implementiere atomare lokale Fachänderungen, die gemeinsam mit stabiler Mutation-ID und unveränderlichem Outbox-Eintrag committed werden; erzwungene Transaktions- und Quota-Fehler dürfen keinen halben Stand hinterlassen.
- [x] 4.5 Implementiere versionierte IndexedDB-Upgrades, die Fach- und Outbox-Daten erhalten; teste einen erfolgreichen Upgradepfad und einen simulierten Fehler, nach dem die alte Datenbank weiter verwendbar bleibt.
- [x] 4.6 Implementiere Öffnen und Schließen kontogetrennter Datenbanken, sofortiges Leeren von UI-State beim Logout und eine bestätigte lokale Löschfunktion mit Warnung vor Pending Mutations; teste Konto A → Logout → Konto B online und offline.
- [x] 4.7 Baue die responsive App-Shell, Hauptnavigation, Offline-Hinweis und Platzhalter für Pending-/Fehlerstatus und prüfe per Playwright statischen Export, Installation, Offline-Start und das Ausbleiben persönlicher Service-Worker-Caches.

## 5. Ziele und tägliche Check-ins

- [x] 5.1 Implementiere `body_goals` und `daily_check_ins` mit partieller Eindeutigkeit für ein aktives Ziel, Unique `(UserId, local_date)`, kanonischen Einheiten und erster Fachmigration; prüfe Constraints gegen echtes PostgreSQL.
- [x] 5.2 Implementiere typisierte Mutationen zum Anlegen und Ersetzen eines Ziels mit erhaltener Historie für `Bulk`, `Maintain` und `Cut`; teste ungültige Werte, parallele Aktivierung und Nutzerisolation.
- [x] 5.3 Implementiere typisierte Mutationen zum Erstellen und Korrigieren eines Check-ins mit Gewicht, optionaler Ernährung, Schritten und Schlaf; teste Atomarität, Feldgrenzen, doppelte IDs und konkurrierende Einträge desselben Tages.
- [x] 5.4 Implementiere nutzergebundene Projektionen für aktives Ziel, Zielhistorie und chronologische Check-ins und stelle sicher, dass jede akzeptierte Änderung einen vollständigen Sync-Change beziehungsweise Tombstone erzeugt.
- [x] 5.5 Baue Zielverwaltung, Zielhistorie und einen in wenigen Sekunden bedienbaren Daily-Check-in gegen die lokalen IndexedDB-Repositories; validiere vor lokalem Commit und ermögliche sichere Korrekturen.
- [x] 5.6 Prüfe die gesamte Body-Tracking-Funktion mit Unit-, Zwei-Nutzer-Integrations- und Offline-Browsertests einschließlich Reload, ungültiger Korrektur und genau eines Check-ins pro Nutzer und lokalem Tag.

## 6. Übungskatalog, Templates und Rotation

- [x] 6.1 Prüfe und dokumentiere die Lizenz des vorgesehenen Exercise-Datasets, erstelle einen versionierten Metadaten-Snapshot mit stabilen IDs ohne Bilder/Animationen und verwende bei fehlender Freigabe einen kleinen eigenen Basiskatalog.
- [x] 6.2 Implementiere Exercise-Persistenz, Katalogversion und eine begrenzte nutzergebundene Lese-API für Suche sowie Filter nach Name, Zielmuskel, Muskelgruppe und Equipment; teste stabile IDs und unveränderliche Basiseinträge.
- [x] 6.3 Implementiere Create-, Update- und Archive-Mutationen für eigene Übungen und teste, dass nur der Eigentümer sie sieht, archivierte Referenzen auflösbar bleiben und neue Templates sie nicht mehr auswählen.
- [x] 6.4 Implementiere Workout-Templates und geordnete Template-Items mit Sets, Rep Range, optionalem RIR, Pause und Notizen sowie allen PostgreSQL-Constraints und Validierungstests.
- [x] 6.5 Implementiere die geordnete Rotation mit nächstem aktivem Template, Umlauf und Überspringen archivierter Einträge; teste normale Folge, letztes Element, leere Rotation und fremde Templates.
- [x] 6.6 Baue lokale Exercise-Library-, Custom-Exercise-, Template- und Rotationsansichten mit Suche, Filtern, Reordering und validierten Offline-Mutationen.
- [x] 6.7 Prüfe Katalog und Planung mit Zwei-Nutzer-Integrationstests sowie Browsertests für Offline-Anlage, Reload, Archivierung und die Anzeige des korrekten nächsten Templates.

## 7. Workout-Ausführung und unveränderliche Historie

- [x] 7.1 Implementiere `workouts`, `workout_exercises` und `workout_sets` als relationalen Snapshot mit Herkunfts-IDs, kopierten Namen/Vorgaben, Status, Positionen, Zeiten und Nutzer-Constraints und migriere das Schema.
- [x] 7.2 Implementiere den lokalen Workout-Start aus einem vollständig verfügbaren eigenen Template als stabile UUID und vollständigen Snapshot; lehne offline unvollständige oder fremde Templates ab und teste den Reload eines laufenden Workouts.
- [x] 7.3 Implementiere lokale und serverseitige Handler für Hinzufügen, Entfernen und Umordnen von Übungen und Sätzen sowie Gewicht, Wiederholungen, RIR und Notizen; teste Validierung und fehlende Rückwirkung auf das Template.
- [x] 7.4 Implementiere Previous Performance aus dem zeitlich letzten passenden abgeschlossenen eigenen Snapshot und eine lokale Cacheprojektion; teste fehlende Offline-Historie, laufende/abgebrochene Workouts und Cross-User-Ausschluss.
- [x] 7.5 Implementiere den Rest Timer mit absolutem Zielzeitpunkt, automatischem Start, `+30 Sekunden`, `Neustart` und `Überspringen`; teste Navigation, Reload, kontrollierte Uhr und Suspendierungsdauer ohne doppelten Timer.
- [x] 7.6 Implementiere Workout-Abschluss und Rotationsfortschritt als eine atomare Multi-Aggregat-Mutation mit mindestens einem abgeschlossenen Satz; teste Rollback, leeres Workout und genau einen unteilbaren Change-Batch.
- [x] 7.7 Implementiere Historienliste und Detailansicht ausschließlich aus Snapshotdaten und verhindere reguläre Änderungen nach Abschluss; teste Template-/Exercise-Änderungen danach sowie abgelehnte historische Mutationen.
- [x] 7.8 Implementiere bestätigten Abbruch und automatische Wiederherstellung laufender Workouts; teste, dass Abbruch weder Historie, Previous Performance noch Rotation verändert und bloßes Schließen keinen Abbruch auslöst.
- [x] 7.9 Ergänze Integrations- und Browsertests für vollständiges Offline-Workout, verlorene Abschlussbestätigung, idempotenten Retry, abweichenden Retry, Reload und fremde Workout-IDs.

## 8. Serverseitiger Sync-Vertrag

- [x] 8.1 Implementiere `sync.clients`, `sync.user_state`, `sync.processed_mutations`, `sync.change_batches` und `sync.change_items` mit Unique Keys, Nutzerindizes, unteilbaren Revisionen und Migrationstests.
- [x] 8.2 Definiere versionierte Push-/Pull-DTOs für typisierte Operationen, Ressourcen-Basisversionen, Abhängigkeiten, Snapshots, Tombstones, Konflikte und stabile Codes; Contract-Tests müssen eine frei wählbare `UserId` ausschließen.
- [x] 8.3 Implementiere kanonische serverseitige Mutationsserialisierung, SHA-256-Hash und gespeicherte Receipts und sichere Dezimalwerte sowie Schlüsselsortierung mit Golden-Vektor-Tests.
- [x] 8.4 Implementiere den Mutation Processor, der Nutzerbindung, aktiven Client, Protokoll, Abhängigkeit und Basisversion prüft und Fachänderung, Receipt, Versionen und Change-Batch in einer PostgreSQL-Transaktion committed.
- [x] 8.5 Implementiere `PUT /api/v1/sync/mutations/{mutationId}` mit `200`, `401`, `409`, `422` und retry-fähigen Transport-/Serverfehlern und teste jede Antwort inklusive CSRF, Replay und Mutation-ID-Wiederverwendung.
- [x] 8.6 Implementiere `GET /api/v1/sync/changes` mit strikt nutzergebundener, sortierter und begrenzter Paginierung, `nextCursor`, `hasMore`, Snapshots und Tombstones; ein Change-Batch darf nie geteilt oder übersprungen werden.
- [x] 8.7 Implementiere Registrierung und explizite Übernahme des aktiven Schreibgeräts sowie Unterstützung der aktuellen und unmittelbar vorherigen Protokollversion; teste read-only Zweitgerät und `upgrade_required` ohne Datenmutation.
- [x] 8.8 Erstelle eine PostgreSQL-Integrationssuite für verlorene Bestätigung, identischen und abweichenden Retry, veraltete Basisversion, Handler-Rollback, blockierte Abhängigkeit, unabhängigen Fortschritt, Tombstones und strikt getrennte Feeds zweier Nutzer.

## 9. Clientseitige Synchronisation und Konflikte

- [x] 9.1 Implementiere `clientId`, monotone `clientSequence`, Mutationsabhängigkeiten und die Regel „älteste Mutation je Aggregat zuerst“ und teste aufeinanderfolgende Offline-Änderungen vor dem ersten Upload.
- [x] 9.2 Implementiere den Push-Worker für Erfolg/Replay, `auth-blocked`, Konflikt, permanente Validierungsfehler sowie Backoff bei Timeout, `429` und `5xx`; unabhängige Aggregate müssen weiterlaufen.
- [x] 9.3 Implementiere Pull und atomare Anwendung von Change-Batches plus Cursor in Dexie, einschließlich Abgleich über `originMutationId`, Server-Snapshot und Working Copy; teste lokalen Commit-Abbruch und identischen Pull-Retry.
- [x] 9.4 Implementiere Foreground-Scheduler für App-Start, Sichtbarkeitswechsel, `online`, kurze Verzögerung nach Mutation und manuellen Retry sowie einen IndexedDB-Lease gegen parallele Tabs; verlasse dich nicht auf Background Sync.
- [x] 9.5 Implementiere `401`-Behandlung, die Outbox erhält, Retry stoppt und nur nach erneuter Anmeldung desselben Kontos fortsetzt; teste zwischenzeitliche Anmeldung eines zweiten Kontos ohne Anzeige oder Versand fremder Pending-Daten.
- [x] 9.6 Implementiere Konfliktspeicher und UI für Serverstand übernehmen oder lokale Änderung auf aktuelle Basisversion erneut anwenden; Tombstones und abgeschlossene Workouts dürfen nicht still überschrieben oder wiederbelebt werden.
- [x] 9.7 Implementiere sichtbaren Status für offline, pending, syncing, letzten Erfolg, Auth-Blockade, Validierungsfehler, Konflikt, inaktives Gerät und `upgrade_required` sowie sicheren Service-Worker-Updatehinweis.
- [x] 9.8 Erstelle Playwright-Szenarien für zwei Tabs, Offline-Erfassung, Reload, Verbindungsabbruch, verlorene Bestätigung, Retry, Konflikt, Kontowechsel und Protokoll-Upgrade und bestätige, dass kein Szenario Outbox-Daten verliert.

## 10. Deterministische Insights und Dashboard

- [x] 10.1 Implementiere `weight-average-v1`, `weight-trend-ols-v1` und `nutrition-average-v1` mit Datenabdeckung, Einheit, Zeitraum und Algorithmusversion und sichere fehlende Tage, weniger als drei Gewichte sowie Rundung mit Golden Tests.
- [x] 10.2 Implementiere `training-volume-v1`, Best Set, Workout-Anzahl und `e1rm-epley-v1` für positive Gewichte und 1 bis 12 Wiederholungen; teste ungeeignete Sätze sowie laufende und abgebrochene Workouts.
- [x] 10.3 Implementiere konsistente nutzergebundene Query-Services mit `asOfRevision` für Gewicht, Ernährung, Wochenworkouts und aktives Ziel und teste parallele Mutation während einer Dashboard-Lesetransaktion.
- [x] 10.4 Implementiere Exercise-Progress-Queries für 7, 30, 90 Tage und Gesamt und teste Stable-ID-Zuordnung, Zeitzonenfenster, Tie-Breaker, keine Daten und Nutzerisolation.
- [x] 10.5 Veröffentliche versionierte Insights-Endpunkte und generiere die TypeScript-Verträge; UI und AI müssen bei identischem Nutzer, Zeitraum und Datenstand exakt dieselben Backendkennzahlen erhalten.
- [x] 10.6 Baue Dashboard und Gewichtsdiagramm mit aktuellem Ziel, letztem Gewicht, 7-Tage-Mittel, Trend, Ernährung und Wochenworkouts sowie Exercise-Progress-Ansichten mit Recharts und klaren Zuständen für fehlende Daten.
- [x] 10.7 Cache serverberechnete Insights lokal mit `asOfRevision` und „zuletzt synchronisiert“, kennzeichne sie offline als möglicherweise veraltet und teste, dass ein OpenAI-Ausfall Dashboard und Progress nicht beeinflusst.

## 11. AI Progress Coach mit OpenAI

- [x] 11.1 Implementiere einen gekapselten serverseitigen Responses-API-Adapter mit externem API-Key, konfigurierbarem Modell, Timeout und Tokenlimit, `store=false` sowie ohne Conversation State, Background Mode oder Hosted Tools; prüfe den Request mit Fake-Transport.
- [x] 11.2 Definiere streng schema-validierte, rein lesende Tools für Ziel, Gewicht, Ernährung, letzte Workouts, Kraftübersicht, freigegebene Exercise-IDs und Zeitvergleiche; Schematests schließen Nutzer-ID, SQL, URL, freie Datenbankfilter und Mutationen aus.
- [x] 11.3 Implementiere begrenzte Backend-Fakten mit stabilen `factId`s aus denselben Insights-Ports wie die UI und schließe E-Mail, Auth-Daten, freie Workout-Notizen sowie unnötige Rohreihen aus den Modellinputs aus.
- [x] 11.4 Implementiere den Tool-Loop mit höchstens drei Runden, serverseitiger Argumentvalidierung, Ergebnisgrenzen und aktuellem `IUserContext`; teste unbekannte Tools, manipulierte IDs, zu große Zeiträume und Cross-User-Versuche.
- [x] 11.5 Implementiere und validiere die strukturierte Ausgabe aus Summary, Observations, Fact-Referenzen, Data Gaps und Suggestions; unbekannte Fakten, erfundene Messwerte, Diagnosen und unfreigegebene numerische Kalorien-/Trainingsanweisungen müssen kontrolliert scheitern.
- [x] 11.6 Implementiere `POST /api/v1/coach/responses`, per-IP/per-User Rate Limits, technische Nutzungsmetadaten und redigierte Telemetrie; Prompts, Antworten, Tool-Payloads, Fitnessrohwerte und API-Key dürfen in keinem Erfolgs- oder Fehlerlog erscheinen.
- [x] 11.7 Baue die Online-only Coach-Ansicht mit Frage, Ladezustand, servergerenderten Evidenzwerten, Datenlücken, Retry und verständlichen Providerfehlern; Offline-Modus darf die Trackingnavigation nicht blockieren.
- [x] 11.8 Erstelle Adapter- und API-Tests für Timeout, `429`, `5xx`, ungültige Tool-/Modellantwort, Datenarmut, medizinische Fragen und Nutzerisolation und führe anschließend eine opt-in Eval für Modell-, Latenz- und Kostenkonfiguration durch.

## 12. Sicherheits- und End-to-End-Härtung

- [ ] 12.1 Erweitere die Zwei-Nutzer-Matrix auf alle Fachmodule, Sync-Push/Pull, Konfliktauflösung, Insights, AI-Tools und Account-Operatoren und belege, dass fremde IDs weder Inhalt noch Existenz offenlegen. *Beim Archivieren am 2026-10-24 offen; nicht weiter verfolgt.*
- [x] 12.2 Ergänze Browser-/API-Tests für Cookie-Flags, CSRF, Origin, deaktiviertes produktives CORS, Sessionablauf, Logout, Kontowechsel und persönliche `Cache-Control: no-store`-Antworten.
- [x] 12.3 Ergänze Grenz-, Fuzz- und Parallelitätstests für Freitext-/Requestlimits, Dezimalwerte, kanonische Mutationshashes, doppelte Tagesdaten, Versionskonflikte und unteilbare Workout-Abschlüsse.
- [x] 12.4 Prüfe automatisiert Logs, Traces, Buildartefakte, Images und Compose-Ausgabe auf Test-Fitnessdaten, Prompts, Antworten, Zugangsdaten und Secrets und lasse gefundene Inhalte den Build brechen.
- [x] 12.5 Führe reproduzierbare Lizenz- und Abhängigkeitsrichtlinienprüfungen aus, dokumentiere akzeptierte Lizenzbefunde und verhindere, dass nicht freigegebene Übungsmedien oder RAG-/pgvector-Abhängigkeiten in das MVP gelangen. Automatisierte CVE-Scans sind für dieses private MVP ausdrücklich kein Release-Gate.
- [ ] 12.6 Automatisiere die vollständige Zwei-Nutzer-Journey von Einladung über Offline-Check-in, Planung, Workout, Timer (Trainingsteil gemäß `rebuild-training-logging`), Sync, Dashboard und Coach mit simulierten Fehlern, bevor eine Produktionsfreigabe möglich ist. *Beim Archivieren am 2026-10-24 offen; nicht weiter verfolgt.*

## 13. Container, Linux-VPS und Betrieb

- [x] 13.1 Erstelle reproduzierbare, nicht als Root laufende API- und Migrator-Images mit festen Runtime-Basen und teste Build, Start, Live-/Ready-Checks und schreibgeschütztes Root-Dateisystem soweit möglich.
- [x] 13.2 Erstelle ein internes Caddy-Edge-Image mit dem statischen PWA-Export und einer Konfiguration für gemeinsame Origin, `/api/v1`-Routing, sichere Header und spätere HSTS-Aktivierung; der vorhandene Host-Caddy terminiert TLS und reicht Forwarded Headers über den Edge weiter. Teste statische Fallback-Routen, API-Proxying und die Zwei-Proxy-Kette.
- [x] 13.3 Ergänze das Docker-Compose-Environment im AppHost für `edge`, `api` und `postgres` mit internem DNS, Health Checks, Restart Policies und Volumes und validiere das Ergebnis mit `aspire publish` und `docker compose config`.
- [x] 13.4 Binde Datenbankpasswort, OpenAI-Key, Provisionierungssecret und persistente Data-Protection-Schlüssel über root-geschützte externe Dateien ein; veröffentliche den Edge ausschließlich auf `127.0.0.1:8081` und keinen App-, Datenbank-, OTLP- oder Aspire-Port öffentlich. Der bestehende Host-Caddy bleibt alleiniger Eigentümer von 80/443 und seiner Zertifikate.
- [x] 13.5 Implementiere einen expliziten einmaligen EF-Migrationsschritt vor API-Start mit Schema-Versionsprüfung und teste leere Datenbank, Wiederholung und eine fehlgeschlagene Migration, nach der die API nicht ready wird.
- [x] 13.6 Automatisiere verschlüsselte externe `pg_dump`-Backups in einen privaten Azure-Blob-Container und führe einen dokumentierten Restore von Identity-, Fach-, Sync- und notwendigen Schlüssel-/Konfigurationsdaten in isolierter Umgebung durch.
- [ ] 13.7 Konfiguriere strukturierte Produktionslogs und optionalen internen OTLP-Export, prüfe Restart mit erhaltenen Volumes und simuliere OpenAI- sowie PostgreSQL-Ausfall, damit Readiness und degradierte Funktionen korrekt reagieren. *Strukturierte Logs und optionaler OTLP-Export sind umgesetzt; die Ausfallsimulation ist nicht belegt. Beim Archivieren offen.*
- [x] 13.8 Erstelle einen VPS-Runbook für `gainer.markfort.xyz`, den vorhandenen Host-Caddy, DNS, Firewall, eingeschränktes SSH, Docker/Compose, Secret-Rechte, Deployment, Migration, Health-Smoke-Tests, HSTS, Monitoring und Wiederherstellung; teste, dass der Gainer-Edge nur auf Loopback und extern nur über HTTPS nutzbar ist.
- [ ] 13.9 Baue und publiziere unveränderlich getaggte Images und Compose-Artefakte, dokumentiere Expand/Contract-Regeln und führe einen Rollback auf die vorherigen Image-Tags nach simuliertem fehlgeschlagenem Health Check durch. *Images werden mit `sha-`Tag veröffentlicht; ein Rollback-Test ist nicht belegt. Beim Archivieren offen.*

## 14. MVP-Abnahme und private Freigabe

- [x] 14.1 Führe vollständigen Backend-Build, Frontend-Typecheck/Lint/Build, Unit-, PostgreSQL-, Architektur-, Contract-, Playwright- und Container-Smoke-Test aus und behebe alle offenen kritischen oder hohen Fehler.
- [x] 14.2 Installiere die PWA auf einem physischen iPhone und dokumentiere Check-in, Offline-Start, nächstes Template, Previous Performance, Set Logging, Timer, App-Suspendierung, Reload, Abschluss, Reconnect und erfolgreichen Sync.
- [x] 14.3 Provisioniere zunächst nur das Betreiberkonto und danach einen Testkollegen; verifiziere Einladung, Kontowechsel, getrennte lokale Daten, Cross-User-Isolation und fehlende fachliche Operatoransicht im produktionsnahen Stack.
- [x] 14.4 Prüfe die beispielhafte Cut-Frage Ende-zu-Ende gegen echte Testkennzahlen und weise nach, dass die Antwort Ziel, Gewicht, Ernährung und Kraft korrekt referenziert, Datenlücken benennt und nichts automatisch verändert.
- [x] 14.5 Führe den finalen Azure-Blob-Backup-/Restore- und Image-Rollback-Drill durch, vervollständige Betriebs-, Datenschutz- und OpenAI-`store=false`-Hinweise und gib den privaten MVP erst mit unterschriebener Abnahmecheckliste für Kollegen frei.
