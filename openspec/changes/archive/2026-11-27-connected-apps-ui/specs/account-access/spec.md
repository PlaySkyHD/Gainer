## ADDED Requirements

### Requirement: Verbundene Apps in der App

Die App SHALL im Profil neben den Passkeys den Screen „Verbundene Apps“ anbieten: je App Name, Verbindungsdatum und letzte Nutzung, Trennen nach Bestätigung und danach eine neu geladene Liste. Ohne verbundene App SHALL er die Einrichtung in ChatGPT mit der kopierbaren MCP-Adresse erklären. Während eine Trennung läuft, MUST NOT eine weitere angeboten werden.

#### Scenario: ChatGPT trennen
- **GIVEN** ChatGPT ist als App verbunden
- **WHEN** der Nutzer die Zeile antippt und „Trennen“ wählt
- **THEN** ruft die App `DELETE /api/v1/auth/connectors/{id}` auf und lädt die Liste neu, ChatGPT steht nicht mehr darin

#### Scenario: Keine App verbunden
- **GIVEN** das Konto hat keine verbundene App
- **WHEN** der Nutzer „Verbundene Apps“ öffnet
- **THEN** sieht er „Kein Assistent verbunden“, einen Satz zur Einrichtung und die MCP-Adresse, die er per Tippen kopiert

#### Scenario: Offline
- **GIVEN** das Gerät hat keine Verbindung zum Server
- **WHEN** der Nutzer „Verbundene Apps“ öffnet
- **THEN** sieht er den Hinweis, dass verbundene Apps nur mit Verbindung verwaltet werden, und „Erneut versuchen“
