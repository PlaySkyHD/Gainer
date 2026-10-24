## Purpose

Diese Capability verwaltet ausschließlich manuell erfasste, benannte und zeitlich begrenzbare Kalorien- und Makro-Zielphasen und visualisiert den Tagesfortschritt, ohne fehlende Daten als erreicht auszugeben.

## ADDED Requirements

### Requirement: Benannte und zeitlich wirksame Ernährungszielphasen verwalten

Die Anwendung MUST einem Nutzer erlauben, eine Zielphase mit stabiler ID, Name, manuell gewählter Kategorie `Cut`, `Maintenance`, `Bulk` oder `Benutzerdefiniert`, lokalem Startdatum, optionalem inklusivem Enddatum, positiven täglichen Kilokalorien und positiven Makrozielen anzulegen. Die Kategorie MUST ausschließlich der Organisation dienen und DARF keine Zielwerte vorbelegen oder empfehlen. Das Enddatum MUSS, falls gesetzt, am oder nach dem Startdatum liegen. Zielphasen desselben Nutzers DÜRFEN sich nicht überschneiden; für einen lokalen Kalendertag darf höchstens eine Phase wirksam sein. Änderungen DÜRFEN die für vergangene Ernährungstage wirksamen Zielwerte nicht rückwirkend verändern.

#### Scenario: Erste Cut-Phase anlegen

- **GIVEN** ein Nutzer besitzt noch kein Ernährungsziel
- **WHEN** er eine manuelle Phase „Sommer Cut“ der Kategorie `Cut` mit Start heute, Ende in zwölf Wochen sowie gültigen Kalorien- und Makrozielen bestätigt
- **THEN** verwendet die Tagesansicht innerhalb dieses Zeitraums diese Phase und zeigt außerhalb des Zeitraums kein daraus abgeleitetes Ziel

#### Scenario: Folgephase nach offenem Ziel planen

- **GIVEN** eine laufende Zielphase besitzt kein Enddatum
- **WHEN** der Nutzer eine neue Phase ab einem zukünftigen Datum plant
- **THEN** MUSS die Anwendung vor dem Speichern ausdrücklich anbieten, die laufende Phase am Vortag zu beenden, und beide Änderungen atomar speichern oder vollständig verwerfen

#### Scenario: Überlappende Zielphase ablehnen

- **GIVEN** für einen Teil des gewählten Zeitraums existiert bereits eine Zielphase
- **WHEN** der Nutzer eine weitere Phase ohne bestätigte Anpassung des bestehenden Zeitraums speichern möchte
- **THEN** lehnt die Anwendung die Änderung mit einer verständlichen Zeitraum-Fehlermeldung ab und erhält den letzten gültigen Stand

#### Scenario: Vergangene Phase bleibt stabil

- **GIVEN** eine Cut-Phase ist beendet und galt für bereits erfasste Ernährungstage
- **WHEN** der Nutzer eine neue Maintenance-Phase anlegt oder eine zukünftige Phase bearbeitet
- **THEN** bleiben Name, Kategorie, Zielwerte und Gültigkeit der beendeten Phase sowie ihre Tageszuordnung unverändert

#### Scenario: Ungültige Zielphase

- **GIVEN** mindestens ein Zielwert ist null, negativ oder nicht endlich oder das Enddatum liegt vor dem Startdatum
- **WHEN** der Nutzer die Phase speichern möchte
- **THEN** lehnt die Anwendung sie mit feldbezogener Fehlermeldung ab und erhält den letzten gültigen Stand

### Requirement: Transparente Makro-Energiebilanz

Die Anwendung MUST für jede Zielphase eine manuell gewählte Eingabeart `Gramm` oder `Prozent` unterstützen und beide Darstellungen vor dem Speichern nachvollziehbar anzeigen. Im Gramm-Modus MUST sie die Makroenergie deterministisch mit 4 kcal pro Gramm Protein, 4 kcal pro Gramm Kohlenhydrate und 9 kcal pro Gramm Fett berechnen; weicht diese Summe um mehr als 10 Prozent vom Kalorienziel ab, MUSS sie vor dem Speichern warnen und eine ausdrückliche Bestätigung verlangen. Im Prozent-Modus MÜSSEN die positiven Anteile für Protein, Kohlenhydrate und Fett zusammen exakt 100 Prozent ergeben; die Anwendung MUSS daraus die Grammziele deterministisch mit 4/4/9 und einer dokumentierten Dezimalrundung ableiten. Sie DARF keine Verteilung vorschlagen oder Eingaben still verändern.

#### Scenario: Makros passen zum Kalorienziel

- **GIVEN** die Makroziele ergeben nach der 4/4/9-Regel annähernd das Kalorienziel
- **WHEN** der Nutzer das Profil prüft
- **THEN** zeigt die Anwendung die berechnete Makroenergie ohne Inkonsistenzwarnung an

#### Scenario: Deutliche Abweichung bestätigen

- **GIVEN** die Makroenergie weicht um mehr als 10 Prozent vom Kalorienziel ab
- **WHEN** der Nutzer das Profil erstmals speichern möchte
- **THEN** erklärt die Anwendung die Abweichung und speichert erst nach einer separaten ausdrücklichen Bestätigung

#### Scenario: Prozentverteilung in Gramm umrechnen

- **GIVEN** eine manuell gewählte Verteilung aus 30 Prozent Protein, 40 Prozent Kohlenhydraten und 30 Prozent Fett bei 2.000 kcal
- **WHEN** der Nutzer die Zielphase prüft
- **THEN** zeigt die Anwendung die deterministisch abgeleiteten Grammziele und speichert Eingabeart, Prozentwerte und abgeleitete Grammwerte als denselben Phasen-Snapshot

#### Scenario: Prozentwerte ergeben nicht 100 Prozent

- **GIVEN** die drei eingegebenen Makroanteile ergeben zusammen 95 Prozent
- **WHEN** der Nutzer die Zielphase speichern möchte
- **THEN** lehnt die Anwendung das Speichern mit einer feldbezogenen Verteilungsfehlermeldung ab und verändert keine vorhandene Phase

### Requirement: Zugänglicher Tagesfortschritt

Die Ernährungstagesansicht MUST Name und Kategorie der für den geöffneten lokalen Tag wirksamen Zielphase anzeigen. Für Kilokalorien, Protein, Kohlenhydrate und Fett MUST sie jeweils aufgenommenen Wert, gültigen Zielwert, verbleibenden beziehungsweise überschrittenen Wert und einen visuellen Fortschritt darstellen. Der Zustand MUST zusätzlich textuell und für Screenreader verständlich sein; Farbe allein DARF ihn nicht vermitteln. Ein Überschreiten MUST sichtbar bleiben und DARF den Zahlenwert nicht bei 100 Prozent abschneiden.

#### Scenario: Ziel teilweise erreicht

- **GIVEN** ein Tag enthält 1.500 von 2.500 kcal und 120 von 180 g Protein
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** zeigt sie für beide Werte den proportionalen Fortschritt und die jeweils verbleibende Menge numerisch sowie zugänglich an

#### Scenario: Fettziel überschritten

- **GIVEN** ein Tag enthält 90 g Fett bei einem Ziel von 70 g
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** kennzeichnet sie 20 g Überschreitung textuell und visuell, ohne die Aufnahme als exakt 70 g auszugeben

#### Scenario: Einträge besitzen fehlende Makros

- **GIVEN** mindestens ein Ernährungseintrag des Tages hat keine verwertbare Proteinangabe
- **WHEN** der Proteinfortschritt berechnet wird
- **THEN** kennzeichnet die Anwendung die Proteinsumme als unvollständig und stellt sie nicht als verlässlich verbleibenden Zielwert dar

#### Scenario: Für den Tag gilt kein Ziel

- **GIVEN** für den geöffneten Tag existiert keine wirksame Zielversion
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** zeigt sie die aufgenommenen Nährwerte ohne irreführende Progressbars und bietet das Konfigurieren eines Zielprofils an

### Requirement: Offline-Verfügbarkeit und idempotenter Sync

Die PWA MUST lokal vorhandene Zielphasen einschließlich Name, Kategorie, Zeitraum, Eingabeart und Makroverteilung sowie den daraus bestimmten Tagesfortschritt offline anzeigen. Das Anlegen oder Ändern zukünftiger Phasen und das bestätigte Beenden einer offenen Phase MUST als vollständiger, überlappungsfreier Schedule atomar mit stabiler Operations-ID in kontogetrennter IndexedDB und Outbox gespeichert und idempotent synchronisiert werden. Eine abgelaufene Sitzung oder ein Konflikt MUST den lokalen Stand erhalten und sichtbar machen.

#### Scenario: Zielphase offline planen

- **GIVEN** das Gerät ist offline und das aktuelle Zielprofil ist lokal vorhanden
- **WHEN** der Nutzer eine neue Zielphase für einen zukünftigen Zeitraum speichert
- **THEN** ist sie lokal sofort sichtbar, übersteht einen Reload und wird nach Wiederherstellung der Verbindung genau einmal synchronisiert

#### Scenario: Bestätigung geht verloren

- **GIVEN** der Server hat eine Zielversion gespeichert, aber die Bestätigung erreicht das Gerät nicht
- **WHEN** dieselbe Operations-ID erneut gesendet wird
- **THEN** bestätigt der Server dieselbe Zielversion und erzeugt keine doppelte Gültigkeitsversion

#### Scenario: Sitzung läuft vor dem Sync ab

- **GIVEN** eine Zieländerung wartet in der Outbox und die Sitzung läuft ab
- **WHEN** die PWA synchronisieren möchte
- **THEN** bleibt die Änderung dem ursprünglichen Konto zugeordnet und wird erst nach dessen erneuter Anmeldung übertragen

### Requirement: Nutzerisolation und keine automatischen Zielwerte

Zielphasen, Fortschrittswerte und Sync-Changes MUST ausschließlich aus Daten des authentifizierten Nutzers entstehen. Name, Kategorie, Zeitraum, Kalorien und Makroverteilung MÜSSEN als manuelle Nutzereingabe gekennzeichnet sein. Weder Request-Metadaten noch AI-Ausgaben DÜRFEN eine Nutzer-ID bestimmen, eine Kategorie auswählen, Zielwerte vorschlagen oder eine mutierende Zieloperation auslösen.

#### Scenario: Fremdes Zielprofil adressieren

- **GIVEN** Nutzer A kennt die Zielprofil-ID von Nutzer B
- **WHEN** Nutzer A sie liest oder verändert
- **THEN** behandelt das Backend sie wie eine nicht vorhandene Ressource und offenbart weder Zielwerte noch Begründungen

#### Scenario: Coach nennt abweichende Zielwerte

- **GIVEN** eine AI-Antwort enthält numerische Zielwerte oder eine Aufforderung zum Speichern
- **WHEN** das Backend die Antwort verarbeitet
- **THEN** werden weder Zielprofil noch Ernährungstag verändert und die Werte werden nicht als Zielvorschlag in die Anwendung übernommen
