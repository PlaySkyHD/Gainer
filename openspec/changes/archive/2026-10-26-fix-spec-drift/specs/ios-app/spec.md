## MODIFIED Requirements

### Requirement: Kein Web-Client

Das Repository SHALL keinen Web-Client mehr enthalten. Die iOS-App MUST der einzige Client der API sein. Build, CI und Deploy MUST ohne Node.js und npm auskommen, ausgenommen der Workflow „OpenSpec“, der beides nur für die gepinnte OpenSpec-CLI in `tools/openspec` nutzt.

#### Scenario: CI ohne Node
- **GIVEN** ein Pull Request gegen `main`
- **WHEN** der Workflow „CI“ läuft
- **THEN** richtet kein Schritt Node.js ein und kein Schritt ruft `npm` oder `npx` auf

#### Scenario: Node nur für die Spec-Prüfung
- **GIVEN** ein Pull Request, der `openspec/` ändert
- **WHEN** der Workflow „OpenSpec“ läuft
- **THEN** richtet er Node.js ein und installiert die CLI aus `tools/openspec`, und keine andere Stufe nutzt npm

#### Scenario: AppHost ohne Web-Ressource
- **GIVEN** der Aspire AppHost im Entwicklungsmodus
- **WHEN** seine Ressourcen aufgelistet werden
- **THEN** gibt es `postgres`, `gainer-db`, `backup-storage`, `backup-blobs` und `api`, aber keine Ressource `web`
