# Tasks

## 1. Sessions

- [x] 1.1 `DeviceSession.Kind` mit Migration, `IssuedDeviceSession.Kind`, Connector-Sessions anlegen, listen, widerrufen.
- [x] 1.2 Claim `gainer:scope` für Connector-Tokens; Richtlinien trennen App- und Connector-Tokens. Prüfung: `FallbackAuthorizationTests`, `ConnectorFlowTests` grün.

## 2. OAuth

- [x] 2.1 Metadaten, Registrierung, Freigabeseite mit Passkey, Token-Endpunkt mit PKCE und Refresh. Prüfung: `ConnectorOAuthEndpointTests`, `ConnectorFlowTests` grün.
- [x] 2.2 Verwaltungsendpunkte `GET`/`DELETE /api/v1/auth/connectors`. Prüfung: `ConnectorFlowTests` grün, OpenAPI-Vertrag aktualisiert.

## 3. MCP

- [x] 3.1 MCP-Endpunkt mit fünf lesenden Tools und `WWW-Authenticate` bei 401. Prüfung: `ConnectorFlowTests` grün, Nutzerisolation mit zwei Nutzern.

## 4. Edge und Spec

- [x] 4.1 Caddyfile leitet `/.well-known/oauth-*` weiter, Freigabeseite mit eigener CSP. Prüfung: `caddy validate` und Header-Test gegen einen lokalen Upstream.
- [x] 4.2 `openspec validate --specs --strict` grün.
