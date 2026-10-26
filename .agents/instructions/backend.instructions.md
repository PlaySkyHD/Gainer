---
description: 'Konventionen für das ASP.NET-Core-Backend und seine Tests.'
applyTo: '**/*.cs'
paths:
  - "src/**/*.cs"
  - "tests/**/*.cs"
---

# Backend

Stack: .NET 10, ASP.NET Core mit Controllern, EF Core mit Npgsql, ASP.NET Core Identity, Aspire nur lokal, MSTest. Keine weiteren Frameworks ohne Begründung im OpenSpec-Design.

## Schichten

- `Core` enthält Domäne, Mutationen, Abfrage-Schnittstellen und fachliche Exceptions. Es kennt weder `Infrastructure` noch `Api` (Architekturtests).
- `Infrastructure` enthält `AppDbContext`, Handler, Queries und externe Adapter. `Api` ist der Composition Root.
- Controller sind `sealed`, nutzen Primärkonstruktoren, tragen `[Authorize]` und `[ResponseCache(NoStore = true)]` und bekommen nie den `AppDbContext`, sondern Core-Schnittstellen.
- HTTP-Verträge liegen in `Contracts`. Fehler gehen als `ProblemDetails` mit stabilem `code` hinaus.

## Daten und Sync

- Jede nutzerbezogene Entität implementiert `IUserOwnedEntity`; der globale Query-Filter in `AppDbContext` isoliert die Nutzer. Die `UserId` kommt nur aus `IUserContext`, nie aus Request oder LLM-Aufruf.
- Schreibende Handler prüfen die Basisversion, erhöhen `Version` und melden Abweichungen über die fachliche `*ConflictException`. `SyncMutationProcessor` übersetzt sie in Sync-Codes.
- Ein Unique-Fehler ist nur dann ein Konflikt, wenn wirklich ein anderer Stand existiert. Werden Kindzeilen mit gleichen IDs ersetzt, das Entfernen zuerst mit `SaveChanges` abschließen, beides in einer Transaktion.
- Migrationen: `dotnet ef migrations add` mit Startprojekt `src/Gainer.Infrastructure`, danach `dotnet format`.
- Neue Antwortfelder sind optional. Der Build erzeugt `contracts/openapi/Gainer.Api.json`; die Datei gehört in den Commit.

## Code

- File-scoped Namespaces, `sealed` als Standard, Nullable aktiv, `CancellationToken` durchreichen.
- NuGet-Versionen nur in `Directory.Packages.props`; `packages.lock.json` mit committen.
- Keine Prompt- oder Response-Inhalte, Tokens oder Fitnessdaten in Logs.

## Tests

- Neues Verhalten bekommt einen Test, bevorzugt einen Integrationstest gegen Postgres (`PostgreSqlTestFixture`, Testcontainers). Aufruf: `sg docker -c 'dotnet test <testprojekt> --filter <klassen> --verbosity quiet --logger "console;verbosity=minimal"'`. `quiet` dämpft die Build-Ausgabe, der Logger zeigt fehlgeschlagene Tests mit Name und Meldung; ohne ihn meldet `quiet` nur „1 failed“ und ein zweiter Lauf ist nötig. Nur die betroffenen Testklassen laufen lassen (`--filter`), die CI prüft den Rest.
- Datenzugriffe prüfen Nutzerisolation mit mindestens zwei Testnutzern.
- Ein Bugfix-Test schlägt ohne den Fix fehl.
