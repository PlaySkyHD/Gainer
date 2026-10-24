## Purpose

Diese Capability stellt einen geschlossenen Nutzerzugang und die konsequente Isolation sämtlicher fachlicher Daten zwischen eingeladenen Nutzern sicher.

## ADDED Requirements

### Requirement: Geschlossene Kontobereitstellung

Das System SHALL neue Konten ausschließlich durch eine betreiberkontrollierte Einladung oder administrative Kontoanlage bereitstellen. Eine öffentliche Selbstregistrierung MUST deaktiviert sein.

#### Scenario: Eingeladenes Konto aktivieren

- **GIVEN** der Betreiber hat für eine Person ein inaktives Konto mit einer gültigen Einladung angelegt
- **WHEN** die Person die Einladung verwendet und gültige Zugangsdaten festlegt
- **THEN** wird ausschließlich dieses Konto aktiviert und die Einladung kann nicht erneut verwendet werden

#### Scenario: Öffentliche Registrierung verhindern

- **GIVEN** eine nicht authentifizierte Person besitzt keine gültige Einladung
- **WHEN** sie über UI oder API versucht, ein Konto anzulegen
- **THEN** wird kein Konto erstellt und die Antwort gibt keine Informationen über bestehende Konten preis

### Requirement: Authentifizierte Sitzungen

Das System MUST geschützte UI- und API-Funktionen auf gültige Sitzungen begrenzen und MUST abgelaufene, widerrufene oder abgemeldete Sitzungen ablehnen.

#### Scenario: Erfolgreiche Anmeldung

- **GIVEN** ein aktives Konto und korrekte Zugangsdaten
- **WHEN** sich der Nutzer anmeldet
- **THEN** wird eine Sitzung für genau dieses Konto erstellt und die private Anwendungsansicht geöffnet

#### Scenario: Ungültige Zugangsdaten

- **GIVEN** eine unbekannte E-Mail-Adresse oder ein falsches Passwort
- **WHEN** eine Anmeldung versucht wird
- **THEN** wird keine Sitzung erstellt und die Antwort verrät nicht, ob das Konto existiert

#### Scenario: Abgelaufene Sitzung

- **GIVEN** eine Sitzung ist abgelaufen oder wurde widerrufen
- **WHEN** damit eine geschützte API-Operation angefordert wird
- **THEN** antwortet die API mit `401 Unauthorized` und führt weder Lese- noch Schreiboperationen aus

### Requirement: Serverseitig bestimmter Nutzerkontext

Das System SHALL die maßgebliche Nutzer-ID für jede fachliche Operation ausschließlich aus der authentifizierten Sitzung ableiten. Eine in Request, lokalem Datensatz oder KI-Werkzeugargument gelieferte Nutzer-ID MUST den Nutzerkontext niemals wechseln oder erweitern.

#### Scenario: Manipulierte Nutzer-ID in einer Mutation

- **GIVEN** Nutzer A ist authentifiziert und kennt die Nutzer-ID von Nutzer B
- **WHEN** Nutzer A eine Mutation mit der Nutzer-ID von Nutzer B übermittelt
- **THEN** wird die Anfrage abgelehnt, keine Entität verändert und kein Datensatz Nutzer B zugeordnet

#### Scenario: Nutzergebundenes KI-Werkzeug

- **GIVEN** Nutzer A ist authentifiziert und der AI Coach ruft ein freigegebenes Werkzeug auf
- **WHEN** das Werkzeug Daten abfragt
- **THEN** begrenzt das Backend den Zugriff auf Nutzer A, ohne eine frei wählbare Nutzer-ID zu akzeptieren

### Requirement: Isolation fachlicher Daten

Das System MUST alle Listen-, Detail-, Schreib-, Synchronisations-, Analyse- und KI-Zugriffe auf die fachlichen Daten des authentifizierten Nutzers begrenzen.

#### Scenario: Nutzergebundene Liste

- **GIVEN** Nutzer A und Nutzer B besitzen jeweils fachliche Datensätze
- **WHEN** Nutzer A eine Liste dieser Datensätze abruft
- **THEN** enthält die Antwort ausschließlich Datensätze von Nutzer A

#### Scenario: Fremde Ressourcen-ID lesen

- **GIVEN** Nutzer A ist authentifiziert und verwendet die Ressourcen-ID eines Datensatzes von Nutzer B
- **WHEN** Nutzer A den Datensatz direkt abruft
- **THEN** antwortet die API mit `404 Not Found` und gibt weder Inhalt noch Eigentümer preis

#### Scenario: Fremde Ressource verändern

- **GIVEN** Nutzer A ist authentifiziert und verwendet die Ressourcen-ID eines Datensatzes von Nutzer B
- **WHEN** Nutzer A eine Änderung oder Löschung anfordert
- **THEN** antwortet die API mit `404 Not Found` und der Datensatz von Nutzer B bleibt unverändert

### Requirement: Lokale Trennung auf gemeinsam genutzten Geräten

Die Anwendung MUST lokale Fachdaten, ausstehende Änderungen und nutzerbezogene Caches nach Konto trennen und SHALL nach einer Abmeldung keine Daten des abgemeldeten Kontos in der UI zugänglich machen.

#### Scenario: Kontowechsel auf demselben Gerät

- **GIVEN** Nutzer A hat lokale Daten gespeichert, sich abgemeldet und Nutzer B meldet sich auf demselben Gerät an
- **WHEN** Nutzer B die Anwendung online oder offline verwendet
- **THEN** werden ausschließlich Daten und Caches von Nutzer B geöffnet und keine Daten von Nutzer A angezeigt oder synchronisiert

#### Scenario: Geschützte Ansicht nach Abmeldung

- **GIVEN** ein Nutzer hat sich abgemeldet
- **WHEN** eine zuvor geöffnete geschützte Ansicht erneut aufgerufen wird
- **THEN** fordert die Anwendung eine Anmeldung und zeigt keine zwischengespeicherten fachlichen Inhalte an

### Requirement: Begrenzte Betreiberfunktionen

Das System MUST Betreiberfunktionen auf Konten, Einladungen und Kontostatus begrenzen und SHALL keine Anwendungsansicht, API, Export- oder Impersonation-Funktion zum Lesen fremder Fitnessdaten anbieten.

#### Scenario: Betreiber verwaltet ein Konto

- **GIVEN** der Betreiber ist für die Kontoverwaltung authentifiziert
- **WHEN** er ein Konto einlädt, deaktiviert oder reaktiviert
- **THEN** kann er die notwendigen Identitätsdaten verwalten, ohne Fitnessdaten des Kontos zu erhalten

#### Scenario: Betreiber fordert fremde Fitnessdaten an

- **GIVEN** der Betreiber besitzt ein eigenes Nutzerkonto und technische Administrationsrechte außerhalb der Anwendung
- **WHEN** er über die Anwendung Fitnessdaten eines anderen Nutzers anfordert
- **THEN** gelten dieselben Isolationsregeln wie für jeden Nutzer und es werden keine fremden Fitnessdaten ausgegeben
