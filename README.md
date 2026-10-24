# Gainer

Gainer ist ein privater, einladungsbasierter Fitness-Tracker für Training, Ernährung und Körperwerte. Die Anwendung ist für den Betreiber und ausgewählte Kollegen gedacht. Jeder Nutzer sieht und verändert ausschließlich seine eigenen Daten.

Gainer besteht aus einer **iOS-App (Flutter)** und einem **ASP.NET-Core-Backend mit PostgreSQL**. Die App arbeitet offline-first und gleicht sich über eine eigene Sync-API mit dem Server ab. Das Backend läuft containerisiert auf einem einzelnen Linux-VPS.

## Funktionen

Die App hat fünf Tabs: **Kalender, Check-in, Essen, Training und Mehr**.

### Training

- Trainingspläne mit Blöcken, Reihenfolge, Duplizieren per langem Drücken und einem Wochenplan im Kalender
- Workout-Erfassung mit Vorwerten, Aufwärmsätzen, Notizen und Zusammenfassung; Workouts lassen sich wiederholen oder als Plan speichern
- Pausen-Timer mit Tönen, Benachrichtigungen und Live Activity auf dem Sperrbildschirm
- Deutscher Übungskatalog (103 Übungen) mit Kategorien, eigenen Übungen und Zusammenführen von Duplikaten
- Muskelkarte mit Haupt- und Hilfsmuskeln; KI-Vorschlag der Muskeln für eigene Übungen
- Statistiken je Übung, zum Beispiel geschätztes 1RM und Verlauf

### Cardio

- Cardio-Einheiten mit Pulsgurt über Bluetooth, Zielzonen, Zonenalarm und Sprachansagen
- Vorlagen mit Phasen und Aufwärmen, Live Activity während der Einheit
- HRV-Messung, Fortschrittsdiagramme und Export der Einheiten nach Apple Health
- Strava-Export ist implementiert, aber nicht aktiv: Die Strava-API-App braucht ein kostenpflichtiges Strava-Abo

### Ernährung

- Tagebuch mit vier Mahlzeiten, Wischen zum Löschen, Umsortieren und Bearbeiten
- Lebensmittel erfassen:
  - manuell
  - über „Zuletzt verwendet“
  - über die Produktsuche und den Barcode-Scan (Open Food Facts)
  - über den Etiketten-Scan per Foto (OpenAI)
  - über die KI-Schätzung aus Text, Diktat oder Foto
- KI-Schätzung mit Websuche auf Nährwertseiten (fddb.info, naehrwertrechner.de, Open Food Facts, USDA), Quellenangabe und einzeln übernehmbaren Bestandteilen
- Diktat mit Spracherkennung auf dem Gerät, ohne Audio-Upload
- Mengen in Gramm oder Stück (z. B. 4 Eier); das Stückgewicht merkt sich die App
- Kalorien, Eiweiß, Kohlenhydrate, Fett und **Salz**; eigenes Salz („eine Prise“) als eigener Eintrag
- Gespeicherte Gerichte, Zielphasen mit Makros in Gramm oder Prozent und eine Salzgrenze (Standard 6 g)
- Durchschnitte über 7 und 30 Tage

### Check-in und Fortschritt

- Täglicher Check-in mit Gewicht, Schlaf, Schritten, Ruhepuls und HRV, vorausgefüllt aus Apple Health
- Körperziele, Gewichtsverlauf und Tagesübersicht
- KI-Coach, der nur liest und Fragen zu den eigenen Fortschrittsdaten beantwortet

### Konto und Sync

- Einladungen statt öffentlicher Registrierung, Anmeldung mit Passwort oder Passkey, Kontoverwaltung für den Betreiber
- Offline-first mit lokaler Datenbank (Drift) und Outbox; der Server ist führend
- Ein Gerät pro Konto schreibt; der Gerätewechsel ist eine geführte Übergabe
- Homescreen-Widget und App-Kurzbefehle

## Architektur

```text
iOS-App (Flutter, Cupertino)              VPS (Docker Compose)
  Drift-DB + Outbox  ──/api/v1──▶  edge (Caddy) ─▶ api (ASP.NET Core) ─▶ PostgreSQL
  Pigeon ⇄ Swift (HealthKit,                         │
  Kamera, Bluetooth, Live Activities,                ├─▶ OpenAI (Coach, KI-Schätzung, Etikett, Muskeln)
  Spracherkennung, Passkeys)                         ├─▶ Open Food Facts
                                                     └─▶ Strava
  migrator (EF-Migrationen) · backup (Restic)
```

- **Backend:** modularer Monolith. `Core` enthält Domäne und Anwendungsfälle. `Infrastructure` enthält EF Core, Identity und die externen Adapter. `Api` ist der Composition Root.
- **Sync:** Die App sendet Mutationen mit Basisversion und holt einen Änderungs-Feed. Bei Konflikten übernimmt der Nutzer in der App den Serverstand oder erzwingt den lokalen Stand.
- **API-Vertrag:** Ein Backend-Build erzeugt [`contracts/openapi/Gainer.Api.json`](contracts/openapi/Gainer.Api.json). Die CI lehnt nicht regenerierte oder inkompatible Änderungen ab (siehe [API-Vertrag](#api-vertrag)).
- **Nativer iOS-Code** liegt unter `apps/mobile/ios/Runner/native` und ist über [Pigeon](apps/mobile/pigeons/mobile_platform_api.dart) angebunden.

## Struktur

```text
apps/mobile/                     Flutter-iOS-App, Swift-Code, Widget-Extension
src/Gainer.Api/                  HTTP-API, Authentifizierung, Composition Root
src/Gainer.Core/                 Domänenmodell und Anwendungsfälle
src/Gainer.Infrastructure/       EF Core, Npgsql, Identity, Sync, OpenAI, Open Food Facts, Strava
src/Gainer.Contracts/            HTTP-Verträge
src/Gainer.Migrator/             Datenbankmigrationen als eigener Container
src/Gainer.AppHost/              Aspire-Modell für die lokale Entwicklung
src/Gainer.ServiceDefaults/      Health Checks, Service Discovery, OpenTelemetry
tests/Gainer.UnitTests/          Domänen- und Anwendungsfalltests
tests/Gainer.IntegrationTests/   API- und PostgreSQL-Tests (Testcontainers)
tests/Gainer.ArchitectureTests/  Modul- und Abhängigkeitsregeln
contracts/openapi/               Generierter OpenAPI-Vertrag
deploy/                          Dockerfiles, Compose, Caddy, Skripte, Runbook
scripts/                         Verifikations- und Prüfskripte
openspec/                        Fachliche Specs (specs/) und Changes (changes/)
docs/                            Hinweise für die Arbeit am Repo
```

## Voraussetzungen

- .NET SDK gemäß [`global.json`](global.json) (.NET 10)
- Docker für PostgreSQL, Integrationstests (Testcontainers) und Container-Builds
- PowerShell 7 für die Skripte unter `scripts/`
- Flutter in der Version aus [`apps/mobile/.flutter-version`](apps/mobile/.flutter-version). Für iOS-Builds braucht es macOS mit Xcode; die App wird in der CI gebaut.

## Lokal entwickeln

Backend mit PostgreSQL über Aspire starten:

```powershell
dotnet user-secrets set "Parameters:openfoodfacts-contact-email" "operator@example.invalid" --project src/Gainer.AppHost
dotnet run --project src/Gainer.AppHost
```

- **Open Food Facts** braucht keinen API-Schlüssel, verlangt aber einen identifizierenden User-Agent mit Kontaktadresse. Direkt gestartete API-Prozesse nutzen `OpenFoodFacts__ContactEmail`.
- **OpenAI:** Die KI-Funktionen brauchen `OpenAI__ApiKey` oder `OpenAI__ApiKeyFile`. Ohne gültige OpenAI-Konfiguration meldet `/health/ready` „nicht bereit“.
- **Strava:** Optional über `Strava__ClientId`, `Strava__ClientSecret` und `Strava__CallbackUrl`.

### Erstes Konto

Die Anwendung hat keine Standardzugangsdaten. Für eine leere, migrierte Datenbank legt ein einmaliger Start mit einer externen JSON-Datei (`email`, `password`) das Betreiberkonto an:

```powershell
$env:Provisioning__AccountOperatorSecretPath = "C:\secure\gainer-operator.json"
dotnet run --project src/Gainer.Api -- --provision-account-operator
```

- Das Betreiberkonto verwaltet nur Konten und Einladungen. Es hat keinen Zugriff auf Fitnessdaten anderer Nutzer.
- Die Provisionierung verweigert eine nicht leere Identity-Datenbank.

## Prüfen

Backend:

```powershell
pwsh ./scripts/verify.ps1          # Restore, Format, Build, Tests
dotnet test Gainer.slnx            # einzeln; Integrationstests brauchen Docker
```

- NuGet-Versionen stehen zentral in [`Directory.Packages.props`](Directory.Packages.props). Die `packages.lock.json`-Dateien sind eingecheckt.
- Nach `dotnet ef migrations add` immer `dotnet format` ausführen. Startprojekt für EF ist `src/Gainer.Infrastructure`.

App (in `apps/mobile`):

```bash
flutter analyze
flutter test
dart format --set-exit-if-changed lib test pigeons
tool/preview_goldens.sh test/ui/<bereich>   # Goldens mit lesbarer Schrift
```

- Nach Änderungen an `pigeons/mobile_platform_api.dart` den Pigeon-Code neu erzeugen und die generierte Dart-Datei formatieren.
- Swift-Code wird nur in der CI kompiliert.
- Details zur Toolchain und zum Simulator stehen in [`apps/mobile/README.md`](apps/mobile/README.md).

## API-Vertrag

ASP.NET OpenAPI ist die einzige Vertragsquelle.
- Neue Antwortfelder müssen optional sein, sonst meldet [`scripts/Test-OpenApiCompatibility.ps1`](scripts/Test-OpenApiCompatibility.ps1) einen Bruch.
- Bewusste Brüche werden mit Begründung in `contracts/openapi/accepted-breaking-changes.json` eingetragen. Nach dem Merge wird die Liste wieder geleert.

## CI und Auslieferung

| Workflow | Zweck |
| --- | --- |
| `ci.yml` | Backend: Build, Tests, Container, OpenAPI-Prüfung, Lizenzen |
| `mobile.yml` | App: Analyse, Tests, Simulator-Build, auf Wunsch TestFlight-Upload |
| `sonar-backend.yml`, `sonar-app.yml` | SonarCloud Quality Gates (u. a. 80 % Abdeckung neuer Zeilen) |
| `deploy.yml` | Produktions-Deploy einer Revision aus `main` auf den VPS |

```bash
gh workflow run deploy.yml --ref main -f ref=<commit>
gh workflow run mobile.yml --ref main -f build_signed_ipa=false -f upload_testflight=true
```

- Einrichtung, Secrets, Deploy, Backup und Wiederherstellung stehen in [`deploy/RUNBOOK.md`](deploy/RUNBOOK.md).
- Welche Daten an Drittanbieter gehen, steht in [`deploy/THIRD_PARTY_POLICY.md`](deploy/THIRD_PARTY_POLICY.md).
- Das Backup-Ziel muss neu eingerichtet werden, weil die Azure-Ressource nicht mehr existiert: [#66](https://github.com/PlaySkyHD/Gainer/issues/66).

## Mitwirken

- Der aktuelle Stand der App steht in den fachlichen Specs unter [`openspec/specs`](openspec/specs).
- Jede Änderung ist ein OpenSpec-Change unter [`openspec/changes`](openspec/changes) (`openspec validate <change> --strict`) mit einem eigenen PR. Vor dem Merge archiviert derselbe PR den Change (`openspec archive <change> -y`), damit seine Deltas in den Specs landen. Der Workflow „OpenSpec“ lehnt PRs mit offenen Changes ab.
- Gemergt wird erst, wenn alle Checks grün sind.
- Arbeitsweise, Definition of Done und Commit-Konventionen stehen in [`CONTRIBUTING.md`](CONTRIBUTING.md).
- Erkenntnisse aus bisherigen Umsetzungen stehen in [`docs/agent-lessons-learned.md`](docs/agent-lessons-learned.md).
