## Context

Siehe [proposal.md](./proposal.md) für Motivation und Scope. Heute liegen optionale Tageskalorien und Makros direkt am `DailyCheckIn`; es gibt weder einzelne Lebensmittel noch Mahlzeiten. Die PWA schreibt Fachdaten zuerst in kontogetrennte IndexedDB-Aggregate und synchronisiert typisierte Mutationen über den bestehenden Revisionsfeed. Dashboard und Coach beziehen deterministische Kennzahlen aus dem Backend.

Open Food Facts ist eine externe Community-Datenquelle. Laut offizieller Dokumentation ist API v3.6 für neue Produktabrufe empfohlen; Produktabrufe sind auf 15 Requests pro Minute/IP und Suchen auf 10 Requests pro Minute/IP begrenzt. Search-as-you-type wird ausdrücklich abgeraten. Read-Requests benötigen keinen Account, aber einen identifizierenden `User-Agent`. Daten stehen unter ODbL, Bilder unter CC BY-SA und besitzen keine Vollständigkeits- oder Richtigkeitsgarantie.

## Goals / Non-Goals

**Goals:**

- Schnelle mobile Erfassung per Barcode, expliziter Suche, letzten Lebensmitteln oder manueller Eingabe
- Historisch stabile Einträge durch nutzereigene Nährwert-Snapshots
- Offline-fähige Mahlzeitenbearbeitung und verlusttoleranter bestehender Sync
- Eine eindeutige Quelle für Tageskalorien ohne Doppelzählung mit Legacy-Check-in-Werten
- Kontrollierter externer Traffic und ein Provider-Ausfall, der Tracking nicht blockiert

**Non-Goals:**

- Open-Food-Facts-Schreibzugriffe oder Benutzerbeiträge
- Eigener vollständiger Lebensmittelkatalog beziehungsweise regelmäßiger Gesamtdatenimport
- Rezepte, Gerichte mit Unterzutaten, Fotoerkennung oder Ernährungspläne
- Automatische Zielkalorien oder medizinische Interpretation
- Produktbilder im ersten Slice

## Decisions

### 1. Ein Ernährungstag ist ein nutzergebundenes Sync-Aggregat

Pro Nutzer und lokalem Kalendertag wird ein `NutritionDay`-Aggregat mit stabiler ID, `localDate`, Version und geordneten `NutritionEntry`-Kindern gespeichert. Jeder Eintrag enthält Mahlzeit, Position, Menge und vollständigen Nährwert-Snapshot. Ein Unique Constraint auf `(UserId, LocalDate)` verhindert doppelte Tagesaggregate; zusammengesetzte Fremdschlüssel mit `UserId` verhindern Cross-User-Kinder.

Ein Aggregat pro Eintrag wurde verworfen: Mahlzeitenverschiebung, Reihenfolge und Tagessummen würden dadurch mehrere konkurrierende Ressourcen und unnötig viele Sync-Konflikte erzeugen. Das Tagesaggregat bleibt klein genug für den privaten MVP und erlaubt eine atomare Tagesänderung.

### 2. Gespeicherte Werte sind Snapshots, keine Live-Referenzen

Übernommene Produkte werden nicht als globaler Fremdkatalog-FK modelliert. Der Eintrag speichert Produktname, optionale Marke, Barcode, Anbieter, Abrufzeitpunkt, Bezugsbasis, Nährwerte pro Bezugsbasis, gewählte Menge und berechnete Eintragswerte. Dadurch verändern externe Korrekturen niemals historische Tage. „Zuletzt verwendet“ wird aus eigenen Snapshots projiziert und benötigt keine zweite schreibbare Produktquelle.

Nur UUID, Barcode und fachlich notwendige Texte werden persistiert. Externe Rohantworten, Suchtexte und Bilder werden nicht in Fachentitäten gespeichert.

### 3. Deterministische Dezimalrechnung und Legacy-Priorität

Nährwerte verwenden `decimal`, kanonische Gramm und Kilokalorien. Eintragswerte werden aus `amountGrams / 100 * valuePer100Grams` berechnet und fachlich einheitlich gerundet; die exakte Rundung wird mit Golden Tests festgeschrieben. Fehlende Makros bleiben `null` und werden nicht als null Gramm interpretiert.

Für Dashboard, Trends und Coach gilt je Tag: Existiert mindestens ein Nutrition-Day-Eintrag, stammt die Tagesernährung ausschließlich aus dessen Summe. Andernfalls bleibt der bisherige Check-in-Wert ein als `legacy-check-in` gekennzeichneter Fallback. Eine Addition beider Quellen wurde verworfen, weil sie fast sicher doppelt zählen würde.

### 4. Open Food Facts bleibt hinter einem Backend-Port

Ein `IExternalFoodCatalog`-Port im Infrastrukturmodul kapselt zwei read-only Operationen: Barcode-Lookup und explizite Suche. Produktabrufe verwenden die aktuelle v3.6-Produktroute. Für Volltextsuche verwendet der erste Slice den von Open Food Facts noch unterstützten, dokumentierten Suchpfad hinter dem Adapter; dadurch kann später auf Search-a-licious gewechselt werden, ohne UI oder Fachverträge zu ändern.

Der benannte `HttpClient` setzt `User-Agent`, kurze Connect-/Gesamttimeouts, Antwortgrößenlimit und Resilience für vorübergehende Transportfehler. `404`, `429`, `503`, Timeout und ungültiges Schema werden auf stabile interne Codes abgebildet. Weder Query noch Barcode erscheinen in Logs, Metrics-Labels oder Traces.

Direkte Browserzugriffe wurden verworfen: Sie erschweren konsistente Normalisierung, Attribution, Limits und Fehlercodes und würden eine zusätzliche externe Origin in CSP/Privacy-Grenzen aufnehmen.

### 5. Zweistufiger Cache ohne personenbezogene Daten

Ein kleiner serverseitiger Memory-Cache dedupliziert gleichzeitige identische Requests und reduziert Providertraffic; normalisierte Barcodeprodukte erhalten eine längere, Suchresultate eine kurze TTL. Der Browser cached ausdrücklich ausgewählte Produkt-Snapshots nur als Teil eigener Einträge beziehungsweise „zuletzt verwendet“ in IndexedDB. Allgemeine Suchantworten werden nicht dauerhaft in der kontogebundenen Datenbank gespeichert.

Interne ASP.NET-Rate-Limits bleiben konservativ unter 15 Produkt- und 10 Suchrequests pro Minute je VPS-IP. Suchen erfordern Submit, mindestens zwei Zeichen, begrenzte Trefferzahl und UI-seitige Sperre bis zur Antwort. Bei mehreren Kollegen kann der gemeinsame Server-IP-Budgettopf zeitweise erschöpft sein; die UI bietet dann Barcode, letzte Lebensmittel und manuell erfassen an.

Redis oder ein separater Cacheprozess wurde für den Einzel-VPS verworfen. Ein Neustart darf den Cache verlieren, ohne Fachdaten zu gefährden.

### 6. Lokaler Store und bestehender Sync werden erweitert

Dexie erhält einen versionierten `nutritionDays`-Store. Speichern, Bearbeiten, Verschieben und Löschen aktualisieren Working Copy und unveränderliche Outbox-Mutation in einer Transaktion. Der Server ergänzt `saveNutritionDay` und `deleteNutritionDay` als typisierte Operationen mit Basisversion, vollständigem Snapshot, Tombstone und normaler Nutzerbindung. Pull wendet Tagessnapshot und Cursor atomar an.

Der vollständige Tages-Snapshot ist gegenüber feingranularen Entry-Mutationen absichtlich gewählt: Der MVP unterstützt ein aktives Schreibgerät und gewinnt damit einfachere Konflikte, Idempotenz und Offline-Recovery. Bei späterer kollaborativer Mehrgerätebearbeitung kann das Aggregat neu geschnitten werden.

### 7. Mobile UI mit bewusster externer Aktion

Die PWA erhält eine Tagesansicht mit Datumsnavigation, kompakter Tagesleiste und vier aufklappbaren Mahlzeiten. „Hinzufügen“ öffnet eine mobile Sheet-Interaktion mit `Zuletzt`, `Barcode`, `Suchen` und `Manuell`. Barcode verwendet nach Nutzeraktion `BarcodeDetector`, sofern verfügbar, und bietet stets manuelle Codeeingabe. Eine Bibliothek wird nur ergänzt, wenn der Browser-Fallback ohne sie nicht zuverlässig erreichbar ist.

Produktsuche beginnt ausschließlich über Submit. Treffer zeigen Text, Marke, Bezugsbasis und verfügbare Nährwerte, keine Bilder. Nach Auswahl bestätigt der Nutzer Menge und Mahlzeit, bevor eine lokale Mutation entsteht.

## Risks / Trade-offs

- [Open-Food-Facts-Daten sind falsch oder lückenhaft] → Quelle, Datenstand und fehlende Felder sichtbar machen; manuelle Korrektur vor Übernahme erlauben; keine medizinischen Aussagen.
- [Gemeinsames VPS-IP-Limit ist bei mehreren Nutzern schnell erreicht] → Submit statt Live-Suche, TTL-Cache, Request-Deduplizierung, konservatives internes Limit und lokale Alternativen.
- [Legacy-Check-in und Tagebuch könnten doppelt zählen] → Tagebuch hat pro Tag explizite Priorität; Quelle wird in Analytics ausgegeben; niemals summieren.
- [Ein großer Nutrition-Day-Snapshot erzeugt Konflikte] → MVP-Grenze „ein aktives Schreibgerät“ beibehalten, Konflikt sichtbar machen und Größenlimit pro Tag/Eintrag setzen.
- [ODbL-/Attributionspflicht wird übersehen] → Quellenhinweis in UI und Drittanbieterhinweisen; keine Bilder im ersten Slice.
- [BarcodeDetector fehlt insbesondere in einzelnen iOS-Versionen] → manuelle Barcodeeingabe und Produktsuche sind gleichwertige Fallbacks; Kamera niemals Voraussetzung.

## Migration Plan

1. Additive PostgreSQL-Migration für Ernährungstage und Einträge ausrollen; bestehende Check-ins bleiben unverändert.
2. API-/Sync-Verträge und Backend-Handler deployen, während alte Clients die neuen ResourceTypes ignorieren können; Sync-Protokollversion nur erhöhen, falls die bestehende Forward-Compatibility dies erfordert.
3. Open-Food-Facts-Adapter zunächst gegen Staging und Fake-Transport prüfen, dann Produktion mit identifizierendem `User-Agent` und Limits aktivieren.
4. PWA mit Dexie-Upgrade und neuer UI deployen; alte lokale Daten und Outbox bleiben erhalten.
5. Analytics auf Tagebuch-priorisierte Tagesquelle umstellen und Legacy-Fallback per Golden-/Regressionstests prüfen.
6. Rollback: UI und API auf vorherige Images zurücksetzen; additive Tabellen und neue Change-Batches bleiben erhalten und werden nicht destruktiv entfernt. Vor einem späteren Contract-Cleanup muss mindestens eine Clientversion Karenz bestehen.
