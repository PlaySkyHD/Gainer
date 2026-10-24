## Context

Die PWA liegt unter `apps/web`, die ASP.NET-Core-API und deren serverseitige Fachregeln bleiben führend. `openspec/specs` enthält noch keine archivierten Capabilities. Maßgebliche Ausgangsanforderungen liegen in den aktiven Changes `build-ai-body-training-tracker-mvp`, `add-meal-calorie-tracking`, `add-smart-meals-and-nutrition-targets` und `add-azure-nutrition-label-scanning`. Deren offene Aufgaben werden nicht durch diese Planung als abgeschlossen betrachtet.

Geprüfte Grenzen: `client.ts` verwendet Sessioncookie und Antiforgery; `RequestOriginMiddleware.cs` verlangt für Mutationen einen passenden HTTP(S)-Origin. `SyncChangesController.cs` erlaubt authentifizierten Pull unabhängig vom Writerstatus, während der bestehende PWA-`runSync` vor Pull bei inaktivem Writer zurückkehrt. Für native Erstbefüllung ist daher ein eigener Read-only-Pull erforderlich. IndexedDB und native App teilen keinen Speicher. Für die Umsetzung ist Stable Flutter 3.47.7/Dart 3.13.5 separat unter `artifacts/flutter-sdk` eingerichtet; das vorhandene Master-SDK bleibt unverändert. Die Arbeitsumgebung ist Windows; der Nutzer bestätigt ein iPhone und einen eigenen Apple Developer Account, aber keinen Mac. macOS/Xcode-Builds werden deshalb über GitHub Actions vorbereitet; Signing-Team/IDs/Secrets und tatsächliche Geräteabnahme bleiben offen.

## Goals / Non-Goals

**Goals:** Testbare Parität mit separaten Plattformadaptern; iPhone-Bedienung mit echter Systemintegration; verlustfreier, serialisierter Writer-Wechsel; nachvollziehbare Grenzen zwischen Gainer-Speichern und Apple-Health-/Extension-Nebenwirkungen. HealthKit, Widgets, Live Activities und Shortcuts gehören aufgrund der Nutzerentscheidung zum ersten iOS-Release.

**Non-Goals:** Keine WebView-Verpackung, kein Flutter-Web-Ersatz in diesem Change, kein Hintergrunddienst als Sync-Voraussetzung, keine Übertragung privater Servercredentials an Extensions, keine automatische Health-basierte Kaloriensteuerung. Scope siehe Proposal. Android folgt als gesonderte Phase innerhalb dieses Changes; dessen offene Tasks verhindern nur die vollständige Archivierung, nicht das iOS-Releasegate.

## Decisions

### 1. Flutter-App mit iOS-first Plattformgrenze

`apps/mobile/lib` erhält `data/{models,repositories,services}`, `domain/{models,use_cases}` bei benötigter komplexer Logik und `ui/{core,features}`. Views zeichnen UI; ViewModels verwalten immutable Zustände; Repositories verantworten Daten/Sync. DI erfolgt über Provider/Constructor-Injection und `ChangeNotifier`/`Listenable`. Handgeschriebene immutable Modelle sind für einfache Typen ausreichend; Generatoren werden nur bei nachgewiesenem Bedarf ergänzt. Flutter-Skill-Empfehlungen werden mit dem offiziellen Architekturleitfaden abgeglichen, nicht als Pflicht zur Überarchitektur gelesen.

Eigene typisierte Plattforminterfaces für Capture, SecureSession, Notifications, LiveActivity, Health und ExtensionSnapshot verhindern Apple-Abhängigkeiten in der Fachlogik. iOS-Implementierung in Swift, Widget-/Activity-Oberflächen in SwiftUI. Flutter rendert die App; Systemfunktionen bleiben echte native APIs. Pigeon erzeugt die Dart-/Swift-Brückentypen. Alternative generischer Plugins wurde für komplexe Health-/Activity-/Account-Grenzen verworfen; native Adapter machen Berechtigungen und Nebenwirkungen explizit testbar. Für Android werden später gleichwertige Adapter oder definierte Unsupported-Zustände ergänzt.

Planungsbaseline: iOS 17.0+, iPhone zuerst, responsive iPad-Darstellung ohne zusätzliche Produktjourney. Dynamic Island wird nur auf geeigneter Hardware geprüft; Sperrbildschirmdarstellung ist ebenfalls Pflicht. Die Baseline ist eine begründete Planungsannahme für den gemeinsamen Widget/App-Intent-Stand. Apple-Watch-App bleibt ausgeschlossen.

### 2. Native Auth mit bestehendem Cookie-/CSRF-Vertrag

Kein neuer Token- oder Refresh-Endpunkt. Der Client benutzt die konfigurierte öffentliche HTTPS-API und sendet bei Mutationen den fest konfigurierten erlaubten Frontend-Origin. Origin ist Request-Schutz, kein Nachweis einer Apple-App-Identität. Cookie-Domain/Path/Secure und Redirect-Ziele werden strikt beachtet; keine Credentials an fremde Hosts. Der Client bootstrappt `/api/v1/auth/antiforgery`, verarbeitet Set-Cookie und RequestToken, meldet über `/auth/login` an, validiert `/auth/session` und erneuert das Antiforgery-Paar nach Identitätswechsel. Absolute 12h-Session bleibt unverändert; keine stillschweigende Verlängerung.

Dio mit Cookie-Manager/`cookie_jar` bietet HTTP/Multi-Part/Abbruch und Cookie-Semantik. Die Cookie-Jar bleibt im Speicher; ihr geschützter Session-Checkpoint wird ausschließlich über den Keychain-Adapter abgelegt, keine plaintext PersistCookieJar. Serverablauf hat Vorrang vor lokalem Wiederherstellen. Keychain: gerätegebunden, nicht synchronisiert, verfügbar nur nach Entsperren; Konto-/Serverbindung und Logout-Bereinigung sind zu testen. Erstinstallation invalidiert ggf. alte verbliebene Sessioncheckpoints. Passwörter und CSRF-RequestToken werden nicht dauerhaft gespeichert. Offline-Profilzugang ist lokaler Zugriff und niemals Serverautorisierung.

Cookies, Login, 401, Lockout, Operatorgrenzen, Origin/CSRF und zwei Nutzer werden gegen die reale API geprüft, bevor Fachfeatures entstehen. Alternative Bearer-Auth würde neue Backend-Sicherheitsverträge schaffen und ist für die private Migration nicht erforderlich.

Kontowechsel während eines asynchronen Syncs wird zusätzlich am Antiforgery-Bootstrap gebunden: dessen Response erhält additiv `authenticatedUserId` aus derselben serverseitigen Identität wie der RequestToken (anonym null). Neue kontoabhängige Sync-/Handover-Clients vergleichen diesen Wert mit ihrem unveränderlichen lokalen Konto, bevor sie den Token verwenden. Wechselt das Cookie danach, verweigert die bestehende Antiforgery-Prüfung den identitätsfremden Token. Der Wert ist ausschließlich ein Vergleichssignal, keine vom Client gewählte Autorisierung; die API leitet den Nutzer weiterhin aus der Sitzung ab. Bestehende Clients ignorieren das additive Responsefeld. Neues Clientverhalten ohne diese Serverfähigkeit verlangt ein API-Upgrade statt blindem Upload.

Zusätzlich senden neue native und PWA Sync-/Handover-Clients `X-Gainer-Account-Id` auf jeder kontogebundenen Anfrage, einschließlich des read-only `GET /sync/changes`. Die API vergleicht einen vorhandenen Header mit `IUserContext.UserId` aus genau derselben authentifizierten HTTP-Anfrage und antwortet bei ungültigem oder abweichendem Wert vor Datenrückgabe oder Side-Effect mit `409 account_changed`. Der Header ist nur ein Vergleichswert, nie Autorität; fehlender Header bleibt vorübergehend für ältere Clients zulässig. Dieser Same-Request-Guard schließt insbesondere den Cookiewechsel zwischen Bootstrap und anschließendem Pull-GET und ergänzt, statt ersetzt, Origin-, Cookie- und Antiforgery-Prüfung.

### 3. SQLite statt IndexedDB mit identischer Sync-Semantik

Drift/SQLite bildet kontoabhängige Datenbanken und versionierte Transaktionen ab. Übertragen werden Fachdaten, Envelope-Versionen, lokale/Server-Snapshots, Outbox mit mutationId/clientSequence/Dependencies/Retry, Konflikte, Tombstones und Cursor. Mutationen sind erst nach atomarem Commit sichtbar bestätigt. Datenbankschema und Upgrade-Fixtures werden versioniert; keine Recovery durch blindes Löschen. OS-Dateischutz ist erforderlich; Keychain schützt Sitzungen, nicht automatisch die Datenbank. Backups/Restore müssen Konto-/Installations-ID und veralteten Writerstatus erneut prüfen.

Protokoll v2 bleibt unverändert, einschließlich JSON-Felder, UUIDs, UTC-Zeitstempel, Numerik, Einheiten und kanonischer Payloads. Test-Fixtures aus TypeScript/Backend werden gegen Dart ausgewertet. SyncScheduler reagiert auf Start/Resume/Netzrückkehr und verhindert parallele Läufe; Netzwerkstatus allein gilt nicht als erfolgreiche Verbindung. Read-only-Pull kann ohne Writerrechte laufen. 401 behält Outbox, 409 verlangt sichtbare Konfliktlösung, Replay verwendet dieselbe ID. Timer speichert UTC-Zielzeit; bei Uhränderung wird die UI neu berechnet, kein sekündlicher Hintergrundprozess.

### 4. Abgesicherte Geräteübergabe als additive Backend-Erweiterung

Nur ein manuelles „PWA war synchronisiert“ kann spätere Writes nicht verhindern. Direkter IndexedDB-Import wäre außerdem ein zweites risikoreiches Protokoll. Deshalb Übertragung über Server-Sync plus zeitlich begrenzte Übergabesperre. Neue geplante Endpunkte, heute nicht vorhanden:

| Operation | Vertrag und Wirkung |
| --- | --- |
| `POST /api/v1/sync/handovers` | Quelle sendet stabile requestId, sourceClientId und expectedRevision. Server prüft aktuellen Nutzer/Writer/Revision und sperrt neue Mutationen sowie konkurrierende Übernahmen; Antwort handoverId, zufälliger Einmalcode, frozenRevision, expiresAtUtc. |
| `POST /api/v1/sync/handovers/{id}/complete` | Ziel sendet Einmalcode, targetClientId und caughtUpRevision. Server prüft Nutzer, Ablauf, gesperrten Stand und registriertes Ziel; Writer-Wechsel und Verbrauch erfolgen atomar. Gleicher Retry für dasselbe Ziel liefert das gespeicherte Ergebnis, ein anderes Ziel wird abgelehnt. |
| `POST /api/v1/sync/handovers/{id}/cancel` | Authentifizierte Quelle bricht ab; kein Writer-Wechsel. Idempotent. Nach erfolgreichem Abschluss kein Rückdrehen. |

Handover speichert UserId, SourceClientId, FrozenRevision, RequestId, Code-Hash, Ablauf (15 Minuten), Status und bei Abschluss TargetClientId/Result. Ein Wiederholungs-Start mit derselben requestId muss vor Ablauf denselben nutzbaren Code liefern: zusätzlich kurzzeitig serverseitig DataProtection-geschützter Code, nach Verbrauch/Ablauf entfernt. Kein Code in URLs, Logs, Analytics oder normalen Screenshots. Übergabe durch bewusste Eingabe/temporären QR-Code; Besitz des Codes allein genügt ohne dieselbe authentifizierte UserId nicht. Konkrete DTOs, Fehlercodes und OpenAPI werden in Task 4.1 festgeschrieben.

Begin/Complete/Cancel, MutationProcessor und die bestehende direkte Writer-Registrierung verwenden dieselbe nutzerbezogene Serialisierung in PostgreSQL. Während aktiver Übergabe wird eine passende sichtbare 409-Sperre ergänzt. Die erste erfolgreiche Complete-Transaktion setzt außerdem dauerhaft `HandoverRequired` im nutzergebundenen Sync-State. Danach muss jede Änderung des ActiveClientId über Handover erfolgen; der alte Register-Aufruf mit `takeOverWriting=true` erhält `handover_required` (409), auch aus alten PWA-Tabs/Versionen. Registrieren ohne Übernahme und Refresh des bereits aktiven Writers bleiben erlaubt. Für unmigrierte Konten bleibt bisheriges Verhalten bestehen. Neue PWA ersetzt den heutigen Takeover-Button durch Übergabe-/Recovery-Navigation. Das ist eine explizite Verhaltensänderung für migrierte Konten, kein alleiniger UI-Schutz. Ablauf löst die temporäre Sperre bei nächstem Request deterministisch; Quelle bleibt Writer. Keine verteilte Uhrentscheidung im Client.

Quelle hält während Vorbereitung eine kontoübergreifende Tab-/App-Schreibsperre, beendet laufende Capture-/Edit-Aktionen, wartet auf aktive Sync-Läufe und leert sämtliche offenen Outbox-Zustände nach Konfliktprüfung. Browser-Sync und Übergabe-Drain teilen eine exklusive kontogebundene Web-Lock-/Lease-Grenze. Persistiertes `syncing` wird nur nach bestätigter Quiescence als verwaist mit derselben Mutation-ID zu `pending` zurückgeführt; niemals parallel zu einem lebenden Push. PWA-Retry nach Kill/Antwortverlust dedupliziert vor Begin. Alte DB-Schemata v1/v2 werden zunächst über bestehende Upgrades auf v5 gebracht; fehlende Sequenzen/Retryfelder durch den bestehenden Prepare-Pfad ergänzen. Testmatrix mindestens v1, v2, v3 und v5 mit Outbox, Tombstones und Konflikten; nicht kompatible Frontends verlangen Update/Recovery statt Cutover. Server prüft Revision und aktive Quelle, kann die lokale Outbox selbst aber nicht inspizieren. Schutz gegen lokale spätere Edits liefern die Client-Sperre und der serverseitige Fence. Ein alter PWA-Tab kann anschließend keine Mutation serverseitig anwenden; verbleibende lokale Daten bleiben sichtbar im Recoverypfad.

Ziel meldet sich mit demselben Konto an, registriert ohne takeover, übernimmt nirgends blind alte lokale Daten, lädt alle Batches ab Cursor 0 read-only bis frozenRevision und bestätigt erst danach. Vor Complete persistiert es handoverId, Code, Konto/Host, Ablauf, caughtUpRevision und stabile targetClientId als separaten temporären Keychain-Pending-Record; die Installations-ID bleibt über Retry stabil. Bei Crash zwischen Serverabschluss und lokaler Bestätigung reconciliert es über idempotenten Complete-Retry und Writerregistrierung, bevor es neue Fachwrites erlaubt. Erfolgreiche Wiederholung für das bereits verbrauchte identische Ziel wird vor Ablaufprüfung des ursprünglichen Codes ausgewertet; ein anderes Ziel bleibt abgelehnt. Erst nach bestätigter Reconciliation, Abbruch oder serverbestätigtem Ablauf wird der Pending-Record bereinigt. Für eine Ziel-PWA liegt der entsprechende kurzlebige Recovery-Record im kontoisolierten Browser-Speicher, wird nicht in Export-/Logartefakte übernommen und ist mit ihrer bestehenden Browser-Session-Grenze geschützt. Kein lokales Schreiben vor bestätigter Übernahme. Vor Abschluss einer Rückübergabe werden alte PWA-Daten mit einem frischen kontoisolierten Staging-Stand verglichen; bei Alt-Outbox oder Konflikten kein Überschreiben. Offline-only/nicht erreichbare Quelldaten können nicht automatisch gerettet werden; Quelle behalten und später synchronisieren, kein verlustbehafteter Force-Cutover.

### 5. Apple-Design und Erfassung

Apple-Design-Skill wird in Cupertino-Komponenten, Systemfont und klare Tab-Journeys übersetzt: Training, Ernährung, Körper, Fortschritt; Coach/Operator nach Berechtigung erreichbar. Navigation/Sheets besitzen direkte Rückwege; keine Sperre während Animation. Große Schrift und VoiceOver testen, Touchflächen mindestens 48 logische Pixel, kontrollierter Kontrast auch auf translucenten Flächen. Reduzierte Bewegung ersetzt räumliche Übergänge; Haptik nur bei Commit/Timer/Erfolg. Fenster-Constraints statt Gerätetyp- oder Orientierungschecks bestimmen das Layout.

Capture-Adapter nutzt AVFoundation für Barcode/Kamera und PHPicker für Fotoauswahl. Kamera nur bei Bedarf, keine pauschale Bibliotheksberechtigung für den Picker. HEIC-/Bilddaten werden auf unterstütztes Uploadformat und Grenzen normalisiert; serverseitige Prüfung bleibt autoritativ. Drafts bleiben zielneutral; Scan/AI-Estimate darf nie automatisch speichern. Swift-/Dart-Temporärdaten und Dateien werden bei Erfolg, Fehler und Abbruch bereinigt; reale iPhone-Dateiformate werden geprüft.

### 6. Timer, Widgets, Live Activities und Shortcuts

UserNotifications plant eine lokale Meldung je workoutId/timerGeneration ohne sensible Nutzlast, ersetzt sie bei Timeränderung und löscht sie bei Ende/Abmeldung. Permission wird erst bei Aktivierung angefragt. Focus/OS-Einschränkungen werden als Zustellgrenzen erklärt. Persistierte Zielzeit ist führend, UI-Tick dient nur der Darstellung.

ActivityKit erzeugt freiwillig eine Activity pro aktivem Workout mit allgemeinen Status-/Zeitdaten. SwiftUI-Zeitdarstellung nutzt Enddatum statt laufender Dart-Updates; kein APNs-Dienst und keine Remote-Push-Activity in diesem Change. Beenden bei Konto-/Workout-Ende; nach Prozessende ist eine sofortige Bereinigung ohne Ausführung nicht garantierbar: staleDate und Systemablauf begrenzen alte Anzeige, Resume reconciliert. Keine Health-/Ernährungsdaten oder Kontodetails in der Activity. Details nur nach separater Anzeige-Freigabe; Standardeinstellung ist neutral.

WidgetKit bietet kleine/mittlere „Training öffnen“-/„Check-in öffnen“-Widgets. App Group speichert ausschließlich versionierte neutrale Routen-/Verfügbarkeits-Snapshots, Generation und Aktualisierungszeit, keine Token oder vollständigen Fachdaten. Logout löscht Snapshot und fordert Timeline-Reload an; verzögerte OS-Updates bleiben durch neutrale Darstellung datensparsam. Deep Links werden immer gegen die aktuelle Sitzung/Route validiert.

App Intents öffnet Training, Check-in oder Ernährung über dieselbe Routergrenze. Keine stille Mutation aus Extension oder Siri; Speichern/Starten bestätigt der Nutzer in der entsperrten App. Universal Links für Einladung werden bei kontrollierter Domain und Associated-Domains-Konfiguration vorbereitet; Token-Eingabe bleibt vollständiger Fallback ohne automatische Annahme. Native Routeinputs sind untrusted.

### 7. HealthKit: definierte Richtung und Nebenwirkungen

Read: ausschließlich Body-Mass-Proben im explizit gewählten Zeitraum; Review zeigt Zeit, Einheit und Quelle. Confirm erzeugt normale eigene Check-ins mit Outbox. Kein Heart-Rate-, Ernährungs- oder automatischer Hintergrundimport. Ein lokaler Importledger bindet Health-UUID an Konto und Gainer-Check-in; Auswahl bei mehreren Messungen/Tageskollisionen statt stiller Überschreibung. Leseverweigerung lässt sich nicht sicher aus leeren Ergebnissen unterscheiden. Vor Confirm Hinweis auf serverseitiges Speichern; Review-Abbruch verwirft Auswahl.

Write: nur abgeschlossene eigene Workouts, explizit vom Nutzer exportiert, Start/Ende und passende Trainingstype; keine erfundene Energie-/Pulsberechnung. Separates Exportledger mit stabiler app-/konto-/workoutbezogener Sync-ID und exportierter Version; Health-Metadaten verwenden eine opaque Zuordnung, keine Email. HKMetadataKeySyncIdentifier und HKMetadataKeySyncVersion liefern Apples systemseitigen Duplikat-/Updatepfad, inklusive Crash nach Health-Write. Retry nutzt dieselbe ID/Version, keine frische Export-ID; das tatsächliche Verhalten für HKWorkout wird im Swift-Spike bewiesen. HealthKit ist geräteweit, nicht pro Gainer-Konto: Kontowechsel verwirft Review und exportiert nie ungefragt ein anderes Konto. Entzug der Berechtigung, extern gelöschte Samples und Reinstallation werden als eigene Recoveryfälle getestet; keine pauschale Löschung bei Logout. Health-Schreiben ist nicht Teil der SQLite-/Servertransaktion, deshalb eigener Retry-/Resultzustand.

### 8. Dependencies, Toolchain und Team

Minimal geplante Dependencies: Provider (DI/UI), Drift/SQLite (Transaktionen), Dio + Cookie-Manager/Cookie-Jar (Transport), Pigeon (typisierte Apple-Brücken), Flutter `integration_test`/`flutter_test`. Jede konkrete Version wird zu Implementierungsbeginn gegen eine ausgewählte Flutter-Stable-Version geprüft, gelockt und in CI reproduziert. iOS-Frameworks: Security, AVFoundation, PhotosUI, UserNotifications, ActivityKit, WidgetKit, SwiftUI, AppIntents, HealthKit. Keine Client-OpenAI-SDKs oder AI-Keys. Zeitzonen-Normalisierung muss IANA-Zeitzonen für Fortschrittsqueries erhalten; ein passender Adapter wird mit Sommerzeit-Fixtures geprüft.

Hauptagent legt Tasks/Dateizuständigkeiten fest und prüft unabhängig. GPT-6-Luna implementiert Dart, Swift, Backend-Ergänzungen, Tests und Nachbesserungen. Gemeinsame Schema-/API-Dateien werden nacheinander bearbeitet. Kein Taskhaken allein aufgrund eines Luna-Berichts; Diff, fokussierte Tests und relevante reale Nachweise sind erforderlich. Überlappende aktive Changes zuerst inventarisieren, keine Nutzeränderungen zurücksetzen.

## Risks / Trade-offs

- [Erweiterter Apple-Scope] → Eigene vertikale Meilensteine; sämtliche vier Integrationen bleiben vor erstem iOS-Release Pflicht, Android folgt erst danach.
- [macOS/Xcode/Gerät noch nicht vorhanden] → Toolchainzugang als erstes Enablement-Task; ohne Nachweis bleibt iOS-Release offen, Windows-Arbeit ersetzt es nicht.
- [Migration bei Offline-only-Daten] → Cutover blockieren und Quelle behalten; kein automatischer Zugriff auf Safari-IndexedDB behaupten.
- [Neue serverseitige Übergabesperre] → Gemeinsame Nutzerlock-Strategie, Timeout-/Race-/Retry-/Cross-User-Integrationstests und reversible additive Migration vor App-Rollout.
- [Cookie-Checkpoint und OS-Restore] → Keychain-Hostbindung, serverseitige Sessionprüfung, sichere Fehlerzustände und Reinstalltests; keine neue Auth-Ausnahme.
- [Health-/Extension-Nebenwirkungen] → Getrennte Ledger/Generationen, Review/Consent, echte Device-Tests und klare Unsupported-/Denied-Zustände.
- [OS verzögert Notification/Widget/Activity] → Zeitbasierte Darstellung und neutrale stale Daten, keine garantierten Hintergrundaktionen.

## Migration Plan

| Meilenstein | Ergebnis | Abhängigkeit/Gate |
| --- | --- | --- |
| M0 | Paritätsmatrix, Stable-SDK, Mac/Xcode/Device-Zugang, private Bundle-/Capability-Konfiguration | Taskgruppe 1; keine Secrets im Repository |
| M1 | Native Login/API, SQLite/Sync und serialisierte Handover-Operationen | Taskgruppen 2–4; Zwei-Nutzer-/Crash-/Race-Tests |
| M2 | Vollständige Fachjourneys und iPhone-Design | Taskgruppe 5; Paritäts-/Layoutabnahme |
| M3 | Native Capture/Timer plus alle Apple-Integrationen | Taskgruppen 6–8; reales iPhone einschließlich Permissions |
| M4 | Private iOS-Beta bereit, Cutover/Rückwechsel geprüft | Taskgruppe 9; unabhängiges iOS-Releasegate |
| M5 | Android-Port und eigene Abnahme | Taskgruppe 10; nach M4, keine Sperre für iOS |

Deploy zuerst additive API/DB/Verträge sowie PWA-Übergabe-/Recoveryhilfe, bestehende PWA-Routine weiter testen. Danach native Beta mit gesondert freigegebener Verteilung. Nutzer einzeln über Handover migrieren; PWA behält Daten und Recoveryzugang. Bei Fehlern Beta-Rollout stoppen, aktive Sperren sicher canceln/auslaufen lassen; abgeschlossene Wechsel niemals durch DB-Rollback rückgängig machen. Native Writer erst nach leerer Outbox zurück an PWA übergeben; keine Deinstallation als Recovery. Handover-Tabellen nicht entfernen, solange aktive/abgeschlossene Recovery-Verträge gebraucht werden. PWA-Stilllegung ist nicht Teil dieses Changes.

## Open Questions

Deferrable Umgebungsdaten: konkretes Apple-Team/Bundle-ID/App-Group-ID, Test-iPhone-Modell und kontrollierte Universal-Link-Domain. Für GitHub Actions ist macOS-15 mit Xcode 26.3 vorgesehen; verfügbare Version und Secret-/Environment-Konfiguration werden vor Ausführung geprüft. Private Beta-Verteilung wird als TestFlight vorbereitet; externe Uploads erfolgen gesondert nach Freigabe. Fehlende Teamdaten blockieren Signing/Verteilung, nicht lokale Dart-/Backend-Umsetzung.

## Quellen und Quality Gate

- Lokales Gate: `artifacts/flutter/migration-quality-gate.md`; Scope-Erweiterung dieses Changes hat Vorrang vor dessen früher als optional geführten Apple-Ideen.
- https://docs.flutter.dev/app-architecture/recommendations
- https://docs.flutter.dev/deployment/ios (macOS/Xcode-Buildgrenze)
- https://docs.flutter.dev/testing/integration-tests (keine pauschale Legacy-Driver-Erweiterung im App-Einstieg)
- https://developer.apple.com/documentation/activitykit (ActivityKit und SwiftUI/Widget-Extension)
- https://developer.apple.com/documentation/healthkit
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier (systemseitige Sync-ID und Version)
- https://developer.apple.com/documentation/widgetkit
- https://developer.apple.com/documentation/appintents
- https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- https://developer.apple.com/documentation/security/keychain-services

Plattformspezifische API-Verfügbarkeiten/Entitlements werden zusätzlich beim konkreten SDK-/Xcode-Pinning geprüft, bevor Swift-Implementierung erfolgt.
