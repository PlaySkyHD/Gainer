## 1. Fachmodelle und deterministische Regeln

- [x] 1.1 `ReusableMeal`, geordnete Komponenten, Archivstatus und vollständige Nährwert-Snapshots mit stabilen IDs, Versionen und nutzergebundener Validierung im Core modellieren.
- [x] 1.2 `NutritionTargetSchedule` und zeitlich geordnete Zielversionen mit Eindeutigkeit, positivem Wertebereich und unveränderlichen bereits wirksamen Versionen modellieren.
- [x] 1.3 Gerichtskalierung und 4/4/9-Makroenergie als gemeinsame `decimal`-Regeln implementieren und mit Golden-Unit-Tests für Rundung, halbe/doppelte Portion sowie 10-Prozent-Warnschwelle absichern.
- [x] 1.4 Domänenverträge für einen kurzlebigen Meal-Estimate-Draft mit begrenzten Komponenten, nullable Makros, Unsicherheiten, Datenlücken und Provenienz definieren.
- [x] 1.5 Grenzwerte für Namen, Komponentenanzahl, Mengen, Nährwerte, Portionsfaktoren und Ziel-Schedule fachlich festlegen und mit Boundary-Tests dokumentieren.

## 2. PostgreSQL-Persistenz und Nutzerisolation

- [x] 2.1 EF-Core-Konfigurationen und additive Migration für Gerichte, Komponenten und Ziel-Schedule einschließlich `UserId`-gebundener Schlüssel und Eindeutigkeitsregeln erstellen.
- [x] 2.2 Repository- und Query-Ports für eigene aktive/archivierte Gerichte sowie den für einen lokalen Tag wirksamen Ziel-Schedule implementieren.
- [x] 2.3 PostgreSQL-Integrationstests für Gericht-CRUD, Komponentenreihenfolge, Archivierung, Zielversionen, Gültigkeitsauswahl und Konflikte ergänzen.
- [x] 2.4 Cross-User-Persistenztests mit mindestens zwei Nutzern ergänzen, die fremde Eltern-Kind-Verknüpfungen, IDs und Ziel-Schedules ohne Datenoffenlegung ablehnen.
- [x] 2.5 Migration auf einem bestehenden Nutrition-Datenbestand testen und nachweisen, dass vorhandene Ernährungstage und Entry-Snapshots unverändert bleiben.

## 3. Sync-Verträge und serverseitige Mutationen

- [x] 3.1 Den typisierten Sync-Vertrag additiv um `saveReusableMeal`, `archiveReusableMeal` und `saveNutritionTargetSchedule` mit vollständigen Snapshots, Basisversionen und Tombstones erweitern.
- [x] 3.2 Serverseitige Mutationshandler mit authentifizierter Nutzerbindung, fachlicher Revalidierung, Idempotenz über Mutation-ID und Change-Feed-Publikation implementieren.
- [x] 3.3 Sync-Integrationstests für Retry nach verlorener Bestätigung, Duplikatfreiheit, veraltete Basisversion, Archivierung und manipulierte UserId mit zwei Konten ergänzen.
- [x] 3.4 Forward-Compatibility mit älteren Clients prüfen, die neue Gerichts- und Ziel-ResourceTypes noch nicht kennen; die Protokollversion nur bei tatsächlicher Inkompatibilität erhöhen.
- [x] 3.5 OpenAPI-Verträge und TypeScript-Client für Gerichtsqueries, Zielqueries und neue Sync-Payloads regenerieren und Contract-Drift-Prüfungen aktualisieren.

## 4. OpenAI Meal Estimation und Bildschutz

- [x] 4.1 Einen separaten Meal-Estimation-Port mit Text-/Bildinput, strukturiertem Draft, stabilen Providerfehlern und konfigurierbaren Modell-, Token-, Timeout- und Budgetgrenzen definieren.
- [x] 4.2 Eine geeignete serverseitige Bilddecoder-/Re-Encoding-Dependency nach Lizenz-, Linux-Container- und Ressourcenprüfung auswählen, zentral pinnen und hinter `IMealImageSanitizer` kapseln.
- [x] 4.3 Bildsanitizer mit Byte-, Magic-Byte-, Format-, Pixel- und Abmessungsgrenzen sowie Re-Encoding ohne Metadaten implementieren; Original- und temporäre Bytes nach Abschluss verwerfen.
- [x] 4.4 Den vorhandenen OpenAI-Responses-Transport für einen multimodalen Request mit `store=false`, ohne Tools und mit strengem Structured-Output-Schema erweitern.
- [x] 4.5 Meal-Estimate-Antworten zusätzlich serverseitig auf Schema, Komponentenlimit, Textlängen, endliche Zahlen, fachliche Grenzen, nullable Makros und Unsicherheitsfelder validieren.
- [x] 4.6 Prompt und Requestaufbau so begrenzen, dass Bild und Freitext als untrusted evidence behandelt werden und keine darin enthaltene Anweisung Daten- oder Toolzugriff auslösen kann.
- [x] 4.7 Per-User-Rate-/Tagesbudget und globale Parallelitätsbegrenzung vor dem Providerrequest implementieren und stabile Fehler für Validierung, Budget, Timeout, Rate-Limit und Inhaltsablehnung abbilden.
- [x] 4.8 Fake-HTTP-Integrationstests für reine Textanalyse, Fotoanalyse, mehrere Komponenten, fehlende Makros, ungültiges Schema, Prompt Injection, Timeout und Providerfehler ergänzen.
- [x] 4.9 Bildtests für falschen MIME-Type, manipulierte Magic Bytes, übergroße Datei, Dekompressions-/Pixelgrenze, Metadatenentfernung und sichere Freigabe temporärer Ressourcen ergänzen.
- [x] 4.10 Telemetrietests sicherstellen lassen, dass Logs, Traces und Metrics weder Freitext, Bild/Base64, Komponenten, E-Mail noch Providerpayload enthalten und nur technische Status-/Tokeninformationen erfassen.

## 5. Meal-Estimate- und Ziel-HTTP-API

- [x] 5.1 Eine authentifizierte, requestgrößenbegrenzte Multipart-Route für Freitext und optional genau ein Foto mit explizitem Consent-Merkmal und personalisiertem `no-store` bereitstellen.
- [x] 5.2 Read-only Endpunkte für eigene Gerichte, Gerichtdetails und den für einen lokalen Tag wirksamen Ziel-Schedule mit stabilen Leerzuständen implementieren.
- [x] 5.3 API-Integrationstests für Authentifizierung, Consent, Requestlimits, Fehlercodes, keine Draft-Persistenz und Cross-User-Zugriffe mit zwei Konten ergänzen.
- [x] 5.4 OpenAPI und generierten TypeScript-Client für Estimate-Draft, manuelle Ziele, Vollständigkeit und Progressdaten aktualisieren und Kompatibilitätsprüfung ausführen.

## 6. Manuelle Zielversionen und Tagesprojektion

- [x] 6.1 Manuell erfasste oder geänderte Werte als neue effektive Zielversion behandeln, ohne Ernährungseinträge oder frühere Zielreferenzen zu verändern.
- [x] 6.2 Die Tagesernährungsprojektion um `consumed`, `target`, `remainingOrOver`, `ratio` und `isComplete` für kcal, Protein, Kohlenhydrate und Fett erweitern.
- [x] 6.3 Regressionstests für Zielauswahl nach lokalem Datum, Überschreitung, fehlende Makros, Tage ohne Ziel und unveränderte Legacy-/Nutrition-Day-Priorität ergänzen.

## 7. Lokale PWA-Persistenz und Offline-Sync

- [x] 7.1 Das Dexie-Schema additiv und kontogetrennt um `reusableMeals` und `nutritionTargetSchedules` erweitern und ein Upgrade ohne Verlust bestehender Nutrition Days oder Outbox-Einträge testen.
- [x] 7.2 Lokale Gerichtoperationen für Anlegen, Bearbeiten und Archivieren mit atomarem Working-Copy-/Outbox-Schreibvorgang und stabilen IDs implementieren.
- [x] 7.3 Lokale Ziel-Schedule-Operationen mit Gültigkeitsprüfung, neuer Version und atomarem Outbox-Schreibvorgang implementieren.
- [x] 7.4 Gerichtkomponenten mit Portionsfaktor deterministisch in neue Nutrition Entries expandieren und Expansion, Nutrition Day und dessen Outbox-Mutation in einer IndexedDB-Transaktion speichern.
- [x] 7.5 Lokale Tests nachweisen lassen, dass Templateänderungen kopierte Entries nicht verändern, Entryänderungen nicht auf das Gericht zurückwirken und ein Fehler keine Teilübernahme hinterlässt.
- [x] 7.6 Upload-/Pull-Mapping für Gerichte und Ziel-Schedule ergänzen und Retry, Konflikt, Reload, Benutzerwechsel sowie abgelaufene Sitzung testen.
- [x] 7.7 AI-Entwürfe ausschließlich als kurzlebigen UI-Zustand halten und bei Bestätigung neue Entries erzeugen; Verwerfen darf keine Fach- oder Sync-Daten hinterlassen.

## 8. Mobile Gerichte- und AI-Oberfläche

- [x] 8.1 Das bestehende Hinzufügen-Sheet um `Gerichte` und `AI schätzen` erweitern, ohne manuelle Eingabe, zuletzt verwendet, Barcode oder Open-Food-Facts-Suche zu verdrängen.
- [x] 8.2 Einen mobilen Gerichtseditor für Name, Standardportion, geordnete Komponenten, Nährwertsummen, Bearbeitung und Archivierung umsetzen.
- [x] 8.3 Eine Gerichtsvorschau mit Mahlzeit, Portionsfaktor und den resultierenden Einzelkomponenten implementieren und erst nach Bestätigung atomar hinzufügen.
- [x] 8.4 Einen Freitext-/Foto-Flow mit Kamera- oder Dateiauswahl, erstem Datenschutzhinweis, Größenfeedback, Uploadfortschritt und Abbruch implementieren.
- [x] 8.5 Einen editierbaren AI-Entwurf mit getrennten Komponenten, Unsicherheiten, fehlenden Makros, Entfernen/Ergänzen sowie Zieltag-/Mahlzeitenwahl umsetzen.
- [x] 8.6 Provider-, Budget-, Offline-, ungültiges-Bild-, Abbruch- und Retry-Zustände gestalten und stets auf manuelle Erfassung oder Gerichte zurückführen.
- [x] 8.7 Sicherstellen, dass lokale Speicherfehler keinen Erfolg anzeigen und der bearbeitete Draft beziehungsweise die Gerichtsvorschau für einen erneuten Versuch erhalten bleibt.

## 9. Zielkonfiguration und Progressbars

- [x] 9.1 Eine mobile Zielkonfiguration für kcal, Protein, Kohlenhydrate, Fett und Gültigkeitsbeginn mit feldbezogener Validierung implementieren.
- [x] 9.2 Die 4/4/9-Makroenergie anzeigen und bei mehr als zehn Prozent Abweichung einen separaten bestätigungspflichtigen Warnschritt umsetzen.
- [x] 9.3 Die Ernährungstagesansicht um zugängliche Progressbars für kcal und drei Makros mit aufgenommen, Ziel, verbleibend beziehungsweise überschritten erweitern.
- [x] 9.4 Fehlende Makrodaten, Tage ohne Ziel und Werte über 100 Prozent ohne irreführende Restwerte oder reine Farbcodierung darstellen.
- [x] 9.5 Light Mode, Dark Mode, Safe Areas, Tastatur, Screenreadertexte, Fokusführung und reduzierte Bewegung für alle neuen Sheets und Progressanzeigen prüfen.

## 10. Ende-zu-Ende-Prüfung und Betrieb

- [x] 10.1 Browser-Tests für Gericht anlegen, offline verwenden, als Deep Copy bearbeiten, Vorlage später ändern und historischen Tag unverändert anzeigen ergänzen.
- [x] 10.2 Browser-Tests für Freitextentwurf, simulierte Fotoanalyse, Korrektur vor Bestätigung, Verwerfen, Providerfehler und nicht persistierten Draft ergänzen.
- [x] 10.3 Browser-Tests für manuelle Ziele, Zielwechsel nach Datum, Überschreitung und unvollständige Makros ergänzen.
- [x] 10.4 Offline-Erfassung, Reload, späteren Sync, Konflikt und abgelaufene Sitzung im Browser sowie auf einem physischen iPhone für Gerichte und Ziele prüfen und dokumentieren. *Der Browser-Teil entfällt.*
- [x] 10.5 Aspire- und Linux-Compose-Konfiguration um Modell-, Bild-, Timeout-, Parallelitäts- und Budgetparameter mit sicheren Produktionsdefaults und Health-/Readiness-Prüfung erweitern.
- [x] 10.6 Einen opt-in OpenAI-Live-Eval mit einem unkritischen Testbild und Freitext für Schema, Latenz und Tokenlimit ergänzen; der normale Testlauf darf keinen echten API-Aufruf benötigen.
- [x] 10.7 Datenschutz- und Drittanbieterhinweise um Fotoübermittlung, Schätzcharakter, Retention-Hinweis und fehlende Fotoablage aktualisieren.
- [x] 10.8 Vollständigen Backend-/Frontend-Build, Unit-, PostgreSQL-, API-, Sync-, Offline-, Browser-, Architektur-, Lizenz- und OpenSpec-Testlauf erfolgreich ausführen.

## 11. Benannte Zielphasen und kompatible Persistenz

- [x] 11.1 Zielversionen im Core additiv um stabile Phasen-ID, Name, Kategorie, inklusives optionales Enddatum, Eingabeart und optionale Prozentwerte erweitern; Intervall-, Überlappungs- und 100-Prozent-Regeln sowie deterministische 4/4/9-Ableitung mit Unit-Tests absichern.
- [x] 11.2 Eine additive EF-Core-Migration erstellen, die bestehende Zielversionen ohne Datenverlust als `Custom`, `Grams`, ohne Enddatum und mit neutraler Bezeichnung weiterführt; Migration und Rollback-Kompatibilität auf bestehendem Nutrition-Datenbestand testen.
- [x] 11.3 Query-, OpenAPI- und typisierte Sync-Verträge um Phasenmetadaten erweitern und alte Payloads ohne neue Felder während der Übergangsphase deterministisch auf die Legacy-Defaults abbilden.
- [x] 11.4 Serverseitige Schedule-Mutation um atomare Überlappungsprüfung und das ausdrücklich bestätigte Beenden einer offenen Phase vor einer Folgephase erweitern; Idempotenz-, Konflikt- und Teilfehlerfreiheit testen.
- [x] 11.5 PostgreSQL- und API-Integrationstests für inklusive Grenzen, Lücken, Überschneidungen, offene Phasen, unveränderte beendete Phasen, Gramm-/Prozentmodus und manipulierte Cross-User-IDs mit mindestens zwei Nutzern ergänzen.
- [x] 11.6 Dexie-Snapshot, lokale Validierung, Outbox-Serialisierung und Pull-Mapping additiv um die Phasenfelder erweitern; bestehende lokale Grammziele, Pending-Mutationen, Reload, Retry und abgelaufene Sitzung ohne Datenverlust testen.

## 12. Eigenständige Gerichtebibliothek und Zielphasen-UI

- [x] 12.1 Im Ernährungsbereich eine eigenständige mobile Ansicht „Gerichte“ bereitstellen, die ohne geöffneten Ernährungstag erreichbar ist und aktive sowie optional archivierte eigene Gerichte aus demselben Offline-Store anzeigt.
- [x] 12.2 Den bestehenden Gerichtseditor in der Bibliothek für Anlegen, Bearbeiten, Duplizieren und Archivieren wiederverwenden; Duplikate müssen neue Gerichts- und Komponenten-IDs erhalten und vor dem Speichern bearbeitbar sein.
- [x] 12.3 Das Gerichte-Tab im Lebensmittel-Hinzufügen-Dialog auf Auswahl, Portionsvorschau und atomare Deep-Copy-Übernahme fokussieren und einen verständlichen Einstieg zur separaten Bibliothek anbieten.
- [x] 12.4 Eine Zielphasenübersicht und einen mobilen Editor für Name, manuelle Kategorie, Start-/Enddatum, Kalorien und wählbaren Gramm-/Prozentmodus mit Live-Darstellung beider Makroformen umsetzen.
- [x] 12.5 Überlappende Zeiträume feldbezogen ablehnen und beim Planen hinter einer offenen Phase einen ausdrücklichen Bestätigungsschritt zum atomaren Beenden am Vortag anzeigen; keine Kategorie darf Werte vorbelegen.
- [x] 12.6 Die Ernährungstagesansicht um Name, Kategorie und Zeitraum der wirksamen Phase ergänzen und bestehende Progressbars ausschließlich mit den kanonischen Grammzielen speisen.
- [x] 12.7 Gerichtebibliothek und Zielphasenverwaltung in Light/Dark Mode, Safe Areas, Tastaturbedienung, Fokusführung, Screenreadertext und reduzierter Bewegung prüfen.

## 13. Delta-Abnahme und Rollout

- [x] 13.1 Browser-Tests für direkten Bibliothekseinstieg, Gericht anlegen/duplizieren/archivieren, Auswahl im Ernährungstag und unveränderte frühere Deep Copies ergänzen.
- [x] 13.2 Browser-Tests für Cut-/Maintenance-/Bulk-/Custom-Phasen, Gramm- und Prozentmodus, exakt 100 Prozent, Intervallgrenzen, bestätigtes Beenden einer offenen Phase und stabile historische Tagesziele ergänzen.
- [x] 13.3 Gerichtebibliothek und Zielphasen offline im Browser sowie auf einem physischen iPhone mit Reload, späterem Sync, Konflikt, abgelaufener Sitzung und Kontowechsel prüfen und die bestehende iPhone-Abnahme aktualisieren. *Der Browser-Teil entfällt.*
- [x] 13.4 OpenAPI-Drift, EF-Migrationsstand, Backend-/Frontend-Build, Unit-, PostgreSQL-, API-, Sync-, Offline-, Browser-, Architektur- und Lizenztests vollständig ausführen und das additive Release mit Health-/Rollback-Prüfung deploybereit machen.

## 14. Wiederverwendbarer Lebensmitteldialog im Gerichtseditor

- [x] 14.1 Den bestehenden Lebensmittel-Hinzufügen-Dialog in eine gemeinsame zielneutrale Komponente mit neutralem `FoodComponentDraft` und schmalen Zieladaptern für Nutrition Day und Reusable Meal überführen, ohne die vorhandenen Tagesabläufe zu duplizieren oder zu regressieren.
- [x] 14.2 Den Gerichtseditor so anbinden, dass `Zuletzt`, Open-Food-Facts-Suche, Barcode-Erfassung, manuelle Eingabe und AI-Schätzung dieselben Dialog-, Draft-, Validierungs-, Online-/Offline- und Fehlerpfade wie Frühstück, Mittagessen, Abendessen und Snacks verwenden.
- [x] 14.3 Bestätigte Einzel- und Mehrkomponenten-Ergebnisse mit neuen stabilen IDs als bearbeitbare, entfernbare und sortierbare Zeilen in die lokale Gericht-Working-Copy übernehmen; vor dem Speichern des Gerichts dürfen weder Nutrition Day noch Fach- oder Sync-Daten entstehen.
- [x] 14.4 Atomaritäts- und Fehlerbehandlung für beide Zieladapter testen: Abbruch, Provider-/Suchfehler oder lokale Übernahmefehler müssen das Ziel unverändert lassen und dürfen keine Teilkomponenten oder versteckten Ernährungstage erzeugen.
- [x] 14.5 Unit- und Browser-Tests für alle Erfassungswege im Gerichtseditor, mehrere AI-Komponenten, Offline-Fallbacks, anschließendes Bearbeiten/Sortieren sowie unveränderte Deep Copies und historische Ernährungstage ergänzen.
- [x] 14.6 Frontend-Build und relevante Unit-, Offline- und Browserregressionen ausführen; die weiterhin offenen physischen iPhone-Abnahmen aus 10.4 und 13.3 um den gemeinsamen Dialog im Gerichtseditor erweitern. *Der Browser-Teil entfällt.*
