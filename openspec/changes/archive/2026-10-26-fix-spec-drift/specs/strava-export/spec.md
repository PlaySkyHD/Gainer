## MODIFIED Requirements

### Requirement: Fehler und Wiederholung

Der Server SHALL vorübergehende Fehler mit Backoff höchstens sechs Versuche unternehmen (der erste zählt mit) und danach `Failed` speichern. Lehnt Strava den Zugriff ab, MUST der Server die Verbindung als „erneut verbinden“ markieren und keine weiteren Exporte versuchen.

#### Scenario: Strava nicht erreichbar
- **GIVEN** Strava antwortet mit 503
- **WHEN** der Worker sendet
- **THEN** bleibt der Eintrag `Pending` mit späterem nächsten Versuch

#### Scenario: Zugriff in Strava widerrufen
- **GIVEN** der Nutzer hat Gainer in Strava entfernt
- **WHEN** der Token-Refresh abgelehnt wird
- **THEN** zeigt die App „Strava-Verbindung abgelaufen“ mit „Erneut verbinden“
