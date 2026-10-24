# ai-coach Specification

## Purpose
Der Coach beantwortet Fortschrittsfragen mit OpenAI auf Basis serverseitig berechneter eigener Kennzahlen, ohne dem Modell Datenzugriff oder schreibende Entscheidungen zu geben.

## Requirements

### Requirement: Online verfügbare Fortschrittsauswertung

Das System SHALL einem authentifizierten Nutzer erlauben, eine Fortschrittsfrage zu stellen und eine verständliche Antwort zu Ziel, Gewicht, Ernährung und Training zu erhalten. Die Funktion MUST eine aktive Netzverbindung erfordern und darf die lokale Tracking-Kernreise bei Nichtverfügbarkeit nicht blockieren.

#### Scenario: Fortschrittsfrage mit Daten

- **GIVEN** ein Nutzer besitzt ein aktives Ziel und ausreichende Fortschrittsdaten
- **WHEN** er fragt, wie sich sein Ziel seit Beginn entwickelt
- **THEN** fasst der Coach die relevanten deterministischen Kennzahlen mit ihren Zeiträumen zusammen und trennt Beobachtungen von unverbindlichen Vorschlägen

#### Scenario: Keine Netzwerkverbindung

- **GIVEN** der Nutzer ist offline
- **WHEN** er eine neue Coach-Antwort anfordert
- **THEN** zeigt die Anwendung die Online-Anforderung mit Retry-Möglichkeit und alle Trackingfunktionen bleiben nutzbar

### Requirement: Kontrollierte rein lesende Werkzeuge

Das System MUST dem Modell ausschließlich freigegebene, schema-validierte und rein lesende Werkzeuge für Ziel, Gewichtstrend, Ernährung, aktuelle Workouts, Übungsfortschritt und Zeitraumvergleiche anbieten. Es MUST direkten SQL-Zugriff, allgemeine Datenbankwerkzeuge und schreibende Funktionen ausschließen.

#### Scenario: Freigegebene Kennzahl abrufen

- **GIVEN** eine Nutzerfrage erfordert den 30-Tage-Gewichtstrend
- **WHEN** das Modell das passende Werkzeug mit einem gültigen Zeitraum aufruft
- **THEN** liefert das Backend ausschließlich die serverseitig berechnete Kennzahl des authentifizierten Nutzers

#### Scenario: Nicht freigegebene oder schreibende Aktion

- **GIVEN** ein Modelloutput fordert SQL, eine Datenänderung oder einen unbekannten Werkzeugnamen an
- **WHEN** das Backend den Werkzeugaufruf validiert
- **THEN** wird der Aufruf ohne Datenzugriff oder Mutation abgelehnt

### Requirement: Unveränderlicher Nutzerkontext

Das System MUST alle Coach- und Werkzeugaufrufe an die authentifizierte Sitzung binden. Das Modell darf keine frei wählbare Nutzer-ID erhalten, und eine vom Nutzer oder Modell genannte fremde ID MUST ignoriert oder abgelehnt werden.

#### Scenario: Frage nennt fremden Nutzer

- **GIVEN** Nutzer A ist authentifiziert und nennt in seiner Frage die Nutzer-ID von Nutzer B
- **WHEN** der Coach Datenwerkzeuge verwendet
- **THEN** können die Werkzeuge ausschließlich Daten von Nutzer A lesen und geben nichts über Nutzer B preis

#### Scenario: Manipuliertes Werkzeugargument

- **GIVEN** ein Werkzeugaufruf enthält trotz Schema eine Nutzer-ID
- **WHEN** das Backend den Aufruf prüft
- **THEN** wird die ID nicht als Berechtigungsquelle verwendet und der Aufruf bei einem Widerspruch abgelehnt

### Requirement: Datenminimierung und deaktivierte Anbieter-Speicherung

Das System SHALL nur die für die konkrete Antwort erforderlichen strukturierten Kennzahlen und Metadaten an OpenAI senden, den API-Schlüssel ausschließlich serverseitig verwenden und jede Anfrage mit deaktivierter Anbieter-Speicherung ausführen. Normale Anwendungslogs MUST frei von vollständigen Prompts, Antworten, Zugangsdaten und Fitnessrohwerten bleiben.

#### Scenario: Anfrage an OpenAI senden

- **GIVEN** das Backend hat die erforderlichen nutzergebundenen Kennzahlen ermittelt
- **WHEN** es eine Modellanfrage erstellt
- **THEN** enthält die Anfrage nur die erforderlichen Daten, setzt `store=false` und legt den API-Schlüssel nicht gegenüber dem Client offen

#### Scenario: Technisches Logging

- **GIVEN** eine Coach-Anfrage wird erfolgreich verarbeitet oder schlägt fehl
- **WHEN** technische Telemetrie geschrieben wird
- **THEN** enthält sie nur notwendige Betriebsmetadaten und keine vollständigen Frage-, Antwort- oder Fitnessinhalte

### Requirement: Evidenzgebundene und zurückhaltende Antwort

Das System MUST den Coach an die vom Backend gelieferten Daten binden, fehlende Datengrundlagen ausdrücklich nennen und erfundene Messwerte, Diagnosen oder als sicher dargestellte Kausalitäten verhindern. Ohne fachlich validierte Regelgrundlage SHALL der Coach keine konkrete numerische Kalorien- oder Trainingsänderung vorgeben oder automatisch ausführen.

#### Scenario: Unzureichende Daten

- **GIVEN** für eine belastbare Trendbewertung liegen zu wenige Check-ins oder Workouts vor
- **WHEN** der Nutzer eine Bewertung anfordert
- **THEN** benennt die Antwort die fehlende Datengrundlage und enthält keine erfundene Trend- oder Leistungszahl

#### Scenario: Frage nach Kalorienänderung

- **GIVEN** es existiert keine freigegebene deterministische Regel für eine konkrete Kalorienanpassung
- **WHEN** der Nutzer nach einer numerischen Änderung fragt
- **THEN** beschreibt der Coach den gemessenen Verlauf, kennzeichnet Grenzen und gibt weder eine konkrete Kalorienzahl als Anweisung aus noch verändert er einen Wert

#### Scenario: Medizinische Frage

- **GIVEN** eine Frage verlangt Diagnose oder Behandlung einer gesundheitlichen Beschwerde
- **WHEN** der Coach antwortet
- **THEN** stellt er keine Diagnose, verweist auf geeignete professionelle Hilfe und verändert keine Trackingdaten

### Requirement: Keine Auswirkungen bei Providerfehlern

Das System MUST Timeout, Rate Limit, ungültige Modellantwort und sonstige OpenAI-Fehler als retriable oder verständlich endgültige Coach-Fehler behandeln, ohne fachliche Daten oder ausstehende Trackingänderungen zu verlieren.

#### Scenario: Provider-Timeout

- **GIVEN** OpenAI antwortet nicht innerhalb des vorgesehenen Zeitlimits
- **WHEN** die Coach-Anfrage abbricht
- **THEN** erhält der Nutzer eine verständliche Retry-Möglichkeit und alle Trackingdaten bleiben unverändert

#### Scenario: Ungültiger Werkzeugaufruf

- **GIVEN** das Modell liefert wiederholt einen Aufruf, der das freigegebene Schema verletzt
- **WHEN** die serverseitige Validierung fehlschlägt
- **THEN** wird kein Werkzeug ausgeführt und die Anfrage endet kontrolliert ohne Offenlegung interner Fehlerdetails
