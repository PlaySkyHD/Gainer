# strava-export

## ADDED Requirements

### Requirement: Strava-Konto verbinden

Die App SHALL unter „Mehr → Strava“ eine Verbindung per Strava-OAuth anbieten. Der Server MUST den Code selbst tauschen, Tokens verschlüsselt speichern und MUST NOT Tokens oder Client-Secret an die App geben. Der `state` MUST an den Nutzer gebunden, höchstens 10 Minuten gültig und nur einmal verwendbar sein.

#### Scenario: Verbinden
- **GIVEN** ein angemeldeter Nutzer ohne Strava-Verbindung
- **WHEN** er „Mit Strava verbinden“ tippt und in Strava zustimmt
- **THEN** zeigt der Screen „Verbunden als <Name>“, „Cardio-Einheiten“ ist an und „Krafttraining“ aus

#### Scenario: Zustimmung ohne Schreibrecht
- **GIVEN** der Nutzer entfernt in Strava das Recht zum Hochladen
- **WHEN** Strava auf den Callback leitet
- **THEN** speichert der Server keine Verbindung und die App meldet „Gainer braucht das Recht, Aktivitäten hochzuladen.“

#### Scenario: Fremder oder alter State
- **GIVEN** ein `state` eines anderen Nutzers, ein abgelaufener oder ein bereits benutzter
- **WHEN** der Callback ihn erhält
- **THEN** speichert der Server nichts und leitet mit `result=failed` weiter

#### Scenario: Nicht eingerichtet
- **GIVEN** der Server hat keine Strava-Konfiguration
- **WHEN** der Nutzer „Strava“ öffnet
- **THEN** ist „Mit Strava verbinden“ nicht verfügbar und der Grund wird genannt

### Requirement: Arten einstellbar exportieren

Der Server SHALL beendete Einheiten nur für eingeschaltete Arten exportieren. Cardio MUST standardmäßig an, Krafttraining standardmäßig aus sein. Das Einschalten MUST NOT ältere Einheiten exportieren.

#### Scenario: Cardio automatisch
- **GIVEN** Cardio ist an
- **WHEN** eine Cardio-Einheit synchronisiert wird und 2 Minuten unverändert bleibt
- **THEN** lädt der Server sie als TCX mit Pulskurve hoch und speichert die Strava-Aktivitäts-Id

#### Scenario: Krafttraining aus
- **GIVEN** Krafttraining ist aus
- **WHEN** ein Workout beendet und synchronisiert wird
- **THEN** sendet der Server nichts an Strava

#### Scenario: Krafttraining eingeschaltet
- **GIVEN** zwei Workouts von gestern und Krafttraining wird heute eingeschaltet
- **WHEN** heute ein Workout endet
- **THEN** exportiert der Server nur das heutige Workout als „Weight Training“

### Requirement: Kein doppelter Export

Der Server MUST je Einheit und Strava-Athlet höchstens eine Aktivität anlegen. Wiederholungen nach Fehlern MUST denselben Ledger-Eintrag nutzen.

#### Scenario: Strava meldet Duplikat
- **GIVEN** ein Upload, den Strava als „duplicate of activity 42“ ablehnt
- **WHEN** der Worker den Upload prüft
- **THEN** gilt der Export mit Aktivität 42 als erledigt

#### Scenario: Erneuter Durchlauf
- **GIVEN** eine erledigte Einheit
- **WHEN** der Worker erneut läuft
- **THEN** sendet er sie nicht noch einmal

### Requirement: Fehler und Wiederholung

Der Server SHALL vorübergehende Fehler mit Backoff höchstens sechsmal wiederholen und danach `Failed` speichern. Lehnt Strava den Zugriff ab, MUST der Server die Verbindung als „erneut verbinden“ markieren und keine weiteren Exporte versuchen.

#### Scenario: Strava nicht erreichbar
- **GIVEN** Strava antwortet mit 503
- **WHEN** der Worker sendet
- **THEN** bleibt der Eintrag `Pending` mit späterem nächsten Versuch

#### Scenario: Zugriff in Strava widerrufen
- **GIVEN** der Nutzer hat Gainer in Strava entfernt
- **WHEN** der Token-Refresh abgelehnt wird
- **THEN** zeigt die App „Strava-Verbindung abgelaufen“ mit „Erneut verbinden“

### Requirement: Einzeln senden und Status

Die Cardio-Detailansicht SHALL den Strava-Stand einer synchronisierten Einheit zeigen und für nicht gesendete oder fehlgeschlagene Einheiten „An Strava senden“ anbieten, unabhängig vom Schalter der Art.

#### Scenario: Ältere Einheit senden
- **GIVEN** eine Cardio-Einheit von vor der Verbindung
- **WHEN** der Nutzer „An Strava senden“ tippt
- **THEN** zeigt die Zeile „Wird gesendet“ und nach dem Upload „Gesendet“

#### Scenario: Offline
- **GIVEN** keine Verbindung zum Server
- **WHEN** der Nutzer die Detailansicht öffnet
- **THEN** erscheint keine Strava-Aktion

### Requirement: Nutzerisolation und Trennen

Status, Einstellungen und Exporte MUST nur dem eigenen Konto gehören. „Verbindung trennen“ SHALL den Zugriff bei Strava widerrufen (best effort) und die Tokens löschen.

#### Scenario: Fremder Export
- **GIVEN** Nutzer A und B, B hat eine Cardio-Einheit
- **WHEN** A einen Export mit der Id von B anfordert
- **THEN** antwortet der Server 404 und legt nichts an

#### Scenario: Trennen
- **GIVEN** eine verbundene Strava-Verbindung
- **WHEN** der Nutzer „Verbindung trennen“ bestätigt
- **THEN** sind die Tokens gelöscht und der Worker exportiert nichts mehr
