# Gainer

Gainer ist ein privater, einladungsbasierter AI Body & Training Tracker. Die Anwendung ist für den Betreiber und ausgewählte Kollegen gedacht. Jeder Nutzer sieht und verändert über die Anwendung ausschließlich seine eigenen Fitnessdaten.

Der aktuelle Repository-Stand enthält das technische Fundament. Die Fachmodule, Offline-Synchronisation und der AI Progress Coach werden schrittweise nach dem OpenSpec-Change [`build-ai-body-training-tracker-mvp`](openspec/changes/build-ai-body-training-tracker-mvp/) umgesetzt.

## MVP-Scope

Der MVP umfasst:

- eingeladene oder administrativ angelegte Konten ohne öffentliche Registrierung,
- Körperziele und tägliche Check-ins,
- ein offline-fähiges Ernährungstagebuch mit vier Mahlzeiten, manueller Erfassung sowie optionaler Barcode- und Produktsuche über Open Food Facts,
- Übungskatalog, Workout-Templates und eine einfache Rotation,
- Offline-first Workout-Ausführung mit Previous Performance, Set Logging, Historie und Rest Timer,
- deterministische Fortschrittskennzahlen,
- einen rein lesenden, serverseitigen OpenAI Progress Coach,
- Betrieb als containerisierte Anwendung mit PostgreSQL auf einem einzelnen Linux-VPS.

Nicht Bestandteil des MVP sind öffentliche Veröffentlichung, Bezahlung, soziale Funktionen, Einsicht in Fitnessdaten anderer Nutzer, Ende-zu-Ende-Verschlüsselung, RAG, automatische Kalorienentscheidungen und garantierter iOS-Hintergrund-Sync.

## Struktur

```text
apps/mobile/                 Flutter-iOS-App (einziger Client)
src/Gainer.Api/              ASP.NET-Core-Composition-Root und HTTP-API
src/Gainer.Core/             Domänenmodell und Anwendungsfälle
src/Gainer.Infrastructure/   EF Core, Npgsql, Identity und externe Adapter
src/Gainer.Contracts/        Versionierte HTTP- und Sync-Verträge
src/Gainer.AppHost/          Aspire-Anwendungsmodell für lokale Entwicklung
src/Gainer.ServiceDefaults/  Health Checks, Service Discovery und OpenTelemetry
tests/Gainer.UnitTests/      Schnelle Domänen- und Anwendungsfalltests
tests/Gainer.IntegrationTests/ PostgreSQL- und API-Integrationstests
tests/Gainer.ArchitectureTests/ Automatisierte Modul- und Abhängigkeitsregeln
openspec/                    Anforderungen, Design und Implementierungsaufgaben
```

Das Backend ist als modularer Monolith ausgelegt. Die iOS-App greift ausschließlich über `/api/v1` auf Serverfunktionen zu. In Produktion leitet ein Reverse Proxy API- und Health-Aufrufe an ASP.NET Core weiter; Aspire ist die Entwicklungs- und Publikationsbeschreibung, nicht der Produktions-Orchestrator.

## Voraussetzungen

- .NET SDK gemäß [`global.json`](global.json)
- PowerShell 7 für das gebündelte Verifikationsskript
- Docker für die späteren PostgreSQL-, Aspire- und Container-Szenarien

## Lokale Qualitätsprüfung

Abhängigkeiten und alle derzeit verfügbaren Prüfungen werden mit folgendem Befehl ausgeführt:

```powershell
pwsh ./scripts/verify.ps1
```

Einzelne Befehle:

```powershell
dotnet restore Gainer.slnx --locked-mode
dotnet format Gainer.slnx --verify-no-changes --no-restore
dotnet build Gainer.slnx --no-restore
dotnet test Gainer.slnx --no-restore --no-build
```

NuGet-Paketversionen werden zentral in [`Directory.Packages.props`](Directory.Packages.props) verwaltet. `packages.lock.json`-Dateien werden eingecheckt und im CI reproduzierbar verwendet.

ASP.NET OpenAPI ist die einzige HTTP-Vertragsquelle. Ein Backend-Build erzeugt
`contracts/openapi/Gainer.Api.json`. Die Datei wird eingecheckt und CI
lehnt nicht regenerierte oder gegenüber dem Ziel-Branch inkompatible Änderungen ab.

Bewusst inkompatible Änderungen werden in `contracts/openapi/accepted-breaking-changes.json` eingetragen: Jeder Eintrag in `accepted` muss exakt der Meldung von `scripts/Test-OpenApiCompatibility.ps1` entsprechen, und `reason` begründet die Änderung. Die Liste ist nur für den Change gedacht, der den Vertrag ändert; neue Befunde, die nicht gelistet sind, lassen das Skript weiterhin fehlschlagen. Nach dem Merge ist die Liste zu leeren, sobald das Skript die Einträge nicht mehr meldet (veraltete Einträge erzeugen eine Warnung), damit der Schutz für spätere Änderungen wieder vollständig greift.

## Open Food Facts lokal

Die externe Lebensmittelsuche ist read-only und benötigt keine API-Zugangsdaten. Open Food Facts verlangt jedoch einen identifizierenden User-Agent; deshalb ist eine erreichbare technische Kontaktadresse erforderlich. Für den Aspire AppHost wird sie lokal als Parameter gespeichert:

```powershell
dotnet user-secrets set "Parameters:openfoodfacts-contact-email" "operator@example.invalid" --project src/Gainer.AppHost
dotnet run --project src/Gainer.AppHost
```

Direkt gestartete API-Prozesse verwenden stattdessen `OpenFoodFacts__ContactEmail`. Barcode und Suchtext werden weder durch den Adapter geloggt noch als URL-Pfad oder Query in OpenTelemetry exportiert. Produktdaten sind Community-Daten und werden vor dem Speichern als eigener Nährwert-Snapshot übernommen; Angaben sollten mit der Verpackung abgeglichen werden.

## Erstes Account-Operator-Konto

Die Anwendung enthält keine Standardzugangsdaten und provisioniert beim normalen
Start kein Konto. Für eine leere, bereits migrierte Identity-Datenbank wird einmalig
eine externe JSON-Datei mit `email` und `password` bereitgestellt. Der Dateipfad
kommt aus `Provisioning__AccountOperatorSecretPath`; anschließend wird die API mit
dem expliziten Modus `--provision-account-operator` gestartet.

```powershell
$env:Provisioning__AccountOperatorSecretPath = "C:\secure\gainer-operator.json"
dotnet run --project src/Gainer.Api -- --provision-account-operator
```

Das Secret bleibt außerhalb des Repositorys. Die Provisionierung verweigert eine
nicht leere Identity-Datenbank; existiert bereits ein Account-Operator, bleibt der
Stand unverändert. Der Account-Operator verwaltet ausschließlich Identity-Metadaten
und erhält durch seine Rolle keinen Zugriff auf Fitnessdaten anderer Nutzer.

## Mitwirken

Arbeitsweise, Definition of Done und Commit-Konventionen stehen in [`CONTRIBUTING.md`](CONTRIBUTING.md).
