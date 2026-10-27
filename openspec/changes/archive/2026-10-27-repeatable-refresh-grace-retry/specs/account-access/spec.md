## MODIFIED Requirements

### Requirement: Wiederverwendung widerruft die Session

Wird ein ersetzter Refresh-Token nach der Kulanzfrist (`Security:DeviceSessions:ReuseGracePeriod`, Standard 6 Stunden) erneut eingelöst, SHALL die API mit 401 antworten und die Session widerrufen. Innerhalb der Frist SHALL sie den unmittelbaren Vorgänger wiederholt akzeptieren und je Retry den zuletzt ausgestellten Token verwerfen. Nach Benutzung des Nachfolgers und bei älteren Tokens MUST sie mit 401 antworten. Kehrt der zuerst verworfene Token zurück, MUST sie die Session widerrufen.

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
- **THEN** erhält sie Token D, und Token D funktioniert, während der zuerst verworfene Token B bei Vorlage die Session widerruft

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
