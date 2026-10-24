# Tasks

## 1. Entfernen

- [x] 1.1 `apps/web`, `deploy/generate-edge-csp.mjs`, `scripts/check-npm-licenses.mjs` und `deploy/NUTRITION_IPHONE_ACCEPTANCE.md` löschen.
- [x] 1.2 `Aspire.Hosting.JavaScript` aus AppHost und `Directory.Packages.props` entfernen, Lockfiles neu erzeugen.

## 2. Edge und Entwicklung

- [x] 2.1 `Dockerfile.edge` auf Caddy mit statischer Konfiguration reduzieren, `Caddyfile` auf API- und Health-Proxy mit 404-Fallback umstellen (D1, D2).
- [x] 2.2 AppHost ohne `web`, `Security:FrontendOrigin` auf den API-Endpunkt; `appsettings.Development.json` auf die Launch-URL (D3); AppHost-Topologietest anpassen.

## 3. CI und Skripte

- [x] 3.1 Web-Schritte aus `ci.yml` und `scripts/verify.ps1` entfernen, Edge-Smoke-Test ergänzen, Driftprüfung nur noch für `contracts/openapi` (D4).

## 4. Doku

- [x] 4.1 README, Runbook, Lizenzhinweise, Beitragsrichtlinie und OpenSpec-Kontext aktualisieren.

## 5. Abschluss

- [x] 5.1 CI grün, danach Production-Deploy und Prüfung: `/health/ready` über den Edge liefert 200, `/` liefert 404, die App meldet sich an und synchronisiert.
