## Why

Das bestehende Ernährungstagebuch reduziert den Aufwand durch Produktsuche und zuletzt verwendete Lebensmittel, bleibt bei gemischten Mahlzeiten und wiederkehrendem Meal Prep aber kleinteilig. Freitext- oder Fotoentwürfe, eine eigenständig pflegbare Gerichtebibliothek und verständliche, zeitlich begrenzbare Zielphasen sollen die Erfassung und Planung beschleunigen, ohne AI-Schätzungen ungeprüft als Fakten zu speichern oder vergangene Ernährungstage rückwirkend zu verändern.

## What Changes

- Ergänzt eine bewusst ausgelöste OpenAI-Schätzung aus Freitext und optional genau einem Foto. Die AI liefert ausschließlich einen strukturierten, als Schätzung gekennzeichneten Entwurf aus einzelnen Komponenten; vor dem Speichern muss der Nutzer Namen, Mengen, Kilokalorien und Makros prüfen und bestätigen.
- Informiert vor einem Foto-Upload über die Übermittlung an OpenAI, entfernt client- beziehungsweise serverseitig unnötige Metadaten, begrenzt Typ und Größe und speichert das Originalfoto standardmäßig weder in PostgreSQL noch in Blob Storage. Requests verwenden `store=false`; Prompt-, Bild- und Antwortinhalte dürfen nicht in normalen Logs, Traces oder Metrics erscheinen.
- Ergänzt nutzergebundene, offline verfügbare Gerichte mit Name, Standardportion und geordneten Komponenten. Eine eigenständige Gerichteansicht erlaubt Anlegen, Bearbeiten, Duplizieren und Archivieren unabhängig davon, ob gerade ein Ernährungseintrag hinzugefügt wird. Komponenten werden über denselben wiederverwendbaren Lebensmittel-Hinzufügen-Dialog wie bei Frühstück, Mittagessen, Abendessen und Snacks erfasst; `Zuletzt`, Open-Food-Facts-Suche, Barcode, manuelle Eingabe und AI-Schätzung stehen abhängig von Netzwerk und Gerät gleichwertig zur Verfügung.
- Fügt ein Gericht mit wählbarem Portionsfaktor als Deep Copy hinzu: Jede Komponente wird als selbständiger Ernährungseintrag in Frühstück, Mittagessen, Abendessen oder Snacks kopiert. Änderungen am Gericht wirken nicht auf eingefügte oder historische Einträge zurück; Änderungen am Ernährungstag verändern das Gericht nicht.
- Ergänzt ausschließlich manuell erfasste, benannte Zielphasen wie „Cut“, „Maintenance“, „Bulk“ oder „Benutzerdefiniert“. Jede Phase besitzt einen Beginn, ein optionales Ende, ein Kalorienziel und eine Makroverteilung, die der Nutzer wahlweise in Gramm oder Prozent eingibt. Weder OpenAI noch eine serverseitige Regel erzeugt, empfiehlt oder verändert numerische Zielwerte im MVP.
- Zeigt Tagesfortschritt und die für den Tag aktive Zielphase für Kilokalorien, Protein, Kohlenhydrate und Fett mit zugänglichen Progressbars, Zahlenwerten und Zuständen für verbleibend, erreicht und überschritten an. Zielphasen dürfen sich nicht überschneiden und verändern die Zielreferenz vergangener Tage nicht rückwirkend.
- Integriert Gerichte, bestätigte Schätzentwürfe und Zielkonfigurationen in Nutzerisolation, IndexedDB, Outbox, idempotenten Sync, Konfliktbehandlung und die bestehende Ernährungstagesprojektion.

### Non-Goals

- Automatisches Speichern oder stilles Übernehmen einer AI-Schätzung ohne Nutzerprüfung
- Medizinische Ernährungsberatung, Diagnose, Therapie oder garantierte Genauigkeit von Portions- und Nährwertschätzungen
- Automatische oder vorgeschlagene Kalorien- und Makroziele durch ein Sprachmodell oder eine Regel-Engine
- Automatische Auswahl von „Cut“, „Maintenance“ oder „Bulk“ aus Körper-, Gewichts- oder Trainingsdaten
- Langfristige Speicherung einer Foto-Bibliothek, Bilderkennung im Hintergrund oder Analyse ohne ausdrückliche Nutzeraktion
- Öffentliche Rezepte, Teilen zwischen Nutzern, Einkaufslisten, Wochenpläne oder automatische Meal-Prep-Planung
- Ersetzen von Open Food Facts oder manueller Erfassung; beide bleiben gleichwertige Alternativen

### Security and Privacy

- Freitext und ausgewählte Fotos werden nur nach ausdrücklicher Nutzeraktion serverseitig an OpenAI übertragen. Die UI muss Zweck, Drittanbieter und den Schätzcharakter vor dem ersten Upload verständlich anzeigen.
- Der OpenAI API-Key bleibt im Backend. Requests erhalten keine frei wählbare `UserId`, keinen SQL-Zugriff und keine anderen Ernährungstage, als für den konkreten Entwurf erforderlich sind.
- Fotos werden vor der Weitergabe auf erlaubte Bildformate, Abmessungen und Dateigröße geprüft und ohne nicht benötigte Metadaten verarbeitet. Temporäre Bytes werden nach Abschluss oder Fehler verworfen.
- Gerichte, Zielprofile und daraus erzeugte Einträge bleiben strikt an die authentifizierte Nutzer-ID gebunden; Cross-User-Zugriffe und manipulierte Nutzer-IDs werden serverseitig abgelehnt.

### Breaking Changes

Keine. Bestehende Ernährungstage und Clients bleiben lesbar; neue Ressourcen und optionale Felder werden additiv eingeführt. Bereits gespeicherte Zielversionen werden als benutzerdefinierte, manuell in Gramm erfasste Phase ohne Enddatum weitergeführt. Ältere Clients ignorieren Gerichte, Zielphasen und AI-Entwürfe, dürfen aber weiterhin normale Ernährungseinträge synchronisieren.

## Capabilities

### New Capabilities

- `ai-meal-estimation`: Nutzerinitiierte, datensparsame Freitext- und Fotoanalyse über OpenAI mit strukturiertem, editierbarem Entwurf, Unsicherheitskennzeichnung und verpflichtender Bestätigung.
- `reusable-meals`: Nutzergebundene, offline-first Gerichte aus geordneten Komponenten mit eigenständiger Gerichtebibliothek und einem wiederverwendbaren Lebensmittel-Hinzufügen-Dialog, die mit Portionsskalierung als einzelne Deep-Copy-Ernährungseinträge übernommen werden.
- `nutrition-targets`: Manuell erfasste, benannte und zeitlich begrenzbare Ernährungszielphasen mit Gramm-/Prozent-Makroverteilung und zugänglicher Tagesfortschrittsanzeige.

### Modified Capabilities

Keine bereits synchronisierte Basisspezifikation wird geändert. Die Integration mit dem noch aktiven Change `add-meal-calorie-tracking` wird in den neuen Capability-Verträgen ausdrücklich beschrieben.

## Impact

- Neue PostgreSQL-Entitäten und EF-Migrationen für Gerichte, Komponenten und zeitlich wirksame Ernährungsziele sowie additive Phasenmetadaten und Gültigkeitsenden; bestätigte AI-Ergebnisse werden ausschließlich als bestehende Nutrition-Entry-Snapshots persistiert.
- Neue ASP.NET-Endpunkte und Anwendungsfälle für Schätzentwürfe, Gerichte und Zielverwaltung sowie Erweiterungen des typisierten Sync- und Change-Feed-Vertrags.
- Neuer gekapselter OpenAI-Responses-Adapter für Text- und Bildinput mit Structured Outputs, `store=false`, Größen-, Timeout-, Rate- und Kostenlimits sowie stabilen Fehlercodes.
- Manuelle Zielerfassung bleibt strikt vom Coach und von der AI-Mahlzeitenschätzung getrennt; beide erhalten keine mutierende Zieloperation.
- Neue kontogetrennte IndexedDB-Stores, Outbox-Mutationen, eine eigenständige mobile Gerichteansicht und mobile Sheets für AI-Entwurf, Gerichtseditor, Deep-Copy-Übernahme und Zielphasenkonfiguration. Der Lebensmittel-Hinzufügen-Dialog und seine Erfassungswege werden als gemeinsame, zielneutrale UI- und Anwendungslogik für Ernährungstage und Gerichtsentwürfe wiederverwendet.
- Erweiterungen der Ernährungstagesansicht um vier Makro-Progressbars sowie Screenreadertexte, Dark/Light Mode, Safe Areas und reduzierte Bewegung.
- Zusätzliche Unit-, PostgreSQL-, API-, Sync-, Offline-, Browser-, Datenschutz- und Cross-User-Tests. Die Funktionen gehören zur privaten Kernjourney; soziale Rezeptfunktionen und weitergehende Ernährungsautomatisierung bleiben spätere Phasen.
