# Proposal

## Why

Der Nutzer möchte seine Gainer-Daten in ChatGPT (und anderen KI-Assistenten mit MCP) auswerten, ohne sie abzutippen. ChatGPT bindet entfernte MCP-Server als App an und verlangt dafür OAuth 2.1 mit PKCE, Discovery über `/.well-known` und Streamable HTTP.

## What Changes

- Neuer MCP-Endpunkt `/api/v1/mcp` im bestehenden API-Prozess mit fünf lesenden Tools: Überblick, Trainingsliste, Trainingsdetail, Übungssuche, Übungsentwicklung.
- Gainer wird Autorisierungsserver für diesen Zweck: Protected-Resource- und Authorization-Server-Metadaten, dynamische Client-Registrierung, Freigabeseite mit Passkey, Token-Endpunkt mit Authorization Code + PKCE (S256) und Refresh-Token.
- Eine Freigabe erzeugt eine **verbundene App**: eine Geräte-Session eigener Art. Ihr Token öffnet nur den MCP-Endpunkt, keinen anderen API-Endpunkt. Widerruf, Ablauf und Rotation folgen den Geräte-Sessions.
- `GET /api/v1/auth/connectors` und `DELETE /api/v1/auth/connectors/{id}` listen und widerrufen verbundene Apps. Die App zeigt sie unter Profil (eigener PR).
- Edge leitet `/.well-known/oauth-*` an die API weiter; die Freigabeseite erhält eine eigene, enge CSP.
- Version 1 schreibt nichts: Das Einzelschreiber-Modell des Syncs bleibt unberührt.

## Capabilities

### New Capabilities

- `ai-connector`: MCP-Endpunkt, OAuth-Ablauf und Tools für externe KI-Assistenten.

### Modified Capabilities

- `account-access`: verbundene Apps als eigene Session-Art, Verwaltung und Abgrenzung zur App-API.

## Impact

Backend: `Gainer.Api` (OAuth-Controller, MCP-Tools, Autorisierungsrichtlinien), `Gainer.Core.Access` (Session-Art), `Gainer.Infrastructure` (Spalte `Kind` an `DeviceSessions`, Migration), Edge-Caddyfile, OpenAPI-Vertrag (nur Verwaltungsendpunkte). Neues Paket `ModelContextProtocol.AspNetCore`.
