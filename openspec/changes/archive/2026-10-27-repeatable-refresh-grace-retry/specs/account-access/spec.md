## MODIFIED Requirements

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
