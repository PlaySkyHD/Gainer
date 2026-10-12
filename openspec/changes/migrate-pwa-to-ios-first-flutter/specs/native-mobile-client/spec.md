## Purpose

Diese Capability bietet die bestehende private Gainer-Kernreise als iOS-orientierten nativen Client mit sicherem Kontozugang und zugänglicher Bedienung an.

## ADDED Requirements

### Requirement: Fachliche Parität der privaten Kernreise

Die App MUST Zugang, Einladungsannahme, berechtigte Kontooperator-Funktionen, Körperziele/Check-ins, Übungskatalog/eigene Übungen, Templates/Rotation, Workouts/Sätze/Previous Performance/Historie, Ernährungstage/Gerichte/Zielpläne/Food-Suche/Barcode/Labelscan, Fortschritt und lesenden Coach anbieten. Fachregeln der aktiven Changes MUST erhalten bleiben; historische Workout-Snapshots DÜRFEN durch spätere Template-Änderungen nicht verändert werden. Onlinepflichtige Funktionen MUST offline einen erklärten Zustand mit Retry statt erfundener Ergebnisse anzeigen.

#### Scenario: Fachliche Parität prüfen
- **GIVEN** dokumentierte PWA-Akzeptanzfälle und dieselben eigenen Serverdaten
- **WHEN** der Nutzer die entsprechenden Journeys in der iOS-App durchläuft
- **THEN** stimmen gespeicherte Fachdaten und Validierung mit den bestehenden Verträgen überein und Änderungen an Templates verändern keine abgeschlossenen Workout-Snapshots

#### Scenario: Coach ohne Verbindung
- **GIVEN** lokale Trackingdaten und keine Netzwerkverbindung
- **WHEN** der Nutzer den Coach öffnet
- **THEN** bleiben lokale Trackingfunktionen nutzbar und eine neue Coach-Anfrage wird als online erforderlich mit Retry angezeigt

### Requirement: Sichere native Sitzung und Nutzerisolation

Die App MUST bestehende eingeladene Konten über den authentifizierten API-Vertrag nutzen, Sitzungsgeheimnisse geschützt und hostgebunden speichern und Passwörter nach der Anmeldung verwerfen. Schreibende Requests MUST gültigen Origin- und Antiforgery-Schutz erfüllen. Neue Sync-/Handover-Requests MUST `X-Gainer-Account-Id` mit der unveränderlichen lokalen Konto-ID auf allen Reads und Writes mitsenden. Die API MUST einen vorhandenen Header gegen `IUserContext.UserId` derselben Anfrage prüfen und bei ungültigem oder abweichendem Konto vor Datenrückgabe oder Side-Effect `409 account_changed` liefern; ältere Clients ohne Header bleiben kompatibel. Der Header ist keine Autorität und ersetzt keinen Sitzungsschutz. Ein abgelaufenes Konto MUST erneut authentifiziert werden, bevor Daten gesendet werden; ein Kontowechsel DARF Daten des vorherigen Kontos weder anzeigen noch senden.

#### Scenario: Native Anmeldung und Sessionablauf
- **GIVEN** ein bestehendes Konto und die konfigurierte HTTPS-API
- **WHEN** Anmeldung, authentifizierte Mutation und später ein Request mit abgelaufener Sitzung erfolgen
- **THEN** gelingt die Mutation nur mit gültiger Sitzung und Request-Schutz und der spätere Upload pausiert bis zur erneuten Anmeldung ohne Verlust der Outbox

#### Scenario: Fremde Daten bleiben isoliert
- **GIVEN** Konto A besitzt lokale und ausstehende Daten
- **WHEN** Konto B angemeldet wird oder eine Ressource von A anfordert
- **THEN** zeigt und sendet der Client ausschließlich B-Daten und die API verweigert fremde Ressourcen unabhängig von übergebenen IDs

#### Scenario: Konto wechselt während eines ausstehenden Uploads
- **GIVEN** eine Mutation gehört zum lokalen Konto A und ein asynchroner Sync hat begonnen
- **WHEN** die serverseitige Sitzung vor oder nach dem Antiforgery-Bootstrap zu B wechselt
- **THEN** wird der Upload durch den Vergleich der Bootstrap-Identität beziehungsweise den identitätsgebundenen RequestToken blockiert und keine A-Trackingdaten werden als B-Daten angelegt

#### Scenario: Konto wechselt zwischen Bootstrap und Sync-Pull
- **GIVEN** ein Sync-Client hat Konto A lokal gebunden und Cookie B ist im API-Request aktiv
- **WHEN** der Client `GET /api/v1/sync/changes` mit `X-Gainer-Account-Id: A` oder eine Sync-/Handover-Schreiboperation mit diesem Header sendet
- **THEN** antwortet die API mit `409 account_changed` vor Datenrückgabe und vor jeder Zustandsänderung; derselbe Request unter Cookie A mit Header A funktioniert, und ein Request ohne Header bleibt für Legacy-Clients zulässig

### Requirement: iOS-Bedienung und zugängliches Layout

Die iOS-App MUST Systemtypografie, nachvollziehbare Navigation einschließlich Zurück-Geste, direktes Touch-Feedback und sinnvolle Haptik bieten. Layouts MUST Safe Areas, Tastatur, Rotation, große Schrift, VoiceOver, Hell/Dunkel und reduzierte Bewegung berücksichtigen. Gesten und Übergänge MUST abbrechbar bleiben; Android-Verfügbarkeit ist keine Voraussetzung für die iOS-Abnahme.

#### Scenario: Große Schrift und reduzierte Bewegung
- **GIVEN** große Systemschrift und reduzierte Bewegung sind aktiviert
- **WHEN** der Nutzer einen Ernährungseintrag bearbeitet und per Zurück-Geste navigiert
- **THEN** bleiben Pflichtfelder und Aktionen erreichbar, keine Inhalte überlaufen und die Rücknavigation bleibt ohne erzwungene große Bewegung verständlich

#### Scenario: Einladung in der App öffnen
- **GIVEN** ein gültiger Einladungslink oder ein vom Nutzer eingefügter Einladungstoken
- **WHEN** die App die Einladung nach Nutzeraktion öffnet
- **THEN** erfolgt keine automatische Annahme, der Nutzer bestätigt sein Passwort und ungültige oder abgelaufene Einladungen zeigen einen Fehler ohne Token-Logging
