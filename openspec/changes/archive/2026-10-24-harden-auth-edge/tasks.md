# Tasks

## 1. Server

- [x] 1.1 Forwarded-Header nur von Loopback und privaten Netzen; `trusted_proxies` im Edge-Caddy; Hinweis im RUNBOOK (D1).
- [x] 1.2 Rate-Limits pro Client: Anmeldung, eigenes Limit für Refresh, `/health/ready`.
- [x] 1.3 Verworfene Refresh-Tokens speichern und bei Rückkehr widerrufen, ein Retry pro Rotation; Migration (D2).
- [x] 1.4 Passkey-Anmeldung ohne Passwort-Sperre (D3).
- [x] 1.5 Größenlimit pro Endpunkt in `RequestSizeLimitMiddleware`.

## 2. Images und Abhängigkeiten

- [x] 2.1 SDK 10.0.402, ASP.NET 10.0.13, Caddy 2.11.7, Postgres 18.6, gepinnt per Digest.
- [x] 2.2 Dependabot.

## 3. Prüfung

- [x] 3.1 Integrationstests für Proxy-Vertrauen, Limits, Kulanz-Retry, Passkey trotz Sperre und Foto-Größe.
- [x] 3.2 Edge-Image lokal vor einem Echo-Backend: `X-Forwarded-For: <client>, <gateway>` kommt an.
- [x] 3.3 Nach dem Deploy: Anmeldung, Refresh und Passkey auf dem iPhone; Mahlzeit-Foto über 1 MiB.
