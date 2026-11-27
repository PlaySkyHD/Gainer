# Design

## Kontext

ChatGPT verbindet entfernte MCP-Server über Streamable HTTP. Sobald Tools Nutzerdaten lesen, erwartet es OAuth 2.1 mit PKCE S256, Protected-Resource-Metadaten (RFC 9728), Authorization-Server-Metadaten (RFC 8414) und eine Client-Registrierung (dynamisch nach RFC 7591 oder per Client-ID-Metadatendokument). Gainer hat Passkey-Login, Geräte-Sessions mit rotierenden Refresh-Tokens und Bearer-Access-Tokens mit 15 Minuten Laufzeit, aber keinen Browser-Login.

## Entscheidungen

### MCP-SDK statt eigener Protokollimplementierung

`ModelContextProtocol.AspNetCore` (offizielles C#-SDK) liefert Streamable HTTP, Tool-Schemas und JSON-RPC. Eine eigene Implementierung des Protokolls wäre fehleranfällig und müsste Spezifikationsänderungen nachziehen. Der Server läuft zustandslos (`Stateless = true`), jede Anfrage trägt ihr Token.

### Kein OAuth-Framework, sondern Geräte-Sessions

OpenIddict oder ein externer Identity-Provider brächten eine zweite Token- und Sessionverwaltung. Stattdessen ist eine verbundene App eine `DeviceSession` mit `Kind = Connector`:

- Refresh-Token-Rotation, Wiederverwendungserkennung, Leerlauf-Ablauf und Widerruf bei jeder Anfrage gelten unverändert.
- Das Access-Token ist dasselbe geschützte Bearer-Ticket wie in der App, mit zusätzlichem Claim `gainer:scope = connector`.
- „Auf allen Geräten abmelden“ trennt auch verbundene Apps.

### Abgrenzung der Tokens

- Standard- und Fallback-Richtlinie sowie die Betreiber-Richtlinie verlangen zusätzlich, dass der Claim `gainer:scope` fehlt. Ein Connector-Token öffnet also keinen App-Endpunkt (Sync, Mutationen, Export, Passkeys).
- Der MCP-Endpunkt verlangt die Richtlinie `Connector` (Claim vorhanden). App-Tokens erhalten dort 403 mit `insufficient_scope`.

### Zustandslose Client-Registrierung

`POST /api/v1/oauth/register` speichert nichts. Die `client_id` ist ein mit Data Protection geschütztes Dokument aus Name und Redirect-URIs. Autorisierung und Token-Endpunkt entschlüsseln es. Redirect-URIs MUST HTTPS sein und auf einem konfigurierten Host liegen (`Security:Connectors:AllowedRedirectHosts`, Standard `chatgpt.com`, `chat.openai.com`, `claude.ai`, `claude.com`). Damit kann niemand einen Code auf eine fremde Seite umleiten.

### Freigabeseite ohne Cookies

`GET /api/v1/oauth/authorize` prüft die Parameter und liefert eine HTML-Seite. Die Anfrage reist als geschütztes, zehn Minuten gültiges Dokument in der Seite mit. Das Skript (`/api/v1/oauth/authorize.js`, CSP `script-src 'self'`) holt Passkey-Optionen über den bestehenden Endpunkt, ruft WebAuthn im Browser auf und sendet die Assertion an `POST /api/v1/oauth/authorize/approve`. Der Server prüft Passkey und Konto wie beim App-Login und antwortet mit der Redirect-URL samt Code. Es entsteht kein Cookie, die Anforderung „Keine Browser-Mechanismen“ bleibt erfüllt. Die Passkey-Origin `https://{ServerDomain}` stimmt mit der Seite überein.

### Autorisierungscodes im Speicher

Codes leben 60 Sekunden, einmal verwendbar, im `IMemoryCache` (Schlüssel: SHA-256 des Codes). Die API läuft als eine Instanz; ein Neustart während der Freigabe verlangt nur eine erneute Freigabe.

### Tools

Fünf lesende Tools mit `ReadOnly`-Annotation auf Basis von `IInsightQueries`, `IWorkoutHistoryQueries`, `IExerciseCatalogQueries` und `IExerciseResolver`, wie der Coach: `get_overview`, `list_workouts`, `get_workout`, `search_exercises`, `get_exercise_progress`. Der Nutzer kommt aus dem Token (`IUserContext`), nie aus Tool-Argumenten. Tool-Aufrufe werden nicht mit Inhalten protokolliert.

### CSP am Edge

Der Edge setzt seine strenge CSP nur noch als Vorgabe (`?Content-Security-Policy`). Die Freigabeseite sendet ihre eigene Richtlinie (`script-src 'self'`, Stil per Hash), alle anderen Antworten behalten die Vorgabe. Ein Löschen des Headers am Edge würde auch die Richtlinie der API entfernen, weil Caddy Löschungen erst nach der Antwort des Upstreams anwendet.

## Risiken

- Daten verlassen Gainer in Richtung des KI-Anbieters. Das ist die ausdrückliche Entscheidung des Nutzers bei der Freigabe; die Seite nennt den Empfänger.
- WebAuthn-JSON-Hilfen (`parseRequestOptionsFromJSON`, `toJSON`) fehlen in älteren Browsern; das Skript dekodiert dann selbst.
- Schreibende Tools brauchen ein eigenes Design wegen des Einzelschreiber-Modells und sind nicht Teil dieser Änderung.
