# Design

## D1 Client-Adresse hinter zwei Proxys

Kette: Client → host Caddy (TLS) → `127.0.0.1:8081` → Edge-Caddy → API. Host Caddy hat kein `trusted_proxies` und ersetzt einen vom Client gesendeten `X-Forwarded-For` durch die echte Adresse. Der Edge-Caddy vertraut `private_ranges`; erreichbar ist er nur über den Loopback-Port und die Compose-Netze. Er hängt die Gateway-Adresse an: `X-Forwarded-For: <client>, <gateway>`.

Die API vertraut nur `127.0.0.0/8`, `::1`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` und `fc00::/7` bei `ForwardLimit = 2`. Sie geht von rechts durch die Liste und hält am ersten öffentlichen Eintrag an. Ein vom Client vorangestellter Eintrag kann so nicht zur Client-Adresse werden.

## D2 Kulanzzeit ohne stille Übernahme

Bisher: Innerhalb einer Minute nach der Rotation akzeptierte die API den vorherigen Token erneut und machte den zuletzt ausgestellten ungültig, ohne die Session zu widerrufen. Ein Angreifer mit dem vorherigen Token übernahm so die Session, und das echte Gerät bekam nur 401.

Jetzt:
- Pro Rotation ist ein Retry erlaubt (`DiscardedAt` ist bis zur nächsten Rotation gesetzt).
- Der Hash des verworfenen Tokens bleibt in `DiscardedRefreshTokenHash`. Das echte Gerät hat diesen Token nur, wenn seine Antwort nicht verloren ging; dann hat jemand anderes den Retry gemacht. Kommt der Token zurück, wird die Session widerrufen.
- Ein zweiter Retry innerhalb derselben Rotation widerruft die Session ebenfalls.

Der legitime Fall (Antwort verloren, App wiederholt mit dem vorherigen Token) funktioniert weiter.

## D3 Passkey und Sperre

Die Identity-Sperre zählt falsche Passwörter. Ein Passkey lässt sich nicht erraten; die Sperre schützt dort nichts und ermöglicht nur das Aussperren von außen. Die Passkey-Anmeldung prüft daher nur `CanSignInAsync` (aktiv und bestätigt).
