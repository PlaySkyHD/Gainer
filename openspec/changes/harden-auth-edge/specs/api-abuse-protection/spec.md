# api-abuse-protection

## ADDED Requirements

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

Request-Bodies SHALL höchstens 1 MiB groß sein, außer ein Endpunkt erlaubt mit `[RequestSizeLimit]` mehr. Die Mahlzeit-Schätzung MUST Fotos bis 8 MB annehmen und Requests über 9 MiB mit 413 ablehnen.

#### Scenario: Foto über 1 MiB
- **WHEN** die App ein 3-MB-Foto zur Mahlzeit-Schätzung sendet
- **THEN** erreicht es die Schätzung

#### Scenario: Großer Body an einem anderen Endpunkt
- **WHEN** ein 2-MiB-Body an einen anderen Endpunkt geht
- **THEN** antwortet die API mit 413
