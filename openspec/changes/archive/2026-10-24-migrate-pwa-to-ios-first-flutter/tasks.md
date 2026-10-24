## 1. M0: Baseline und Ausführungsumgebung

Alle Implementierungstasks werden an GPT-6-Luna delegiert; der Hauptagent prüft unabhängig anhand der genannten Specs und `artifacts/flutter/migration-quality-gate.md`. Jeder Task benötigt grüne betroffene Builds/Tests, bevor sein Haken gesetzt wird. Gemeinsame API-/Schema-Dateien werden nacheinander bearbeitet; Commits verwenden Conventional Commits. Die Haken dokumentieren unabhängig geprüfte Abnahme; implementierter Code mit noch fehlenden Nachweisen bleibt offen.

- [x] 1.1 PWA-Paritätsmatrix für sämtliche Journeys samt Zuordnung zu aktiven OpenSpec-Anforderungen und existierenden Tests erstellen; uncommitted Scanner-/Ernährungsänderungen sowie offene Alt-Tasks dokumentieren, ohne sie zu überschreiben.
- [x] 1.2 Konkrete Flutter-Stable-/Dart-/Xcode-Versionen und Dependencies prüfen und reproduzierbar pinnen; lokales Master-SDK nicht still umstellen. Ergebnis mit `flutter doctor`, Lockfiles und sauberem Restore prüfen.
- [x] 1.3 macOS/Xcode-Runner, Signing-Verantwortung, physisches iPhone und iOS-17+-Gerätematrix dokumentieren; fehlende iOS-Nachweise ausdrücklich als offen ausweisen, niemals durch Windows ersetzen.
- [x] 1.4 `apps/mobile` mit iOS-Target, MVVM/Repositories/Services, Provider-DI, Pigeon-Plattforminterfaces und Analyse-/Testkonfiguration anlegen; App-Smoke und Abhängigkeitsgrenzen prüfen.
- [x] 1.5 Mac-CI für iOS-Simulatorbuild und Dart-Checks sowie Backend-/PWA-Regressionchecks einrichten; Lockfiles und Stable-Pinning in sauberer CI verifizieren.

## 2. M1: API und sicherer nativer Zugang

Referenz: `native-mobile-client`; vor Fachjourneys abzuschließen.

- [x] 2.1 Dart-Modelle und Transportgrenzen aus OpenAPI erstellen, DTO-/Numerik-/UUID-/UTC-Fixtures gegen Backendverträge prüfen; IANA-Zeitzonen für Analytics einschließlich Sommerzeit nachweisen.
- [ ] 2.2 ~~HTTPS-/Cookie-/Origin-/CSRF-Transport und additive authenticatedUserId-Bindung im Antiforgery-Bootstrap implementieren; neue Sync-/Handover-Clients senden zusätzlich X-Gainer-Account-Id auf allen Scoped-Reads und -Writes, serverseitig gegen IUserContext derselben Anfrage validiert. Optionale Header-Abwesenheit bleibt für Legacy-Clients kompatibel. Reale API-Tests für Login → Session → Mutation → Logout, A→B-Race inklusive Pull-GET, falschen/fehlenden Origin, CSRF, Cookie und fremde Redirecthosts ausführen.~~ *Entfällt: Cookie-, CSRF- und Origin-Schutz wurden durch Bearer-Tokens ersetzt (`mobile-token-auth`); `X-Gainer-Account-Id` ist umgesetzt.*
- [x] 2.3 Swift-Keychain-Adapter und geschützten Sessioncheckpoint implementieren; Ablauf, Keychain-Sperre, Erstinstallation/Restore, Logout und Server-/Kontobindung prüfen; keine plaintext Cookie-Jar oder Passwortpersistenz.
- [x] 2.4 Login, Reauth und Offline-Profilzugang implementieren; 401 mit ausstehender Outbox und Kontowechsel A/B im Widget-/API-Test prüfen, einschließlich verweigerter fremder Ressourcen.
- [x] 2.5 Einladungsannahme und Operator-Journeys portieren; Universal-Link-Konfiguration und Token-Eingabe-Fallback prüfen, ungültige Links/Token und fehlende Operatorrolle gegen echte API testen. *Ohne Universal Links; die Einladung wird als Code oder eingefügter Link angenommen.*

## 3. M1: Native Datenbank und Sync-Parität

Referenz: `native-offline-migration`; Grundlage für alle fachlichen Offline-Writes.

- [x] 3.1 Kontoabhängige Drift-Datenbanken mit Fachdaten, Envelopes, Outbox, Konflikten, Cursor und Tombstones anlegen; zwei Konten und Schema-Upgrade/-Rollback mit gespeicherten Mutationen testen.
- [x] 3.2 Atomaren lokalen Mutation-Commit mit stabilen IDs/Sequenzen/Dependencies implementieren; Fehler zwischen Fach-/Outbox-Write und Prozessende nach Bestätigung über Persistenztests prüfen.
- [x] 3.3 Read-only-Pull ohne aktive Writerrechte, Pagination sowie atomaren Batch-/Cursor-Commit implementieren; Abbruch-/Replay-/Tombstone-Fixtures gegen API prüfen.
- [x] 3.4 Writerregistrierung und Push-Reihenfolge/Retry portieren; Timeout nach Serverannahme und Prozessende ergeben genau eine fachliche Wirkung; Protokollfehler und inaktiver Writer zeigen blockierten Zustand.
- [x] 3.5 Konfliktresolver und permanente Fehlerzustände portieren; neue bestätigte Konfliktlösung mit neuer Mutation-ID/current base und Fortschritt unabhängiger Aggregate testen.
- [x] 3.6 Start-/Resume-/Netzrückkehr-Scheduler ohne parallele Sync-Läufe implementieren; echte iPhone-Suspend-/Netzverlust-/Sessionablauftests mit A/B durchführen, ohne Hintergrund-Sync-Zusage.

## 4. M1: Kontrollierte Übergabe und Rückwechsel

Referenz: `native-offline-migration`; nach 2 und 3. Neue Endpunkte sind additive geplante Verträge, keine bestehenden APIs.

- [x] 4.1 Handover-DTOs/Fehlercodes, EF-Migration und begin/complete/cancel-Verträge implementieren; OpenAPI und bestehende Clients regenerieren, Vertragskompatibilität prüfen.
- [x] 4.2 Gemeinsame Nutzer-Serialisierung und dauerhaftes HandoverRequired nach erstem Complete für Handover, MutationProcessor und direkte Writer-Übernahme ergänzen; Postgres-Tests für Race, Late-Write, Cross-User und direkte Legacy-Übernahme nach Complete ausführen; unmigrierte Konten behalten ihren bisherigen Pfad.
- [x] 4.3 Befristung, geschützten Einmalcode, Start-/Complete-/Cancel-Idempotenz implementieren; Antwortverlust, falsches Ziel, fremdes Konto, Ablauf und mehrfachen Verbrauch testen; Codes nicht loggen.
- [ ] 4.4 ~~PWA-Übergabeoberfläche mit Edit-/Tab-/Sync-Lock und Quiescence bauen; verwaistes syncing nach Kill mit derselben ID zu pending wiederanlaufen lassen, dann Drain/Konflikt-/Revisionsprüfung. Playwright prüft Antwortverlust nach Serverannahme, lebende/parallele Tabs, pending/conflict/401/Offline und Datenbestand bei Abbruch.~~ *Entfällt: Die PWA ist entfernt (`remove-web-app`).*
- [x] 4.5 Native Übergabe mit gleicher Sitzung, Zielregistrierung ohne takeover, Pull bis frozenRevision und temporärem Keychain-Pending-Record vor Confirm implementieren; stabile targetClientId und Reconciliation nach erfolgreichem Complete/Antwortverlust/Kill sowie Expiry testen, ohne Writes vor bestätigtem Writerstand.
- [ ] 4.6 ~~Rückübergabe nativ → PWA und Staging-/Recoveryprüfung implementieren; bisherigen PWA-Takeover-Button ersetzen und kurzlebigen Ziel-Recovery-Record schützen/bereinigen; Pending-Outbox, veraltete Daten und verlorene Abschlussantwort dürfen weder Daten löschen noch Writer unbemerkt wechseln.~~ *Entfällt: Die PWA ist entfernt (`remove-web-app`).*
- [ ] 4.7 ~~End-to-End-Migration mit zwei Nutzern, zwei Installationen und alter PWA-Tabinstanz prüfen; PWA-Schema-Fixtures v1/v2/v3/v5 mit fehlenden Sequenzen, Outbox/Konflikten/Tombstones durch Upgrade → Drain → Handover → Vollpull testen. Alte Frontends verlangen Update/Recovery; alte Takeover-Aufrufe bleiben nach Migration serverseitig gesperrt.~~ *Entfällt: Die PWA ist entfernt (`remove-web-app`).*

## 5. M2: Fachjourneys und Apple-Design

Referenz: `native-mobile-client`; Tasks einzeln anhand der Paritätsmatrix abnehmen.

- [x] 5.1 Cupertino-Navigation, Theme/Systemfont, Safe Areas, Shared-Formzustände und Tab-Journeys bauen; Widget-/Sichtprüfung für hell/dunkel, Tastatur, Rotation, große Schrift und unterbrechbare Zurück-Geste.
- [x] 5.2 Körperziele und tägliche Check-ins portieren; Offline-Validierung, Einheiten, Datum/Zeitzonen und Sync-Fixtures aus Altanforderungen prüfen.
- [x] 5.3 Katalog/eigene Übungen, Templates und Rotation portieren; Offline-CRUD und historische Snapshot-Unveränderlichkeit im Integrationstest nachweisen.
- [x] 5.4 Workout-Ausführung, Satzlogging und Previous Performance portieren; Prozessabbruch während Offline-Workout und unveränderte vorangegangene Leistung prüfen.
- [x] 5.5 Workout-Abschluss/Verwerfen und Historie portieren; invalides/abgebrochenes Speichern und historische Snapshots testen.
- [x] 5.6 Ernährungstage, vier Mahlzeiten, manuelle Komponenten und Food-Suche portieren; Snapshot-/Einheiten-/Offline-/Fehlerfälle gegen bestehende Ernährungstests prüfen.
- [x] 5.7 Wiederverwendbare Gerichte, Zielpläne, zuletzt verwendete Lebensmittel und bestätigte AI-Mahlzeitenschätzung portieren; Review-Abbruch ohne Mutation sowie bestehende Smart-Meals-Regeln testen.
- [x] 5.8 Dashboard/Übungsfortschritt und lesenden Coach portieren; Kennzahlen ausschließlich serverseitig abrufen, Offline-/Retry-/Unauthorized-Zustände und unveränderten AI-Key-Schutz prüfen.
- [x] 5.9 VoiceOver-Semantik, 48-Pixel-Touchflächen, Kontrast, große Schrift und reduzierte Bewegung auf iPhone prüfen; Paritätsmatrix für alle Journeys mit konkreten Test-/Screenshotnachweisen vervollständigen.

## 6. M3: Native Kamera, Haptik und Timer

> Timer-Tasks 6.4 und 6.5 sowie Live-Activity-Tasks 7.2, 7.3 und 7.6 (Workout-/Pausenanteil) werden durch `rebuild-training-logging` (Gruppe 11) umgesetzt und abgenommen.

Referenz: `apple-native-training`; nach den jeweiligen Fachjourneys.

- [x] 6.1 AVFoundation-Barcode-/Capture- und PHPicker-Brücken mit Berechtigungsbeschreibungen implementieren; tatsächliche iPhone-Kamera, Ablehnung, Abbruch und Resume ohne doppelte Kamerasession prüfen.
- [x] 6.2 Normalisierung/Multipart-Upload und Labelscan-Review anbinden; HEIC/unterstützte Formate, Grenzen, Metadatenbereinigung, Timeout und Abbruch testen; keine Bilder in Outbox/Logs/bleibenden Temp-Dateien.
- [x] 6.3 Haptik-Adapter für bewusste Commits/Timer und unmittelbares Pressfeedback implementieren; reduzierte Bewegung und deaktivierte/fehlende Haptik beeinträchtigen Bedienung nicht.
- [x] 6.4 Persistierten UTC-Pausentimer mit Zielzeit-/Uhrwechsel-/Resume-Verhalten implementieren; Geräteprüfung nach Suspend, Prozessende und Neustart durchführen.
- [x] 6.5 UserNotifications-Adapter mit Permission-Aktivierung und Timer-Generation implementieren; Denied, Reschedule, Cancel, Workout-Ende, Kontowechsel und verspätete OS-Zustellung auf iPhone prüfen.

## 7. M3: Live Activities, Widgets und Shortcuts

Referenz: `apple-native-training`; für ersten iOS-Release verpflichtend.

- [x] 7.1 SwiftUI-Extension, App-Group-/Bundle-Konfiguration und typisierten neutralen Snapshotvertrag einrichten; kein Cookie, Auth-Token oder vollständiger Fitnessdatensatz darf in Shared Storage erscheinen.
- [x] 7.2 ActivityKit-Adapter und Workout-/Pause-Ansichten für Sperrbildschirm und Dynamic Island implementieren; Start/Update/Ende, Denied/Unavailable und gespeicherte Zielzeit statt Dauerticks testen.
- [x] 7.3 Activity-Reconciliation, staleDate/Ende und Konto-/Workoutwechsel implementieren; Prozessende, Systemende und Resume auf iPhone prüfen; veraltete Anzeige und fehlende Ausführung nicht als aktuellen Zustand ausgeben.
- [x] 7.4 Kleine/mittlere Training-/Check-in-Widgets mit neutralen Einstiegen erstellen; Timeline-Reload, veraltete Snapshots, Logout und Konto A→B ohne Datenoffenlegung prüfen.
- [x] 7.5 App Intents für Training/Check-in/Ernährung und gemeinsame Deep-Link-Routergrenze implementieren; ohne Sitzung, gesperrtes Gerät und manipulierte Routeinputs testen, keine stille Mutation.
- [x] 7.6 Native Systemoberflächen mit VoiceOver, hell/dunkel, Dynamic-Island-/Nicht-Dynamic-Island-Geräten abnehmen; Standarddarstellung ohne sensible Details und explizite Detailfreigabe nachweisen.

## 8. M3: HealthKit

Referenz: `apple-health-integration`; für ersten iOS-Release verpflichtend, aber für Nutzer freiwillig.

- [x] 8.1 HealthKit-Entitlement, Usage Descriptions und Swift-Brücke implementieren; Body-Mass-Read und Workout-Write getrennt anfordern, Denied/Unavailable/Entzug ohne blockierte Kernjourney prüfen.
- [x] 8.2 HKWorkout-Spike mit stabilen HKMetadataKeySyncIdentifier/SyncVersion durchführen; identischer Save-Retry nach simuliertem Crash erzeugt auf iPhone keine Duplikate. Keine Implementierungsfreigabe für einen unbelegten Exportpfad.
- [x] 8.3 Gewichtsabfrage mit begrenztem Zeitraum, Einheiten-/Datumsnormalisierung und Quelle im Review bauen; leere Ergebnisse nicht als sichere Read-Denial oder Nullgewicht behandeln.
- [x] 8.4 Bestätigten Check-in-Import und kontoabhängiges Health-Ledger implementieren; gleiche Probe, Tageskollision, Review-Abbruch, Konto A→B und atomarer Outbox-Commit testen; Server-Sync-Hinweis vor Bestätigung.
- [x] 8.5 Bestätigten Export abgeschlossener Workouts mit eigener Result-/Retry-Verwaltung implementieren; unbekannte Energie/Puls weglassen, stable IDs nach Reinstall/Restore, externe Samplelöschung und Berechtigungsentzug prüfen.
- [x] 8.6 HealthKit auf physischem iPhone mit getrennten Testkonten abnehmen; keine automatischen Imports/Exports/Health-Löschungen bei Logout und keine Dateninhalte in normalen Logs nachweisen.

## 9. M4: iOS-Releasegate und privater Übergang

Referenz: `mobile-quality-release`; abhängig von allen Gruppen 1–8.

- [x] 9.1 Format/Analyse/Unit-/Widget-/reale API-Integrationstests und iOS-Simulatorbuild reproduzierbar ausführen; Testlogs ohne Secrets sichern und alle offenen/failing Checks ehrlich ausweisen.
- [x] 9.2 Physische iPhone-End-to-End-Suite durchführen: Flugmodus, Kill/Resume, 401, Konflikt, Replay, Übergabe/Rückwechsel, Kamera, Notifications, Health, Widget, Activity und Shortcut; mindestens zwei Nutzer prüfen. *Die Rückübergabe an die PWA entfällt.*
- [x] 9.3 Permissions-/Datenschutzhinweise, Bild-/Health-Datenfluss, TestFlight-Metadaten und signierbaren privaten Beta-Build vorbereiten; native Capabilities/Privacy-Manifeste mit gewähltem SDK prüfen, noch kein externer Upload.
- [ ] 9.4 ~~Runbook für additive API-/PWA-Auslieferung, nutzerweisen Cutover, Recovery und Beta-Rollback schreiben und anhand eines Testkontos ohne Datenverlust durchspielen; PWA-Stilllegung ausschließen.~~ *Entfällt: Die PWA ist entfernt (`remove-web-app`).*
- [x] 9.5 Hauptagent prüft Diff, Paritätsmatrix, Apple-Design, Releasebuild und Gerätenachweise unabhängig; erst nach bestandenen Gruppen 1–8 und 9.1–9.4 iOS-Freigabe protokollieren. Jede fehlende Apple-Integration hält dieses Gate offen.
- [x] 9.6 Nach separater Nutzerfreigabe private Beta hochladen/verteilen und erste kontrollierte Übergabe prüfen; keine automatische öffentliche Veröffentlichung.

## 10. M5: Android nach iOS

Diese Gruppe startet nach iOS-Gate 9.5; sie blockiert iOS-Freigabe nicht, bleibt aber für vollständige Change-Archivierung erforderlich.

- [ ] 10.1 ~~Android-Target und kompatible SDK-/Dependency-Versionen pinnen; Plattforminterfaces anbinden und Build-/DI-Abhängigkeitsregeln prüfen.~~ *Entfällt: Android ist nicht geplant; die iOS-App ist der einzige Client.*
- [ ] 10.2 ~~Sichere Sitzungsspeicherung, Kamera/Picker, Berechtigungen, Haptik und lokale Notifications für Android implementieren; Denied-/Abbruch-/Lifecycle-Fälle auf Gerät testen.~~ *Entfällt: Android ist nicht geplant; die iOS-App ist der einzige Client.*
- [ ] 10.3 ~~Apple-spezifische Integrationen als klare Unsupported-Zustände behandeln, ohne tote Schaltflächen oder behauptete Android-HealthKit-Parität; Training/Ernährung funktionieren vollständig.~~ *Entfällt: Android ist nicht geplant; die iOS-App ist der einzige Client.*
- [ ] 10.4 ~~Gemeinsame Fachjourneys, Zwei-Konto-Isolation, Offline-/Replay-/Konflikt-/Handover-Verhalten auf Android abnehmen; eigene Layout-/Accessibility- und Releasebuild-Prüfung durchführen.~~ *Entfällt: Android ist nicht geplant; die iOS-App ist der einzige Client.*
- [ ] 10.5 ~~Android-Runbook und getrenntes Freigabeprotokoll erstellen; externen Upload nur nach separater Freigabe, Change erst nach allen verpflichtenden Tasks archivieren.~~ *Entfällt: Android ist nicht geplant; die iOS-App ist der einzige Client.*
