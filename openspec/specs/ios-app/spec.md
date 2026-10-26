# ios-app Specification

## Purpose
Gainer ist eine Flutter-App für iOS und der einzige Client der API. Sie nutzt native Kamera, Widgets und Kurzbefehle als kontrollierte Einstiege und wird über CI und TestFlight ausgeliefert.

## Requirements

### Requirement: Private Kernreise in der App

Die App MUST Zugang, Einladungsannahme, berechtigte Kontooperator-Funktionen, Körperziel und Check-ins, Übungskatalog, Pläne und Rhythmus, Krafttraining und Cardio, Ernährung mit Gerichten, Tagesvorlagen, Zielen, Suche, Barcode und Etikett, Statistik und den lesenden Coach anbieten. Historische Trainings DÜRFEN durch spätere Änderungen an Plänen oder Übungen nicht verändert werden. Onlinepflichtige Funktionen MUST offline einen erklärten Zustand mit Retry statt erfundener Ergebnisse anzeigen.

#### Scenario: Plan nach dem Training ändern
- **GIVEN** ein aus dem Plan „Push“ gestartetes und beendetes Training
- **WHEN** der Nutzer den Plan „Push“ danach bearbeitet
- **THEN** zeigt das Training im Tagebuch weiterhin seine eigenen Übungen und Sätze

#### Scenario: Coach ohne Verbindung
- **GIVEN** lokale Trackingdaten und keine Netzwerkverbindung
- **WHEN** der Nutzer den Coach öffnet
- **THEN** bleiben lokale Trackingfunktionen nutzbar und eine neue Coach-Anfrage wird als online erforderlich mit Retry angezeigt

### Requirement: Kontogebundene Requests

Die App MUST eingeladene Konten über Bearer-Tokens nutzen (siehe `account-access`). Sync- und Übergabe-Requests MUST `X-Gainer-Account-Id` mit der lokalen Konto-ID mitsenden. Weicht der Header vom angemeldeten Nutzer ab, MUST die API vor Datenrückgabe oder Seiteneffekt `409 account_changed` liefern; Requests ohne Header bleiben zulässig. Der Header ersetzt keine Anmeldung. Ein Kontowechsel DARF Daten des vorherigen Kontos weder anzeigen noch senden.

#### Scenario: Fremde Daten bleiben isoliert
- **GIVEN** Konto A besitzt lokale und ausstehende Daten
- **WHEN** Konto B angemeldet wird oder eine Ressource von A anfordert
- **THEN** zeigt und sendet der Client ausschließlich B-Daten und die API verweigert fremde Ressourcen unabhängig von übergebenen IDs

#### Scenario: Konto wechselt während eines Syncs
- **GIVEN** ein Sync-Client hat Konto A lokal gebunden, der Request trägt aber den Access-Token von Konto B
- **WHEN** der Client `GET /api/v1/sync/changes` oder eine Sync- bzw. Übergabe-Schreiboperation mit `X-Gainer-Account-Id: A` sendet
- **THEN** antwortet die API mit `409 account_changed` vor Datenrückgabe und vor jeder Zustandsänderung, und derselbe Request mit dem Token von A funktioniert

### Requirement: iOS-Bedienung und zugängliches Layout

Die iOS-App MUST Systemtypografie, nachvollziehbare Navigation einschließlich Zurück-Geste, direktes Touch-Feedback und sinnvolle Haptik bieten. Layouts MUST Safe Areas, Tastatur, große Schrift, VoiceOver, Hell/Dunkel und reduzierte Bewegung berücksichtigen. Gesten und Übergänge MUST abbrechbar bleiben.

#### Scenario: Große Schrift und reduzierte Bewegung
- **GIVEN** große Systemschrift und reduzierte Bewegung sind aktiviert
- **WHEN** der Nutzer einen Ernährungseintrag bearbeitet und per Zurück-Geste navigiert
- **THEN** bleiben Pflichtfelder und Aktionen erreichbar, keine Inhalte überlaufen und die Rücknavigation bleibt ohne erzwungene große Bewegung verständlich

#### Scenario: Einladung in der App öffnen
- **GIVEN** ein gültiger Einladungslink oder ein vom Nutzer eingefügter Einladungstoken
- **WHEN** die App die Einladung nach Nutzeraktion öffnet
- **THEN** erfolgt keine automatische Annahme, der Nutzer bestätigt sein Passwort und ungültige oder abgelaufene Einladungen zeigen einen Fehler ohne Token-Logging

### Requirement: Native Kamera und Fotoauswahl

Die App MUST nutzerinitiierte Kamera-/Barcode-Erfassung und systemeigene Fotoauswahl anbieten, Berechtigungen bedarfsgerecht anfordern und manuelle Eingabe bei Ablehnung erlauben. Label-/AI-Bildverarbeitung MUST die bestehenden Online-, Einwilligungs-, Format-/Größen- und Review-Regeln erhalten. Bilder DÜRFEN nicht in die Offline-Outbox oder normale Telemetrie gelangen.

#### Scenario: Kamera abgelehnt oder geschlossen
- **GIVEN** ein Lebensmittelentwurf ohne bestätigte Mutation
- **WHEN** Kamera-Zugriff abgelehnt oder Fotoauswahl abgebrochen wird
- **THEN** bleibt der Entwurf unverändert, manuelle Erfassung bleibt möglich und keine Bildübertragung erfolgt

#### Scenario: Scan überprüfen
- **GIVEN** ein unterstütztes Foto und aktive Sitzung mit Internet
- **WHEN** der Nutzer den Scan erlaubt und ein Ergebnis erhält
- **THEN** muss er Bezugsgröße und Werte prüfen und bestätigen, bevor ein lokaler Ernährungseintrag samt Outbox entsteht

### Requirement: Widget und Shortcuts als kontrollierte Einstiege

Die App MUST Home-Screen-Widgets (klein und mittel) für „Training öffnen“ und „Check-in öffnen“ und Kurzbefehle für „Training öffnen“, „Check-in öffnen“ und „Ernährung öffnen“ bereitstellen. Systemoberflächen DÜRFEN weder Passwörter/Sitzungstoken noch komplette Fitnessdaten speichern und keine fachliche Mutation ohne In-App-Bestätigung ausführen. Veraltete, abgemeldete oder kontoübergreifende Einstiege MUST sicher in den aktuellen Zugangspfad führen.

#### Scenario: Widget nach Kontowechsel
- **GIVEN** ein Widget wurde unter Konto A eingerichtet
- **WHEN** Konto B aktiv wird und das Widget geöffnet wird
- **THEN** werden keine A-Daten angezeigt und der Einstieg löst keine Aktion für A aus

#### Scenario: Shortcut ohne aktive Sitzung
- **GIVEN** ein Shortcut und keine gültige Sitzung
- **WHEN** der Nutzer den Shortcut ausführt
- **THEN** öffnet sich die App mit dem passenden Zugangspfad und führt keine versteckte Mutation aus

### Requirement: Prüfung und Auslieferung

Jeder Pull Request MUST in der CI Format, Analyse, Flutter-Tests, einen iOS-Simulator-Build, die XCTest-Suite und die Screenshot-Aufnahmen auf macOS mit festgelegter Xcode- und Flutter-Version bestehen. Ein signierter Build und der TestFlight-Upload MUST nur manuell und nur von `main` ausgelöst werden können. Swift-Code wird nur in der CI gebaut.

#### Scenario: Pull Request
- **GIVEN** ein Pull Request mit Änderungen unter `apps/mobile`
- **WHEN** der Workflow „Mobile CI“ läuft
- **THEN** laufen Flutter-Checks, Simulator-Build, XCTests und Screenshot-Aufnahme, aber kein Signieren und kein Upload

#### Scenario: TestFlight von einem Feature-Branch
- **GIVEN** ein Feature-Branch
- **WHEN** jemand den Upload nach TestFlight manuell für diesen Branch anfordert
- **THEN** wird der Signier-Job nicht ausgeführt und es werden keine Signier-Secrets gelesen

### Requirement: Kein Web-Client

Das Repository SHALL keinen Web-Client mehr enthalten. Die iOS-App MUST der einzige Client der API sein. Build, CI und Deploy MUST ohne Node.js und npm auskommen, ausgenommen der Workflow „OpenSpec“, der beides nur für die gepinnte OpenSpec-CLI in `tools/openspec` nutzt.

#### Scenario: CI ohne Node
- **GIVEN** ein Pull Request gegen `main`
- **WHEN** der Workflow „CI“ läuft
- **THEN** richtet kein Schritt Node.js ein und kein Schritt ruft `npm` oder `npx` auf

#### Scenario: Node nur für die Spec-Prüfung
- **GIVEN** ein Pull Request, der `openspec/` ändert
- **WHEN** der Workflow „OpenSpec“ läuft
- **THEN** richtet er Node.js ein und installiert die CLI aus `tools/openspec`, und keine andere Stufe nutzt npm

#### Scenario: AppHost ohne Web-Ressource
- **GIVEN** der Aspire AppHost im Entwicklungsmodus
- **WHEN** seine Ressourcen aufgelistet werden
- **THEN** gibt es `postgres`, `gainer-db`, `backup-storage`, `backup-blobs` und `api`, aber keine Ressource `web`

### Requirement: Edge leitet nur API und Health weiter

Der Edge-Container SHALL `/api/v1/*` und `/health/*` unverändert an die API weiterleiten und `/.well-known/apple-app-site-association` selbst beantworten (siehe `account-access`). Alle anderen Pfade MUST er mit 404 beantworten. Jede Antwort MUST die Header `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` und `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'` tragen.

#### Scenario: Startseite
- **GIVEN** der Edge-Container läuft
- **WHEN** ein Client `GET /` aufruft
- **THEN** antwortet der Edge mit 404 und der CSP `default-src 'none'; frame-ancestors 'none'`

#### Scenario: API-Aufruf
- **GIVEN** Edge und API laufen
- **WHEN** die iOS-App `GET /api/v1/auth/session` aufruft
- **THEN** leitet der Edge den Request an die API weiter und gibt deren Antwort zurück

#### Scenario: Health-Prüfung
- **GIVEN** Edge und API laufen
- **WHEN** der Betreiber `GET /health/ready` über den Edge aufruft
- **THEN** liefert der Edge die Antwort der API
