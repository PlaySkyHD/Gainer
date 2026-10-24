# Design

## D1 Edge bleibt als reiner Reverse Proxy

Man könnte den Edge-Container ganz streichen und Host-Caddy direkt auf die API zeigen lassen. Dann müssten aber Host-Caddy, Compose-Topologie, `Test-DeploymentTopology.ps1`, Deploy-Workflow und Rollback-Anleitung gleichzeitig geändert werden. Der Edge bleibt deshalb unter gleichem Namen und Port bestehen und wird zu einem Caddy-Image mit fest eingebauter Konfiguration. Ein Build-Schritt mit Node entfällt.

## D2 Unbekannte Pfade liefern 404

Ohne statische Dateien gibt es nichts mehr auszuliefern. Alles außer `/api/v1/*` und `/health/*` beantwortet der Edge mit 404. Die Sicherheitsheader bleiben. Die CSP wird auf `default-src 'none'; frame-ancestors 'none'` verschärft, weil keine Skripte oder Styles mehr ausgeliefert werden. `Permissions-Policy` entfällt, weil es keine Dokumente mehr gibt.

## D3 Lokaler Frontend-Origin

Die API verlangt in Development einen konkreten `Security:FrontendOrigin`, und die `RequestOriginMiddleware` vergleicht ändernde Requests damit. Die iOS-App sendet ohne `GAINER_TRUSTED_FRONTEND_ORIGIN` den API-Origin. Der AppHost setzt den Wert deshalb auf den eigenen HTTP-Endpunkt der API, und `appsettings.Development.json` nutzt die Launch-URL `http://localhost:5160`.

## D4 Vertragsprüfung ohne TypeScript

Die eingecheckte OpenAPI-Datei bleibt die Vertragsquelle. Die Drift- und Kompatibilitätsprüfungen laufen weiter, nur ohne die generierte TypeScript-Datei.
