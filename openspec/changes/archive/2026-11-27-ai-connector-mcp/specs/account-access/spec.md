## ADDED Requirements

### Requirement: Verbundene Apps als eigene Session-Art

Eine OAuth-Freigabe SHALL eine Session der Art „verbundene App“ anlegen, die Rotation, Ablauf, Wiederverwendungserkennung und Widerruf der Geräte-Sessions teilt. Ihr Access-Token MUST ausschließlich den MCP-Endpunkt öffnen; außerhalb davon MUST die API es wie ein fehlendes Token behandeln, unabhängig von der Richtlinie des Endpunkts. „Auf allen Geräten abmelden“ MUST auch verbundene Apps widerrufen.

#### Scenario: Connector-Token an der Sync-API
- **GIVEN** das Access-Token einer verbundenen App
- **WHEN** es `POST /api/v1/sync/mutations` aufruft
- **THEN** antwortet die API mit 401 und ändert nichts

### Requirement: Refresh verbundener Apps an den Client gebunden

Eine verbundene App MUST ihr Refresh-Token nur über den OAuth-Token-Endpunkt und nur für den Client rotieren, für den sie entstand. Tokens anderer Clients oder von App-Geräte-Sessions MUST die API ablehnen, ohne die betroffene Session zu verändern. Verbindet derselbe Client sich erneut, MUST die vorherige Session widerrufen werden.

#### Scenario: Refresh-Token der App am OAuth-Endpunkt
- **GIVEN** das Refresh-Token einer App-Geräte-Session
- **WHEN** es an `POST /api/v1/oauth/token` geschickt wird
- **THEN** antwortet die API mit `invalid_grant` und das Token bleibt für die App gültig

#### Scenario: Erneut verbunden
- **GIVEN** ChatGPT ist verbunden
- **WHEN** derselbe Client sich erneut freigeben lässt
- **THEN** listet `GET /api/v1/auth/connectors` nur eine Verbindung

### Requirement: Verbundene Apps verwalten

`GET /api/v1/auth/connectors` SHALL die aktiven verbundenen Apps des Kontos mit Name, Erstellung und letzter Nutzung liefern, `DELETE /api/v1/auth/connectors/{id}` SHALL eine davon sofort widerrufen. Beide MUST nur mit einem App-Token funktionieren und MUST NOT Sessions anderer Konten oder Geräte-Sessions betreffen.

#### Scenario: Widerruf
- **GIVEN** ChatGPT ist als App verbunden
- **WHEN** der Nutzer sie in Gainer widerruft
- **THEN** antwortet der MCP-Endpunkt auf das bisherige Token mit 401
