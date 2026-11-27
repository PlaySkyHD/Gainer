## ADDED Requirements

### Requirement: Verbundene Apps als eigene Session-Art

Eine OAuth-Freigabe SHALL eine Session der Art „verbundene App“ anlegen, die Rotation, Ablauf, Wiederverwendungserkennung und Widerruf der Geräte-Sessions teilt. Ihr Access-Token MUST ausschließlich den MCP-Endpunkt öffnen; jeder andere geschützte Endpunkt MUST es wie ein fehlendes Token mit 403 ablehnen. „Auf allen Geräten abmelden“ MUST auch verbundene Apps widerrufen.

#### Scenario: Connector-Token an der Sync-API
- **GIVEN** das Access-Token einer verbundenen App
- **WHEN** es `POST /api/v1/sync/mutations` aufruft
- **THEN** antwortet die API mit 403 und ändert nichts

### Requirement: Verbundene Apps verwalten

`GET /api/v1/auth/connectors` SHALL die aktiven verbundenen Apps des Kontos mit Name, Erstellung und letzter Nutzung liefern, `DELETE /api/v1/auth/connectors/{id}` SHALL eine davon sofort widerrufen. Beide MUST nur mit einem App-Token funktionieren und MUST NOT Sessions anderer Konten oder Geräte-Sessions betreffen.

#### Scenario: Widerruf
- **GIVEN** ChatGPT ist als App verbunden
- **WHEN** der Nutzer sie in Gainer widerruft
- **THEN** antwortet der MCP-Endpunkt auf das bisherige Token mit 401
