# web-client-retirement

## ADDED Requirements

### Requirement: Kein Web-Client

Das Repository SHALL keinen Web-Client mehr enthalten. Die iOS-App MUST der einzige Client der API sein. Build, CI und Deploy MUST ohne Node.js und npm auskommen.

#### Scenario: CI ohne Node
- **GIVEN** ein Pull Request gegen `main`
- **WHEN** der Workflow „CI“ läuft
- **THEN** richtet kein Schritt Node.js ein und kein Schritt ruft `npm` oder `npx` auf

#### Scenario: AppHost ohne Web-Ressource
- **GIVEN** der Aspire AppHost im Entwicklungsmodus
- **WHEN** seine Ressourcen aufgelistet werden
- **THEN** gibt es `postgres`, `gainer-db`, `backup-storage`, `backup-blobs` und `api`, aber keine Ressource `web`

### Requirement: Edge leitet nur API und Health weiter

Der Edge-Container SHALL `/api/v1/*` und `/health/*` unverändert an die API weiterleiten. Alle anderen Pfade MUST er mit 404 beantworten. Jede Antwort MUST die Header `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` und `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'` tragen.

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

### Requirement: Lokale Entwicklung mit der iOS-App

Der AppHost SHALL `Security:FrontendOrigin` der API auf deren eigenen HTTP-Endpunkt setzen, damit ändernde Requests der iOS-App ohne überschriebenen vertrauenswürdigen Origin die Origin-Prüfung bestehen.

#### Scenario: App ohne eigenen Origin
- **GIVEN** die API läuft über den AppHost und die App ist ohne `GAINER_TRUSTED_FRONTEND_ORIGIN` gebaut
- **WHEN** die App eine Mutation mit `Origin` gleich dem API-Origin sendet
- **THEN** lässt die `RequestOriginMiddleware` den Request durch
