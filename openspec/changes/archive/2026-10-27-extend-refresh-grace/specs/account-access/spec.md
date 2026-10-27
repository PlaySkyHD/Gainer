## MODIFIED Requirements

### Requirement: Wiederverwendung widerruft die Session

Wird ein ersetzter Refresh-Token nach der Kulanzfrist (`Security:DeviceSessions:ReuseGracePeriod`, Standard 6 Stunden) erneut eingelöst, SHALL die API mit 401 antworten und die Session widerrufen. Innerhalb der Frist SHALL sie den unmittelbaren Vorgänger einmal akzeptieren und den zuletzt ausgestellten Token verwerfen. Ältere Tokens MUST mit 401 abgelehnt werden. Kehrt der verworfene Token zurück oder folgt ein zweiter Retry, MUST die API die Session widerrufen.

#### Scenario: Gestohlener Token
- **GIVEN** Token A wurde gegen Token B getauscht
- **WHEN** sieben Stunden später Token A eingelöst wird
- **THEN** antwortet die API mit 401, und weder Token B noch der zugehörige Access-Token funktionieren noch

#### Scenario: Verlorene Antwort
- **GIVEN** Token A wurde gegen Token B getauscht, die Antwort kam nicht an
- **WHEN** die App 30 Minuten später Token A erneut einlöst
- **THEN** erhält sie Token C, und Token C funktioniert

#### Scenario: Älterer Vorgänger
- **GIVEN** Token A wurde gegen Token B und dieser gegen Token C getauscht
- **WHEN** fünf Minuten später Token A eingelöst wird
- **THEN** antwortet die API mit 401, und Token C funktioniert weiter

#### Scenario: Gestohlener Token in der Kulanzminute
- **GIVEN** das Gerät hat Token A gegen Token B getauscht, ein Angreifer löst 20 Sekunden später Token A ein und erhält Token C
- **WHEN** das Gerät Token B einlöst
- **THEN** antwortet die API mit 401, und weder Token C noch der zugehörige Access-Token funktionieren noch
