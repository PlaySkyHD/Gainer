# Proposal

## Why

Eine Sicherheitsanalyse mit vier unabhängigen Prüfungen fand keine kritischen Lücken, aber mehrere Schwächen am Rand:

- Hinter den zwei Caddy-Proxys sah die API für jeden Request dieselbe Docker-Gateway-Adresse. Das Anmelde-Limit von 30 Anfragen pro Minute galt damit für alle Nutzer gemeinsam, und eine einzelne Person konnte Login und Token-Refresh für alle blockieren.
- Production lief auf ASP.NET Core 10.0.3, acht Patch-Releases hinter dem Stand.
- Ein gestohlener Refresh-Token, der in der Kulanzminute nach einer Rotation eingelöst wurde, übernahm die Sitzung unbemerkt.
- Fünf falsche Passwörter sperrten auch die Passkey-Anmeldung, so dass Fremde mit der E-Mail-Adresse ein Konto aussperren konnten.
- `/health/ready` war öffentlich und ohne Limit.
- Mahlzeit-Fotos über 1 MiB scheiterten am globalen Größenlimit, bevor das Limit des Endpunkts griff.

## What Changes

- **Proxy-Kette:** Der Edge-Caddy vertraut den privaten Netzen (`trusted_proxies static private_ranges`), die API nur Loopback und privaten Netzen. Die API sieht so die Adresse, die host Caddy vom Client erhalten hat.
- **Rate-Limits pro Client:** Anmeldung 30/min, Token-Refresh eigenes Limit 60/min, `/health/ready` 30/min.
- **Refresh-Token:** Pro Rotation ist ein Retry in der Kulanzzeit erlaubt. Der dabei verworfene Token wird gespeichert; kommt er zurück, oder ein zweiter Retry, wird die Session widerrufen. Migration `AddDiscardedRefreshToken`.
- **Passkey-Anmeldung** ignoriert die Passwort-Sperre.
- **Größenlimit:** Die Middleware beachtet `[RequestSizeLimit]` des Endpunkts; Mahlzeit-Schätzungen bis 8 MiB kommen an.
- **Images:** .NET SDK 10.0.402 und ASP.NET 10.0.13, Caddy 2.11.7, Postgres 18.6; alle Base-Images per Digest gepinnt. Dependabot für Docker, Compose, NuGet, Actions und pub.

### Non-Goals

- Frische Bestätigung beim Anlegen von Passkeys, „Überall abmelden“, gleiche Login-Dauer für unbekannte Konten und App-Härtung folgen in einer eigenen Change.
