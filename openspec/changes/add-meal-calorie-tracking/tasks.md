## 1. Domänenmodell und Persistenz

- [x] 1.1 `NutritionDay`, `NutritionEntry`, Mahlzeitentypen und Nährwert-Snapshots mit stabilen IDs, Positionen, Basisversionen und fachlicher Validierung im Backend modellieren.
- [x] 1.2 Die deterministische Berechnung und Rundung von Kilokalorien und Makros aus Grammwerten implementieren und mit Golden-Unit-Tests für gültige, fehlende und ungültige Werte absichern.
- [x] 1.3 EF-Core-Konfigurationen und eine additive PostgreSQL-Migration für Ernährungstage und Einträge einschließlich `(UserId, LocalDate)`-Eindeutigkeit und nutzergebundener Fremdschlüssel erstellen.
- [x] 1.4 Repository- und Query-Ports für Ernährungstage, Tagessummen sowie zuletzt verwendete eigene Lebensmittel implementieren.
- [x] 1.5 PostgreSQL-Integrationstests für CRUD, Sortierung, Constraints, Versionierung und Isolation zwischen mindestens zwei Testnutzern ergänzen.

## 2. Open-Food-Facts-Integration

- [x] 2.1 Interne Verträge für Barcode-Lookup, explizite Produktsuche, normalisierte Nährwerte, Datenqualität und stabile Providerfehler definieren.
- [x] 2.2 Einen `IExternalFoodCatalog`-Adapter mit benanntem `HttpClient`, konfigurierbarem identifizierendem `User-Agent`, Timeouts und Antwortgrößenlimit implementieren.
- [x] 2.3 Den read-only Produktabruf über die Open-Food-Facts-API v3.6 sowie die ausdrücklich abgesendete, begrenzte Produktsuche hinter dem Adapter implementieren.
- [x] 2.4 Energieeinheiten, Bezugsbasis und optionale Makros deterministisch normalisieren; fehlende oder nichtnumerische Werte dürfen dabei nicht als null interpretiert werden.
- [x] 2.5 Barcode- und Suchergebnisse mit getrennten TTLs cachen, parallele identische Requests deduplizieren und interne Budgets unterhalb der Providerlimits erzwingen.
- [x] 2.6 `404`, `429`, `503`, Timeout, übergroße und fehlerhafte Antworten auf stabile API-Fehler abbilden, ohne Query, Barcode oder Antwort-Payload zu protokollieren.
- [x] 2.7 Adaptertests mit Fake-HTTP-Transport für vollständige und unvollständige Produkte, Kilojoule-Umrechnung, Cache, Limits, Stale-Fallback und Providerausfälle ergänzen.

## 3. HTTP-API und Verträge

- [x] 3.1 Authentifizierte Endpunkte für Barcode-Lookup und explizite Produktsuche mit Eingabe-, Treffer- und Seitengrenzen bereitstellen.
- [x] 3.2 Ernährungsabfragen für einen lokalen Kalendertag sowie zuletzt verwendete eigene Lebensmittel über nutzergebundene API-Verträge bereitstellen.
- [x] 3.3 OpenAPI-Dokumentation aktualisieren, TypeScript-Clientverträge regenerieren und sicherstellen, dass keine `UserId` aus Requests übernommen wird.
- [x] 3.4 API-Integrationstests für Authentifizierung, Eingabegrenzen, stabile Providerfehler und Cross-User-Zugriffe mit zwei Konten ergänzen.

## 4. Offline-Synchronisation

- [x] 4.1 Den Sync-Vertrag um versionierte `saveNutritionDay`- und `deleteNutritionDay`-Mutationen, vollständige Tagessnapshots und Tombstones erweitern.
- [x] 4.2 Serverseitige Sync-Handler mit authentifizierter Nutzerbindung, Basisversionsprüfung, Idempotenz über Mutation-IDs und Change-Feed-Publikation implementieren.
- [x] 4.3 Konflikt-, Retry-, verlorene-Bestätigung-, Tombstone- und Cross-User-Szenarien in PostgreSQL-basierten Sync-Integrationstests abdecken.
- [x] 4.4 Das Sync-Protokoll nur bei fehlender Forward-Compatibility versionieren und Kompatibilität mit Clients ohne Ernährungsressourcen testen.

## 5. Lokaler PWA-Datenspeicher

- [x] 5.1 Das Dexie-Schema additiv um kontogetrennte `nutritionDays` erweitern und ein Upgrade ohne Verlust bestehender Fachdaten oder Outbox-Einträge testen.
- [x] 5.2 Lokale Operationen zum Anlegen, Bearbeiten, Verschieben, Sortieren und Löschen von Einträgen mit atomarem Working-Copy- und Outbox-Schreibvorgang implementieren.
- [x] 5.3 Lokale Selektoren für vier Mahlzeiten, Mahlzeiten- und Tagessummen sowie zuletzt beziehungsweise häufig verwendete eigene Snapshots implementieren.
- [x] 5.4 Upload- und Pull-Mapping für Ernährungstage ergänzen und Sitzungsablauf, Benutzerwechsel, Reload sowie idempotente Wiederholung lokal testen.

## 6. Mobiles Ernährungstagebuch

- [x] 6.1 Eine mobile Tagesansicht mit Datumsnavigation, kompakter Tageszusammenfassung und den Bereichen Frühstück, Mittagessen, Abendessen und Snacks umsetzen.
- [x] 6.2 Ein mobiles Hinzufügen-Sheet mit den Wegen `Zuletzt`, `Barcode`, `Suchen` und `Manuell` sowie Menge- und Mahlzeitenbestätigung implementieren.
- [x] 6.3 Barcode-Erfassung nach ausdrücklicher Nutzeraktion mit `BarcodeDetector` umsetzen und bei fehlender Unterstützung oder verweigerter Kamera eine manuelle Codeeingabe anbieten.
- [x] 6.4 Produktsuche ausschließlich per Submit auslösen, laufende Doppelanfragen sperren und begrenzte Ergebnisse ohne Produktbilder darstellen.
- [x] 6.5 Manuelle Lebensmittel und Korrektur unvollständiger externer Nährwerte mit feldbezogener Validierung implementieren.
- [x] 6.6 Bearbeiten, Verschieben, Neuordnen und Löschen eigener Einträge einschließlich sichtbarer Sync- und Konfliktzustände umsetzen.
- [x] 6.7 Offline-, Leer-, Nicht-gefunden-, Kamera-, Rate-Limit- und Providerfehlerzustände mit lokalen Alternativen verständlich gestalten.
- [x] 6.8 Open Food Facts als Quelle mit Datenstand, Qualitätswarnung und ODbL-Attribution in Produktdetails und Drittanbieterhinweisen ergänzen.
- [x] 6.9 Light Mode, Dark Mode, Safe Areas, Tastaturbedienung, Screenreader-Beschriftungen und reduzierte Bewegung für alle neuen Oberflächen prüfen.
- [ ] 6.10 Eine gepflegte Browser-Decoder-Dependency für EAN-8, EAN-13, UPC-A und UPC-E anhand Browserabdeckung, Bundle-Größe und Lizenz auswählen, zentral pinnen und ausschließlich beim Öffnen des Scanners lazy laden.
- [ ] 6.11 Den Kamera-Scanner hinter einer gemeinsamen Abstraktion so erweitern, dass er die native `BarcodeDetector`-API als Fast Path und bei fehlender API automatisch den Decoder-Fallback über sicheren `getUserMedia`-Zugriff verwendet.
- [ ] 6.12 Bevorzugte Rückkamera, laufende Decode-Schleife, Deduplizierung wiederholter Treffer und Übergabe an denselben normalisierten Barcode-Lookup für beide Scannerpfade implementieren.
- [ ] 6.13 Alle Media-Tracks bei Erfolg, Abbruch, Fehler, Navigation, Sheet-Schließung und Komponenten-Unmount idempotent stoppen; manuelle Codeeingabe muss während jedes Fehlerzustands erreichbar bleiben.

## 7. Analytics und Coach

- [x] 7.1 Die deterministische Tagesernährungsprojektion so erweitern, dass Tagebucheinträge Vorrang haben und der manuelle Check-in-Wert nur ohne Einträge als `legacy-check-in` dient.
- [x] 7.2 Dashboard, Trends und Coach-Fakten auf die gemeinsame Tagesernährungsprojektion umstellen und die verwendete Quelle nachvollziehbar ausgeben.
- [x] 7.3 Regressionstests ergänzen, die Tagebuch- und Legacy-Werte niemals addieren, fehlende Makros erhalten und keine Ernährungsdaten anderer Nutzer einbeziehen.

## 8. Ende-zu-Ende-Prüfung und Betrieb

- [x] 8.1 Browser-Tests für manuelle Erfassung, externe Suche, Barcode-Fallback, Bearbeitung, Tageswechsel und Providerausfall ergänzen.
- [ ] 8.2 Offline-Erfassung, Reload, spätere Synchronisation und abgelaufene Sitzung im Browser sowie auf einem physischen iPhone prüfen und dokumentieren.
- [x] 8.3 Aspire-Konfiguration, Health Checks und Telemetrie für den externen Adapter ergänzen, ohne Suchtexte, Barcodes oder Ernährungsinhalte in Logs, Traces oder Metrics-Labels aufzunehmen.
- [x] 8.4 Konfiguration und Deployment-Dokumentation für Open-Food-Facts-Basis-URL, Kontaktadresse, Limits und Timeouts auf dem Linux-V-Server aktualisieren.
- [x] 8.5 Vollständigen Backend- und Frontend-Build, alle Unit-/Integrations-/Browser-Tests sowie eine Prüfung der Lizenz- und Datenschutzhinweise erfolgreich ausführen.
- [ ] 8.6 Automatisierte Frontend- und Browser-Tests mit deaktivierter nativer `BarcodeDetector`-API, EAN-/UPC-Testbildern, verweigerter Berechtigung, doppelten Frames und überprüftem Media-Track-Cleanup ergänzen.
- [ ] 8.7 Den produktiven HTTPS-Kamerascan auf einem PC-Browser ohne native API und einem physischen iPhone mit realen EAN-/UPC-Barcodes prüfen; erfolgreichen Lookup sowie manuelle Fallbacks dokumentieren.
- [ ] 8.8 Nach der Scanner-Erweiterung Typecheck, Lint, Produktionsbuild, Unit-/Browser-/PWA-Tests und den Lizenzcheck der neuen Dependency erfolgreich ausführen.
