# account-access Specification

## Purpose
Geschlossener Zugang für eingeladene Konten: Anmeldung mit Passwort oder Passkey, Geräte-Sessions mit Bearer-Tokens, Kontoschutz, Schutz der API vor Missbrauch und strikte Isolation der Fachdaten zwischen Nutzern.

## Requirements

### Requirement: Geschlossene Kontobereitstellung

Das System SHALL neue Konten ausschließlich durch eine betreiberkontrollierte Einladung oder administrative Kontoanlage bereitstellen. Eine öffentliche Selbstregistrierung MUST deaktiviert sein.

#### Scenario: Eingeladenes Konto aktivieren

- **GIVEN** der Betreiber hat für eine Person ein inaktives Konto mit einer gültigen Einladung angelegt
- **WHEN** die Person die Einladung verwendet und gültige Zugangsdaten festlegt
- **THEN** wird ausschließlich dieses Konto aktiviert und die Einladung kann nicht erneut verwendet werden

#### Scenario: Öffentliche Registrierung verhindern

- **GIVEN** eine nicht authentifizierte Person besitzt keine gültige Einladung
- **WHEN** sie über UI oder API versucht, ein Konto anzulegen
- **THEN** wird kein Konto erstellt und die Antwort gibt keine Informationen über bestehende Konten preis

### Requirement: Authentifizierte Sitzungen

Das System MUST geschützte UI- und API-Funktionen auf gültige Sitzungen begrenzen und MUST abgelaufene, widerrufene oder abgemeldete Sitzungen ablehnen.

#### Scenario: Erfolgreiche Anmeldung

- **GIVEN** ein aktives Konto und korrekte Zugangsdaten
- **WHEN** sich der Nutzer anmeldet
- **THEN** wird eine Sitzung für genau dieses Konto erstellt und die private Anwendungsansicht geöffnet

#### Scenario: Ungültige Zugangsdaten

- **GIVEN** eine unbekannte E-Mail-Adresse oder ein falsches Passwort
- **WHEN** eine Anmeldung versucht wird
- **THEN** wird keine Sitzung erstellt und die Antwort verrät nicht, ob das Konto existiert

#### Scenario: Abgelaufene Sitzung

- **GIVEN** eine Sitzung ist abgelaufen oder wurde widerrufen
- **WHEN** damit eine geschützte API-Operation angefordert wird
- **THEN** antwortet die API mit `401 Unauthorized` und führt weder Lese- noch Schreiboperationen aus

### Requirement: Serverseitig bestimmter Nutzerkontext

Das System SHALL die maßgebliche Nutzer-ID für jede fachliche Operation ausschließlich aus der authentifizierten Sitzung ableiten. Eine in Request, lokalem Datensatz oder KI-Werkzeugargument gelieferte Nutzer-ID MUST den Nutzerkontext niemals wechseln oder erweitern.

#### Scenario: Manipulierte Nutzer-ID in einer Mutation

- **GIVEN** Nutzer A ist authentifiziert und kennt die Nutzer-ID von Nutzer B
- **WHEN** Nutzer A eine Mutation mit der Nutzer-ID von Nutzer B übermittelt
- **THEN** wird die Anfrage abgelehnt, keine Entität verändert und kein Datensatz Nutzer B zugeordnet

#### Scenario: Nutzergebundenes KI-Werkzeug

- **GIVEN** Nutzer A ist authentifiziert und der AI Coach ruft ein freigegebenes Werkzeug auf
- **WHEN** das Werkzeug Daten abfragt
- **THEN** begrenzt das Backend den Zugriff auf Nutzer A, ohne eine frei wählbare Nutzer-ID zu akzeptieren

### Requirement: Isolation fachlicher Daten

Das System MUST alle Listen-, Detail-, Schreib-, Synchronisations-, Analyse- und KI-Zugriffe auf die fachlichen Daten des authentifizierten Nutzers begrenzen.

#### Scenario: Nutzergebundene Liste

- **GIVEN** Nutzer A und Nutzer B besitzen jeweils fachliche Datensätze
- **WHEN** Nutzer A eine Liste dieser Datensätze abruft
- **THEN** enthält die Antwort ausschließlich Datensätze von Nutzer A

#### Scenario: Fremde Ressourcen-ID lesen

- **GIVEN** Nutzer A ist authentifiziert und verwendet die Ressourcen-ID eines Datensatzes von Nutzer B
- **WHEN** Nutzer A den Datensatz direkt abruft
- **THEN** antwortet die API mit `404 Not Found` und gibt weder Inhalt noch Eigentümer preis

#### Scenario: Fremde Ressource verändern

- **GIVEN** Nutzer A ist authentifiziert und verwendet die Ressourcen-ID eines Datensatzes von Nutzer B
- **WHEN** Nutzer A eine Änderung oder Löschung anfordert
- **THEN** antwortet die API mit `404 Not Found` und der Datensatz von Nutzer B bleibt unverändert

### Requirement: Lokale Trennung auf gemeinsam genutzten Geräten

Die Anwendung MUST lokale Fachdaten, ausstehende Änderungen und nutzerbezogene Caches nach Konto trennen und SHALL nach einer Abmeldung keine Daten des abgemeldeten Kontos in der UI zugänglich machen.

#### Scenario: Kontowechsel auf demselben Gerät

- **GIVEN** Nutzer A hat lokale Daten gespeichert, sich abgemeldet und Nutzer B meldet sich auf demselben Gerät an
- **WHEN** Nutzer B die Anwendung online oder offline verwendet
- **THEN** werden ausschließlich Daten und Caches von Nutzer B geöffnet und keine Daten von Nutzer A angezeigt oder synchronisiert

#### Scenario: Geschützte Ansicht nach Abmeldung

- **GIVEN** ein Nutzer hat sich abgemeldet
- **WHEN** eine zuvor geöffnete geschützte Ansicht erneut aufgerufen wird
- **THEN** fordert die Anwendung eine Anmeldung und zeigt keine zwischengespeicherten fachlichen Inhalte an

### Requirement: Begrenzte Betreiberfunktionen

Das System MUST Betreiberfunktionen auf Konten, Einladungen und Kontostatus begrenzen und SHALL keine Anwendungsansicht, API, Export- oder Impersonation-Funktion zum Lesen fremder Fitnessdaten anbieten.

#### Scenario: Betreiber verwaltet ein Konto

- **GIVEN** der Betreiber ist für die Kontoverwaltung authentifiziert
- **WHEN** er ein Konto einlädt, deaktiviert oder reaktiviert
- **THEN** kann er die notwendigen Identitätsdaten verwalten, ohne Fitnessdaten des Kontos zu erhalten

#### Scenario: Betreiber fordert fremde Fitnessdaten an

- **GIVEN** der Betreiber besitzt ein eigenes Nutzerkonto und technische Administrationsrechte außerhalb der Anwendung
- **WHEN** er über die Anwendung Fitnessdaten eines anderen Nutzers anfordert
- **THEN** gelten dieselben Isolationsregeln wie für jeden Nutzer und es werden keine fremden Fitnessdaten ausgegeben

### Requirement: Anmeldung erzeugt eine Geräte-Session

`POST /api/v1/auth/login` SHALL bei gültigen Zugangsdaten eines aktiven, bestätigten Kontos mit 200 einen Access-Token, dessen Laufzeit in Sekunden, einen Refresh-Token und dessen Ablaufzeit liefern und eine Geräte-Session mit dem übergebenen Gerätenamen anlegen. Die Antwort MUST NOT ein Cookie setzen. Der Refresh-Token MUST nur als SHA-256-Hash gespeichert werden. Unbekanntes Konto und falsches Passwort MUST dieselbe 401-Antwort mit Code `invalid_credentials` liefern.

#### Scenario: Erfolgreiche Anmeldung
- **GIVEN** ein aktives Konto `athlete@example.test`
- **WHEN** die App sich mit richtigem Passwort und Gerätename „Gainer iPhone“ anmeldet
- **THEN** antwortet die API mit 200, `expiresIn` 900 und einem Refresh-Token, ohne `Set-Cookie`, und `identity.device_sessions` enthält eine Session „Gainer iPhone“ mit 32-Byte-Hash

#### Scenario: Falsches Passwort
- **WHEN** die App sich mit falschem Passwort anmeldet
- **THEN** antwortet die API mit 401 und Code `invalid_credentials`, wie bei einem unbekannten Konto

### Requirement: Refresh rotiert und gleitet

`POST /api/v1/auth/refresh` SHALL für den aktuellen Refresh-Token einer aktiven Session ein neues Token-Paar liefern, den alten Token ersetzen und die Session auf 60 Tage ab jetzt verlängern. Eine Session ohne Refresh MUST nach 60 Tagen ablaufen.

#### Scenario: Regelmäßige Nutzung
- **GIVEN** eine Session, die alle 50 Tage erneuert wird
- **WHEN** 200 Tage vergangen sind
- **THEN** ist die Session weiterhin gültig und läuft 60 Tage nach dem letzten Refresh ab

#### Scenario: Lange nicht genutzt
- **GIVEN** eine Session, deren letzter Refresh 60 Tage und 1 Sekunde zurückliegt
- **WHEN** die App den Refresh-Token einlöst
- **THEN** antwortet die API mit 401 und Code `invalid_refresh_token`

### Requirement: Wiederverwendung widerruft die Session

Wird ein ersetzter Refresh-Token nach der Kulanzfrist (`Security:DeviceSessions:ReuseGracePeriod`, Standard 6 h) eingelöst, SHALL die API 401 liefern und die Session widerrufen. In der Frist SHALL sie den Vorgänger bis zu zehnmal akzeptieren und je Retry den letzten Token verwerfen. Nach Nutzung des Nachfolgers und bei älteren Tokens MUST sie 401 liefern. Ein elfter Retry, ein Retry über 50 verworfene Tokens und jeder verworfene Token jünger als die Leerlauffrist MUST die Session widerrufen.

#### Scenario: Gestohlener Token
- **GIVEN** Token A wurde gegen Token B getauscht
- **WHEN** sieben Stunden später Token A eingelöst wird
- **THEN** antwortet die API mit 401, und weder Token B noch der zugehörige Access-Token funktionieren noch

#### Scenario: Verlorene Antwort
- **GIVEN** Token A wurde gegen Token B getauscht, die Antwort kam nicht an
- **WHEN** die App 30 Minuten später Token A erneut einlöst
- **THEN** erhält sie Token C, und Token C funktioniert

#### Scenario: Zwei verlorene Antworten
- **GIVEN** Token A wurde gegen Token B getauscht, die Antwort kam nicht an, ein Retry mit Token A lieferte Token C, auch diese Antwort kam nicht an
- **WHEN** die App Token A innerhalb der Kulanzfrist ein zweites Mal einlöst
- **THEN** erhält sie Token D, und Token D funktioniert, während jeder verworfene Token (B und C) bei Vorlage die Session widerruft

#### Scenario: Älterer Vorgänger
- **GIVEN** Token A wurde gegen Token B und dieser gegen Token C getauscht
- **WHEN** fünf Minuten später Token A eingelöst wird
- **THEN** antwortet die API mit 401, und Token C funktioniert weiter

#### Scenario: Vorgänger nach Benutzung des Nachfolgers
- **GIVEN** Token A wurde gegen Token B getauscht, ein Retry mit Token A lieferte Token C, und Token C wurde gegen Token D getauscht
- **WHEN** Token A innerhalb der Kulanzfrist erneut eingelöst wird
- **THEN** antwortet die API mit 401

#### Scenario: Gestohlener Token in der Kulanzminute
- **GIVEN** das Gerät hat Token A gegen Token B getauscht, ein Angreifer löst 20 Sekunden später Token A ein und erhält Token C
- **WHEN** das Gerät Token B einlöst
- **THEN** antwortet die API mit 401, und weder Token C noch der zugehörige Access-Token funktionieren noch

#### Scenario: Angreifer nach dem Retry des Geräts
- **GIVEN** Token A wurde gegen Token B getauscht, die Antwort kam nicht an, das Gerät erhielt per Retry mit Token A Token C, danach löste ein Angreifer Token A ein und erhielt Token E
- **WHEN** das Gerät Token C einlöst
- **THEN** antwortet die API mit 401, und weder Token E noch der zugehörige Access-Token funktionieren noch

#### Scenario: Zu viele Retries
- **GIVEN** Token A wurde gegen Token B getauscht, und Token A wurde zehnmal per Retry eingelöst
- **WHEN** Token A innerhalb der Kulanzfrist ein elftes Mal eingelöst wird
- **THEN** antwortet die API mit 401, und der zuletzt ausgestellte Token funktioniert nicht mehr

#### Scenario: Verworfener Token nach weiteren Rotationen
- **GIVEN** das Gerät hat Token A gegen Token B getauscht, ein Angreifer erhielt per Retry mit Token A Token C und tauschte danach zweimal ohne Retry weiter bis Token E
- **WHEN** das Gerät Token B einlöst
- **THEN** antwortet die API mit 401, und Token E funktioniert nicht mehr

#### Scenario: Zwischenrotation und Retry des Angreifers
- **GIVEN** das Gerät hat Token A gegen Token B getauscht, ein Angreifer erhielt per Retry mit Token A Token C, tauschte Token C gegen Token D und erhielt per Retry mit Token C Token E
- **WHEN** das Gerät Token B einlöst
- **THEN** antwortet die API mit 401, und weder Token E noch der zugehörige Access-Token funktionieren noch

#### Scenario: Zu viele gespeicherte verworfene Tokens
- **GIVEN** in fünf Rotationen wurde der Vorgänger je zehnmal per Retry eingelöst, sodass 50 verworfene Tokens gespeichert sind
- **WHEN** nach der nächsten Rotation der Vorgänger innerhalb der Kulanzfrist per Retry eingelöst wird
- **THEN** antwortet die API mit 401, und der zuletzt ausgestellte Token funktioniert nicht mehr

### Requirement: Widerruf wirkt sofort

Jeder Bearer-authentifizierte Request SHALL abgelehnt werden, wenn seine Geräte-Session widerrufen oder abgelaufen ist oder das Konto deaktiviert wurde. Logout SHALL die eigene Session widerrufen; Deaktivieren eines Kontos SHALL alle seine Sessions widerrufen, auch für eine spätere Reaktivierung.

#### Scenario: Logout
- **WHEN** die App sich abmeldet
- **THEN** liefern der bisherige Access-Token und der Refresh-Token 401

#### Scenario: Deaktivierung
- **GIVEN** ein angemeldetes Konto
- **WHEN** der Operator es deaktiviert und später wieder aktiviert
- **THEN** liefert der alte Access-Token sofort 401, und der alte Refresh-Token bleibt auch nach der Reaktivierung ungültig

### Requirement: Keine Browser-Mechanismen

Die API SHALL keine Cookie-Authentifizierung, kein Antiforgery und keine Origin-Prüfung mehr anbieten. `GET /api/v1/auth/antiforgery` MUST 404 liefern. Ein Cookie MUST NOT authentifizieren.

#### Scenario: Fremder Origin
- **GIVEN** ein Konto mit gültigen Zugangsdaten
- **WHEN** ein Login mit `Origin: https://attacker.example` eintrifft
- **THEN** behandelt die API ihn wie jeden anderen Login, ohne 403

### Requirement: App hält die Session selbstständig

Die App SHALL den Access-Token vor Ablauf und nach einem 401 genau einmal erneuern, parallele Requests mit einem Refresh bedienen und nach jeder Rotation den Keychain-Checkpoint mit dem neuen Refresh-Token überschreiben. Der Checkpoint MUST NOT Passwort oder Access-Token enthalten. Checkpoints der Version 1 MUST verworfen werden. Lehnt der Server den Refresh ab, SHALL die App das Konto schließen, den Checkpoint löschen und die Anmeldung mit dem Hinweis zeigen, dass lokale Daten erhalten bleiben.

#### Scenario: Neustart
- **GIVEN** die App wurde beendet und hat nur den Refresh-Token im Keychain
- **WHEN** sie neu startet
- **THEN** erneuert sie die Tokens, öffnet das Konto online und speichert den neuen Refresh-Token

#### Scenario: Paralleler Ablauf
- **GIVEN** der Access-Token läuft in weniger als 30 Sekunden ab
- **WHEN** zwei Requests gleichzeitig starten
- **THEN** sendet die App genau einen Refresh und beide Requests mit dem neuen Access-Token

#### Scenario: Session widerrufen
- **GIVEN** die Session wurde serverseitig widerrufen
- **WHEN** die App den Refresh-Token einlöst
- **THEN** zeigt sie die Anmeldung mit „Deine Anmeldung ist abgelaufen …“ und der Checkpoint ist gelöscht

#### Scenario: Update von einem Cookie-Build
- **GIVEN** im Keychain liegt ein Checkpoint der Version 1
- **WHEN** die neue App startet
- **THEN** verwirft sie ihn und zeigt die Anmeldung

### Requirement: Passkey anlegen

Ein angemeldetes Konto SHALL über `POST /api/v1/auth/passkeys/creation-options` und `POST /api/v1/auth/passkeys` einen Passkey für die Relying Party `gainer.markfort.xyz` mit Nutzerverifikation anlegen können. Antworten mit anderer Origin, mit fremdem, verändertem, abgelaufenem oder bereits genutztem Zustand MUST mit 400 und Code `passkey_rejected` abgelehnt werden.

#### Scenario: Passkey hinzufügen
- **GIVEN** ein angemeldetes Konto ohne Passkey
- **WHEN** der Nutzer unter „Mehr → Passkeys“ einen Passkey hinzufügt und Face ID bestätigt
- **THEN** antwortet die API mit 201, und die Liste zeigt „Gainer iPhone“ mit Erstelldatum

#### Scenario: Fremde Origin
- **WHEN** eine Registrierung mit Origin `https://attacker.example` eintrifft
- **THEN** antwortet die API mit 400 und es wird kein Passkey gespeichert

#### Scenario: Zustand eines anderen Kontos
- **GIVEN** Konto A hat Registrierungsoptionen erhalten
- **WHEN** Konto B die Antwort mit dem Zustand von A einreicht
- **THEN** antwortet die API mit 400, und A kann den Zustand danach noch selbst einlösen

### Requirement: Mit Passkey anmelden

`POST /api/v1/auth/passkeys/request-options` und `POST /api/v1/auth/passkeys/login` SHALL ohne Anmeldung eine Geräte-Session mit Token-Paar starten, wenn die Assertion gültig ist und das Konto aktiv und bestätigt ist. Eine Sperre nach falschen Passwörtern MUST NOT die Passkey-Anmeldung verhindern. Andernfalls MUST die API mit 401 und Code `invalid_passkey` antworten. Ein Zustand MUST nur einmal angenommen werden.

#### Scenario: Anmeldung per Face ID
- **GIVEN** ein Konto mit Passkey
- **WHEN** der Nutzer im Login „Mit Passkey anmelden“ wählt und Face ID bestätigt
- **THEN** ist die App angemeldet und die Geräte-Session heißt „Gainer iPhone“

#### Scenario: Wiederholte Assertion
- **WHEN** dieselbe Assertion mit demselben Zustand ein zweites Mal eingereicht wird
- **THEN** antwortet die API mit 401

#### Scenario: Gesperrt nach falschen Passwörtern
- **GIVEN** ein Konto mit Passkey, gesperrt nach fünf falschen Passwörtern
- **WHEN** der Nutzer sich mit dem Passkey anmeldet
- **THEN** antwortet die API mit 200 und einem Token-Paar

#### Scenario: Deaktiviertes Konto
- **GIVEN** das Konto des Passkeys ist deaktiviert
- **WHEN** der Nutzer sich mit dem Passkey anmeldet
- **THEN** antwortet die API mit 401

#### Scenario: Abbruch
- **WHEN** der Nutzer das System-Sheet abbricht
- **THEN** sendet die App keinen Login und bleibt im bisherigen Zustand

### Requirement: Passkeys verwalten

Ein angemeldetes Konto SHALL seine Passkeys auflisten und einzeln entfernen können. Ein entfernter Passkey MUST NOT mehr anmelden. Ohne Verbindung MUST die App das Anlegen deaktivieren und erklären, warum.

#### Scenario: Entfernen
- **GIVEN** ein angemeldetes Konto hat einen Passkey „Gainer iPhone“
- **WHEN** der Nutzer einen Passkey nach links wischt und bestätigt
- **THEN** antwortet die API mit 204, und eine Anmeldung mit diesem Passkey liefert 401

### Requirement: Domain-Bindung

Der Edge-Container SHALL unter `/.well-known/apple-app-site-association` JSON mit `webcredentials.apps = ["Q7GTYQ282F.xyz.markfort.gainer"]` ausliefern. Die App MUST das Entitlement `webcredentials:gainer.markfort.xyz` tragen, und der signierte Build MUST abbrechen, wenn das Provisioning-Profil Associated Domains nicht enthält.

#### Scenario: Apple fragt die Domain ab
- **GIVEN** der Edge-Container läuft und die App ist für `gainer.markfort.xyz` eingerichtet
- **WHEN** `GET https://gainer.markfort.xyz/.well-known/apple-app-site-association` eintrifft
- **THEN** antwortet der Edge mit 200, `Content-Type: application/json` und der App-ID

### Requirement: Veraltete Tokens blockieren keine Anmeldung

Ein Request mit widerrufenem oder abgelaufenem Access-Token SHALL wie ein Request ohne Token behandelt werden. Geschützte Endpunkte MUST mit 401 antworten, Anmelde-Endpunkte MUST normal funktionieren.

#### Scenario: Anmeldung nach Deaktivierung und Reaktivierung
- **GIVEN** ein Client sendet noch den Access-Token einer widerrufenen Session
- **WHEN** er sich mit Passwort neu anmeldet
- **THEN** antwortet die API mit 200 und einem neuen Token-Paar

### Requirement: Neuer Passkey nur mit frischer Bestätigung

`POST /api/v1/auth/passkeys/creation-options` SHALL nur Optionen liefern, wenn die Geräte-Session des Requests höchstens 5 Minuten zuvor angemeldet wurde oder der Body das richtige Passwort enthält. Andernfalls MUST die API mit 403 und Code `reauthentication_required` antworten, und die App MUST das Passwort abfragen und erneut senden.

#### Scenario: Direkt nach der Anmeldung
- **GIVEN** der Nutzer hat sich vor einer Minute angemeldet
- **WHEN** er einen Passkey hinzufügt
- **THEN** startet Face ID ohne Passwortabfrage

#### Scenario: Später
- **GIVEN** die Anmeldung liegt sechs Minuten zurück
- **WHEN** der Nutzer einen Passkey hinzufügt
- **THEN** fragt die App das Passwort ab und legt den Passkey erst danach an

#### Scenario: Falsches Passwort
- **WHEN** der Nutzer ein falsches Passwort eingibt
- **THEN** antwortet die API mit 403, und die App meldet „Das Passwort war falsch.“

### Requirement: Auf allen Geräten abmelden

`POST /api/v1/auth/logout-all` SHALL alle Geräte-Sessions des angemeldeten Kontos widerrufen, auch die eigene. Passkeys MUST erhalten bleiben. Die App MUST sich erst lokal abmelden, wenn der Server zugestimmt hat, und die Funktion ohne Verbindung deaktivieren.

#### Scenario: Zwei Geräte
- **GIVEN** das Konto ist auf iPhone und iPad angemeldet
- **WHEN** der Nutzer auf dem iPhone „Auf allen Geräten abmelden“ bestätigt
- **THEN** liefern beide Access-Tokens 401, und eine Anmeldung per Passkey funktioniert weiter

#### Scenario: Server nicht erreichbar
- **WHEN** der Aufruf scheitert
- **THEN** bleibt das iPhone angemeldet, und ein Dialog erklärt, dass die anderen Geräte nicht abgemeldet wurden

### Requirement: Login verrät keine Konten

Für eine unbekannte E-Mail-Adresse und für gesperrte, inaktive oder unbestätigte Konten SHALL der Login einen Passwort-Hash berechnen, damit die Antwortzeit der einer falschen Passwortangabe entspricht. Die Antwort MUST in allen Fällen 401 mit Code `invalid_credentials` sein.

#### Scenario: Unbekannte E-Mail
- **GIVEN** zu der eingegebenen E-Mail-Adresse existiert kein Konto
- **WHEN** sich jemand mit dieser E-Mail-Adresse anmeldet
- **THEN** antwortet die API nach einer Passwortprüfung mit 401 `invalid_credentials`

### Requirement: Kein Einblick im App-Switcher

Die App SHALL beim Wechsel in den Hintergrund ihren Inhalt mit einer Unschärfe verdecken und sie beim Zurückkehren entfernen. System-Sheets wie Face ID MUST NOT die Unschärfe auslösen.

#### Scenario: App-Switcher
- **GIVEN** die App zeigt geschützte Inhalte
- **WHEN** der Nutzer die App in den Hintergrund schickt
- **THEN** zeigt der App-Switcher eine unscharfe Vorschau

### Requirement: Limits gelten pro Client

Die API SHALL als Client-Adresse den ersten öffentlichen Eintrag von rechts in `X-Forwarded-For` verwenden und dabei nur Loopback und privaten Netzen als Proxy vertrauen. Anmeldung (Passwort und Passkey) MUST auf 30, Token-Refresh auf 60 und `/health/ready` auf 30 Anfragen pro Minute und Client begrenzt sein; darüber antwortet die API mit 429. Das Limit eines Clients MUST NOT andere Clients betreffen.

#### Scenario: Ein Client überschreitet das Limit
- **GIVEN** Client 203.0.113.20 hat 30-mal `/health/ready` abgefragt
- **WHEN** er ein weiteres Mal anfragt und Client 203.0.113.21 ebenfalls
- **THEN** erhält 203.0.113.20 eine 429 und 203.0.113.21 eine 200

#### Scenario: Vorangestellte Adresse
- **WHEN** ein Request mit `X-Forwarded-For: 198.51.100.1, 203.0.113.10` ankommt
- **THEN** gilt 203.0.113.10 als Client-Adresse

### Requirement: Größenlimit pro Endpunkt

Request-Bodies SHALL höchstens 1 MiB groß sein, außer ein Endpunkt erlaubt mit `[RequestSizeLimit]` mehr. Die Mahlzeit-Schätzung MUST Requests bis 8 MiB annehmen und größere mit 413 ablehnen.

#### Scenario: Foto über 1 MiB
- **GIVEN** die App hat ein 3 MB großes Foto für die Mahlzeit-Schätzung ausgewählt
- **WHEN** die App das Foto sendet
- **THEN** erreicht es die Schätzung

#### Scenario: Großer Body an einem anderen Endpunkt
- **GIVEN** ein Endpunkt ohne `[RequestSizeLimit]`-Erlaubnis für mehr als 1 MiB
- **WHEN** ein 2-MiB-Body an diesen Endpunkt geht
- **THEN** antwortet die API mit 413

### Requirement: Export der eigenen Daten

Das System SHALL einem angemeldeten Nutzer alle eigenen Daten als JSON-Datei bereitstellen, nur für den aus der Sitzung bestimmten Nutzer: den aktuellen Stand jeder Sync-Ressource ohne gelöschte und im Abschnitt `coachMemories` alle Gedächtnis-Einträge. Der Export MUST NOT Passwörter, Passkeys, Sessions, Tokens, Geräte oder Integrationszugänge enthalten. Die Datei SHALL Format-Kennzeichen, Schemaversion, Exportzeitpunkt und Server-Revision tragen. Der Endpunkt MUST pro Nutzer begrenzt sein.

#### Scenario: Vollständiger Export

- **GIVEN** ein Nutzer hat Trainings, Ernährungstage und Check-ins, eine Ressource mehrfach geändert und eine gelöscht
- **WHEN** er den Export anfordert
- **THEN** enthält die Datei jede vorhandene Ressource genau einmal in ihrer neuesten Version und die gelöschte nicht

#### Scenario: Gedächtnis im Export

- **GIVEN** ein Nutzer hat zwei Einträge im Coach-Gedächtnis
- **WHEN** er den Export anfordert
- **THEN** enthält der Abschnitt `coachMemories` beide Einträge mit Kategorie, Text, Zeitstempeln und Version, neueste zuerst, und die Schemaversion bleibt 1

#### Scenario: Keine fremden Daten

- **GIVEN** zwei Nutzer haben Daten und Gedächtnis-Einträge
- **WHEN** der erste Nutzer exportiert
- **THEN** enthält die Datei keine Ressource und keinen Gedächtnis-Eintrag des zweiten Nutzers

### Requirement: Datenexport in der App

Die App SHALL den Export unter „Mehr“ anbieten und als Datei über das iOS-Teilen-Sheet weitergeben. Sie SHALL ihn nur mit Verbindung anbieten und auf noch nicht gesendete Änderungen hinweisen.

#### Scenario: Ohne Verbindung

- **GIVEN** die App ist offline
- **WHEN** der Nutzer den Export-Screen öffnet
- **THEN** ist „Export erstellen“ deaktiviert und der Screen nennt den Grund

#### Scenario: Noch nicht gesendete Änderungen

- **GIVEN** das Gerät hat Änderungen, die noch nicht beim Server sind
- **WHEN** der Nutzer den Export-Screen öffnet
- **THEN** weist der Screen darauf hin, dass diese Änderungen im Export fehlen

#### Scenario: Zu viele Exporte

- **GIVEN** ein Nutzer hat das Export-Limit im aktuellen Zeitfenster ausgeschöpft
- **WHEN** er erneut exportiert
- **THEN** antwortet der Server mit `429` und die App zeigt einen Hinweis zum späteren Versuch
