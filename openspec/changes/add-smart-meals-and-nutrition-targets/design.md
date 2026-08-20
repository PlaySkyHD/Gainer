## Context

Siehe [proposal.md](./proposal.md) für Motivation und Scope. Das bestehende Ernährungstagebuch speichert einen vollständigen `NutritionDay` mit eigenständigen `NutritionEntry`-Snapshots, synchronisiert ihn über IndexedDB und einen idempotenten Revisionsfeed und priorisiert seine Tageswerte gegenüber Legacy-Check-ins. Der vorhandene OpenAI-Responses-Adapter arbeitet serverseitig mit `store=false`, ohne gehostete Tools und mit begrenzter Ausgabe; der Coach darf strukturierte Daten nur lesen und formulieren.

Die neue Funktion berührt UI, lokale Persistenz, Sync, PostgreSQL, deterministische Analytics und den externen OpenAI-Aufruf. AI-Schätzungen sind inhärent ungenau und online-only, während Gerichte, Ziele und bestätigte Ernährungseinträge offline-first funktionieren müssen. Bilddaten sind deutlich sensibler und größer als die bisher an OpenAI gesendeten strukturierten Fakten.

## Goals / Non-Goals

**Goals:**

- AI-Ausgaben als kurzlebige, strikt validierte Entwürfe behandeln und erst nach Nutzerkorrektur in bestehende Nutrition-Entry-Snapshots überführen.
- Wiederverwendbare Gerichte als tiefe, historisch stabile Vorlagen modellieren, ohne Nutrition Days von veränderlichen Vorlagen abhängig zu machen.
- Benannte Zielphasen mit eindeutigem Zeitraum und manueller Gramm- oder Prozentverteilung zeitlich stabil, deterministisch auswertbar und offline verfügbar machen.
- Den bestehenden modularen Monolithen, OpenAI-Adapter, Sync-Mechanismus und Deploymentaufbau erweitern, ohne einen weiteren Dienst einzuführen.
- Bildübertragung, Providerkosten, Telemetrie und Nutzerisolation mit expliziten technischen Grenzen absichern.

**Non-Goals:**

- Serverseitige Speicherung oder spätere Wiederanzeige von Mahlzeitenfotos.
- Persistenz unbestätigter AI-Entwürfe über Reload oder Gerätewechsel hinweg.
- Ein allgemeines Rezept-, Sharing-, Einkaufslisten- oder Wochenplanungsmodul.
- Durch OpenAI berechnete Zielwerte oder AI-gesteuerte Mutationen.
- Automatisch berechnete oder empfohlene Kalorien- und Makroziele; Ziele werden im MVP ausschließlich manuell erfasst.
- Ein Anspruch, Lebensmittel, Portionsgrößen oder Nährwerte aus einem Foto zuverlässig oder medizinisch belastbar zu bestimmen.

## Decisions

### 1. Gerichte und Ziele werden eigene nutzergebundene Aggregate; AI-Entwürfe nicht

Ein `ReusableMeal` besitzt stabile ID, Version, Status, Name, Standardportion und geordnete `ReusableMealComponent`-Snapshots. Jede Komponente enthält die für eine spätere Übernahme notwendigen Nährwerte und optionale Quellenmetadaten, aber keine zwingende Live-Referenz auf Open Food Facts oder einen früheren Nutrition Entry. Zusammengesetzte Schlüssel mit `UserId` sichern Eltern und Kinder gegen Cross-User-Verknüpfungen. Duplizieren erzeugt clientseitig ein neues Aggregat mit neuer ID und neuen Komponenten-IDs; es entsteht keine fachliche Elternreferenz.

Pro Nutzer verwaltet ein kleines `NutritionTargetSchedule`-Aggregat geordnete, nicht überlappende Zielphasen. Jede Phase besitzt stabile ID, Namen, die rein beschreibende Kategorie `Cut`, `Maintenance`, `Bulk` oder `Custom`, `effectiveFrom`, optionales inklusives `effectiveUntil`, manuell eingegebene Kilokalorien, Eingabeart sowie Makroverteilung. Der vollständige Schedule-Snapshot vermeidet konkurrierende Einzelressourcen und stellt eindeutig fest, welche Phase für einen lokalen Tag gilt. Bereits beendete Phasen und ihre fachlichen Werte werden nicht in-place verändert. Wird vor einer neuen Phase eine offene laufende Phase beendet, werden deren bisherige Tageszuordnungen nicht verändert und Enddatum plus neue Phase in derselben Schedule-Mutation gespeichert.

Ein AI-Entwurf bleibt hingegen Request-/UI-Zustand. Das Backend validiert und liefert ihn zurück, persistiert ihn aber nicht. Erst die Bestätigung übergibt die gewählten Komponenten an das aktive lokale Speicherziel: entweder an die vorhandene Nutrition-Day-Operation oder an den noch ungespeicherten `ReusableMeal`-Entwurf. Eine Draft-Tabelle oder Blobablage wurde verworfen, weil sie Retention, Löschung, Nutzerisolation und Sync für Daten verkomplizieren würde, die ohne Bestätigung keinen fachlichen Wert besitzen.

### 2. Eine Gerichtübernahme expandiert vor dem Speichern in Nutrition Entries

Die PWA lädt die lokale Gerichtsvorlage, wendet einen positiven Dezimalfaktor auf Menge und Nährwerte jeder Komponente an und erzeugt neue Entry-UUIDs. Expansion, Ergänzung des Nutrition-Day-Working-Copy und Outbox-Mutation erfolgen in derselben IndexedDB-Transaktion. Das Backend erhält wie bisher den vollständigen Nutrition-Day-Snapshot und validiert alle skalierten Werte erneut.

Nutrition Entries speichern keinen Foreign Key auf das Gericht. Optionaler Snapshot-Text wie „aus Gericht Chicken Rice Bowl“ darf für Herkunft und UI mitkopiert werden, bestimmt aber keine fachliche Auflösung. Damit verändern Template-Updates weder frühere Tage noch Pending-Mutationen. Eine serverseitige „Gericht-ID anwenden“-Mutation wurde verworfen: Sie wäre offline nicht verfügbar und könnte bei Template-Änderungen zwischen Auswahl und Sync einen anderen Inhalt erzeugen.

Die Skalierung verwendet dieselben `decimal`- und Rundungsregeln wie Nutrition Entries. Die PWA zeigt die Vorschau; das Backend bleibt letzte Validierungsgrenze. Die vollständige Übernahme ist atomar, sodass kein halbes Gericht entsteht.

### 3. Gerichte und Ziel-Schedule nutzen den bestehenden typisierten Sync

Dexie erhält kontogetrennte Stores für `reusableMeals` und `nutritionTargetSchedules`. Working Copy und unveränderliche Outbox-Mutation werden atomar geschrieben. Neue Operationen `saveReusableMeal`, `archiveReusableMeal` und `saveNutritionTargetSchedule` verwenden Client-UUID, Mutation-ID, Basisversion und vollständigen Snapshot. Pull-Changes enthalten Snapshot oder Tombstone und werden zusammen mit dem Cursor angewendet.

Gerichte sind je Vorlage ein Aggregat; dadurch kollidieren Änderungen verschiedener Gerichte nicht. Das Ziel-Schedule bleibt ein Aggregat pro Nutzer, weil die Phasenliste klein ist und Intervall-, Lücken- und Überlappungsprüfung einschließlich des atomaren Beendens einer offenen Phase zentral erfolgen muss. Der bestehende MVP-Vertrag mit einem aktiv schreibenden Hauptgerät bleibt bestehen; Konflikte werden nicht automatisch zusammengeführt.

### 4. Die Mahlzeitenschätzung erweitert den vorhandenen OpenAI-Responses-Port

Ein eigener Anwendungsfall für Meal Estimation verwendet die vorhandene OpenAI-Infrastruktur, aber ein separates Options-, Prompt- und Response-Schema. Der Request akzeptiert begrenzten Freitext und optional ein bereinigtes Bild als multimodalen Input. Der Modellname bleibt konfigurierbar und muss Bildinput sowie Structured Outputs unterstützen. Die Responses-Anfrage setzt `store=false`, ein enges Ausgabe-Tokenlimit, keine Tools und ein JSON-Schema mit begrenzter Komponentenanzahl, Pflichtfeldern, nullable Makros und Unsicherheitsfeldern.

Die Backendvalidierung vertraut dem Schema nicht allein: Sie prüft Anzahl, Textlängen, endliche Dezimalwerte, fachliche Min-/Max-Grenzen und konsistente Einheiten. Ein vollständig ungültiger Entwurf wird verworfen; fehlende optionale Makros bleiben `null`. Der Systemprompt beschreibt Text und Bild als untrusted meal evidence und verbietet das Befolgen darin enthaltener Anweisungen. Da keine Tools bereitgestellt werden, kann eine Prompt Injection weder Daten lesen noch Aktionen ausführen.

Eine direkte Wiederverwendung des Coach-Outputs wurde verworfen. Coach-Antworten sind erzählerisch und faktenbasiert, während die Meal Estimation ein eigenes streng strukturiertes, unsicheres Erkennungsresultat benötigt. Beide dürfen denselben niedrigen HTTP-/Responses-Transport nutzen, erhalten aber getrennte Ports und Tests.

### 5. Bilder werden vor dem Providerrequest normalisiert und nur im Speicher gehalten

Die UI nimmt Kamera oder Dateiauswahl erst nach Nutzeraktion entgegen, prüft eine erste Größenbegrenzung und komprimiert große Bilder für schnelle mobile Uploads. Das Backend vertraut dieser Vorverarbeitung nicht: Es liest nur bis zu einem festen Requestlimit, prüft Magic Bytes statt nur Content-Type, dekodiert innerhalb begrenzter Pixelmaße und kodiert in ein erlaubtes Format ohne Metadaten neu. Nur diese normalisierten Bytes gehen an OpenAI; Original und normalisierte Kopie werden nach dem Request verworfen.

Die Bildnormalisierung liegt hinter einem kleinen `IMealImageSanitizer`-Port. Die konkrete Decoderbibliothek wird nur nach Lizenz-, CVE-, Speicher- und Linux-Containerprüfung aufgenommen und zentral gepinnt. Eine reine Client-Bereinigung wurde verworfen, weil manipulierte Clients sonst Originalmetadaten und übergroße Decoderlast senden könnten. Blob Storage wird nicht verwendet, weil weder Wiederaufnahme noch spätere Anzeige Teil des Fachvertrags ist.

ASP.NET begrenzt Requestgröße und Parallelität vor der AI-Ausführung. Pro Nutzer gelten kurze Rate- und Tageskostenbudgets; globale Parallelität schützt den einzelnen VPS. Logs enthalten nur Ergebnisstatus, Latenz, Modell, Tokenmenge und anonyme technische Fehlerklasse, niemals Freitext, Bild, Base64, Komponenten oder Nutzer-E-Mail.

### 6. Bestätigung verwendet das aktive lokale Speicherziel, kein AI-Tool

Der Client hält den validierten Entwurf im Sheet, erlaubt Korrektur und erzeugt bei Bestätigung neue Snapshots für das aktive lokale Speicherziel. Im Ernährungstagskontext sind dies Nutrition Entries für den ausgewählten lokalen Tag und Mahlzeitentyp. Im Gerichtseditor sind es `ReusableMealComponent`-Snapshots im noch ungespeicherten Gerichtsentwurf; erst das ausdrückliche Speichern des gesamten Gerichts schreibt Working Copy und Outbox atomar. Die AI besitzt keine Write-Function und die Schätzroute speichert keine Fachdaten. Damit durchläuft jede Persistenz exakt die lokalen Atomaritäts-, Outbox-, Basisversions- und Nutzerisolationsregeln ihres Zielaggregats.

Der Snapshot erhält eine Quellenart `ai-estimate-confirmed`, aber keinen Prompt, kein Foto und keine rohe Providerantwort. Optional werden Modell-/Schema-Version und Bestätigungszeitpunkt als technische Provenienz gespeichert, damit spätere Qualitätsauswertungen möglich sind, ohne Eingaben zu rekonstruieren. Eine direkte serverseitige Übernahme per AI-Response-ID wurde verworfen, weil sie Offline-First und die sichtbare Nutzerkorrektur schwächen würde.

### 7. Zielphasen und Makroverteilungen werden ausschließlich manuell erfasst

Der MVP besitzt weder `INutritionTargetPolicy` noch einen Zielvorschlagsendpunkt. Name, Kategorie, Zeitraum, Kalorien und Makroverteilung werden vom Nutzer eingegeben und als Herkunft `Manual` gespeichert. Die Kategorien sind Labels ohne fachliche Regelwerte. OpenAI Meal Estimation und der Coach erhalten keine Zielmutation und ihre Ausgaben werden niemals in Zielwerte oder eine Phasenauswahl umgewandelt.

Im Gramm-Modus werden die manuell eingegebenen Grammwerte kanonisch gespeichert. Sie dürfen von der 4/4/9-Makroenergie abweichen, weil Rundung und individuelle Planung das rechtfertigen können; eine Abweichung über zehn Prozent löst eine bestätigungspflichtige Warnung aus, aber keine stille Anpassung oder Empfehlung.

Im Prozent-Modus müssen die drei positiven Dezimalanteile nach normalisierter Präzision exakt 100 ergeben. Der Server leitet die kanonischen Grammziele aus Kalorien und Anteilen mit `protein = kcal × Anteil / 100 / 4`, `carbs = kcal × Anteil / 100 / 4` und `fat = kcal × Anteil / 100 / 9` ab und rundet mit derselben dokumentierten Dezimalregel wie andere Nutrition-Berechnungen. Eingabeart, ursprüngliche Prozentwerte und abgeleitete Grammwerte werden gemeinsam im unveränderlichen Phasen-Snapshot gespeichert. Damit können UI und spätere Clients die Nutzereingabe exakt erklären, während Tagesprogress stets Grammziele verwendet.

### 8. Tagesfortschritt ist eine deterministische Projektion mit Vollständigkeit

Die Tagesprojektion kombiniert die vorhandene Nutrition-Day-Summe mit der für `localDate` wirksamen Zielphase und liefert zusätzlich deren Name, Kategorie und Zeitraum. Für jeden Nährstoff liefert sie `consumed`, `target`, `remainingOrOver`, `ratio` und `isComplete`. Kilokalorien und Makros werden nicht vom Client oder Coach neu interpretiert. Enthält mindestens ein Entry für ein Makro `null`, ist dessen Summe unvollständig; die UI zeigt bekannte Aufnahme und Ziel, aber keinen scheinbar verlässlichen Restwert.

Die visuelle Progressbar darf für die Geometrie bei 100 Prozent enden, zeigt Überschreitung jedoch mit eigenem Zustand und dem echten Zahlenwert. ARIA-Text nennt aufgenommen, Ziel und Rest beziehungsweise Überschreitung. Ohne wirksames Ziel werden nur Aufnahmewerte und ein Setup-Einstieg angezeigt.

### 9. HTTP-Verträge bleiben klein und Writes laufen über Sync

Die API ergänzt eine online-only `POST /api/v1/nutrition/meal-estimates`-Route für Multipart-Text/Bild sowie read-only Queries für eigene Gerichte und Ziel-Schedule. Gericht- und manuelle Zielphasen-Writes laufen wie andere Offline-Ressourcen über typisierte Sync-Mutationen; die normalen Query-Endpunkte sind personalisiert und `no-store`. Der Ziel-Snapshot wird additiv um Phasenmetadaten, Enddatum, Eingabeart und optionale Prozentwerte erweitert. Einen Zielvorschlagsendpunkt gibt es im MVP nicht.

Alle Controller beziehen die Identität ausschließlich aus der Sitzung. Requestmodelle enthalten keine maßgebliche UserId. Stabile Fehlercodes unterscheiden Validierung, Consent erforderlich, nicht unterstützt, Budget erschöpft und Provider temporär nicht verfügbar. OpenAPI bleibt Vertragsquelle für den TypeScript-Client.

### 10. Gerichte erhalten eine eigenständige Bibliotheksansicht

Der Ernährungsbereich erhält neben dem Tagebuch eine eigenständige Ansicht „Gerichte“. Sie verwendet denselben lokalen `reusableMeals`-Store und dieselben Sync-Operationen wie die bisherige Gerichtefunktion im Hinzufügen-Sheet. Damit existiert keine zweite Datenquelle. Die Bibliothek zeigt aktive Gerichte, kann archivierte einblenden und öffnet den vollständigen Editor für Anlegen, Bearbeiten, Duplizieren und Archivieren.

Der Lebensmittel-Hinzufügen-Dialog bleibt auf die konkrete Tagesaktion fokussiert: aktives Gericht auswählen, Portionsfaktor und resultierende Komponenten prüfen, Deep Copy bestätigen. Ein Einstieg zur Bibliothek darf angeboten werden, aber komplexe Vorlagenpflege ist nicht mehr an einen geöffneten Ernährungstag gebunden. Eine zusätzliche globale Bottom-Navigation wurde verworfen, weil „Gerichte“ fachlich zum bestehenden Ernährungsbereich gehört und die mobile Hauptnavigation nicht weiter anwachsen soll.

### 11. Der Lebensmittel-Hinzufügen-Dialog ist zielneutral und wiederverwendbar

Der bestehende Dialog für Frühstück, Mittagessen, Abendessen und Snacks wird nicht als zweite Variante im Gerichtseditor nachgebaut. Eine gemeinsame Dialog- beziehungsweise Sheet-Komponente kapselt Navigation, Suche, Barcode, `Zuletzt`, manuelle Eingabe, AI-Schätzung, Draft-Bearbeitung, Validierung sowie Online-/Offline- und Fehlerzustände. Die Erfassungsadapter liefern ein neutrales `FoodComponentDraft` mit Snapshotwerten und optionaler Quellenprovenienz, kennen aber weder einen Nutrition Day noch ein `ReusableMeal`.

Der Aufrufer stellt einen expliziten Zieladapter bereit. `NutritionDayEntryTarget` übernimmt bestätigte Drafts atomar als Nutrition Entries in einen Tag und Mahlzeitentyp. `ReusableMealComponentTarget` übernimmt sie zunächst als geordnete Komponenten in die lokale Working Copy des Gerichtseditor; erst das Speichern des Gerichts erzeugt seine Outbox-Mutation. Dadurch bleiben Dialogdarstellung, Providerzugriffe und Validierung an einer Stelle, während Transaktionsgrenzen und Fachregeln beim jeweiligen Zielaggregat liegen. Der Gerichtseditor verwendet keinen temporären oder versteckten Nutrition Day.

Ein Dialoglauf darf mehrere bestätigte Komponenten liefern, insbesondere bei AI-Schätzungen. Nach der Übernahme kann der Gerichtseditor jede Zeile unabhängig bearbeiten, entfernen und umordnen. Abbruch oder Adapterfehler lassen das Ziel unverändert. Online-only Erfassungswege behalten dieselben Fallbacks wie im Ernährungstag; lokale Snapshots, `Zuletzt` und manuelle Erfassung bleiben offline nutzbar.

## Risks / Trade-offs

- [Fotos erlauben nur grobe Portionsschätzungen] → Entwurf deutlich kennzeichnen, Unsicherheit und Datenlücken anzeigen, Bearbeitung erzwingen und nie automatisch speichern.
- [Bilddecoder können Speicher- oder Sicherheitsprobleme verursachen] → harte Byte-/Pixel-/Parallelitätslimits, vollständiges serverseitiges Re-Encoding, gepinnte Dependency und gezielte Decoder-Fuzz-/Fehlertests.
- [OpenAI-Kosten oder Rate-Limits steigen] → per-user Tagesbudget, globale Parallelitätsgrenze, kurze Timeouts, kleines Bild, begrenztes Schema und manuelle Alternativen.
- [AI-Schätzung wird als medizinisch korrekt verstanden] → UI-Sprache „Schätzung“, keine Gesundheitsbewertung, keine automatische Zielverknüpfung und sichtbare Bestätigung jeder Komponente.
- [Deep Copies duplizieren Daten] → bewusst akzeptiert, weil Historienstabilität und unabhängige Tageskorrektur wichtiger sind als Speicherersparnis; Fotos und rohe Providerdaten werden nicht dupliziert.
- [Nutzer interpretiert manuelle Ziele als Empfehlung der App] → Zielkonfiguration eindeutig als eigene Eingabe kennzeichnen und keine vorgeschlagenen Standardwerte aus Profil- oder AI-Daten erzeugen.
- [Ziel-Schedule erzeugt Mehrgerätekonflikte] → vollständiger kleiner Snapshot, Basisversion und sichtbarer Konflikt; keine stille Zusammenführung im MVP.
- [Überlappende oder offene Phasen machen Tagesziele mehrdeutig] → inklusive Intervalle serverseitig validieren; eine offene Phase nur nach ausdrücklicher Bestätigung atomar vor einer Folgephase beenden.
- [Prozentwerte und gerundete Grammwerte driften auseinander] → Eingabewerte und deterministisch abgeleitete Werte gemeinsam speichern und serverseitig mit derselben Dezimalregel revalidieren.
- [Fehlende Makros verzerren Progressbars] → Vollständigkeitsflag je Makro und kein vermeintlich genauer Restwert bei lückenhaften Entries.
- [Ein gemeinsamer Dialog koppelt unterschiedliche Speicherziele] → Zielneutrale Drafts und schmale Zieladapter trennen Erfassung, Validierung und UI von den Transaktionsregeln für Nutrition Day und Reusable Meal.

## Migration Plan

1. Additive Tabellen für Gerichte, Komponenten und Ziel-Schedule ausrollen; vorhandene Nutrition Days bleiben unverändert. Bestehende Zielversionen werden additiv als `Custom`, Eingabeart `Grams`, ohne Enddatum und mit einer neutralen Bezeichnung migriert.
2. Sync-ResourceTypes, OpenAPI-Verträge und Queries hinter deaktivierten UI-Einstiegen deployen; alte Clients ignorieren die additiven Changes.
3. Bildsanitizer und Meal-Estimation-Adapter mit Fake-Transport, Größenlimits und einem kleinen opt-in Live-Eval prüfen. OpenAI-Modell und Budgets über Aspire-Parameter und Deployment-Environment konfigurieren.
4. Dexie-Schema additiv upgraden, Gerichte und Ziel-Schedule synchronisieren und anschließend die mobile UI aktivieren. Bestehende Outbox-Einträge dürfen nicht migriert oder verworfen werden.
5. Ziel-Schedule und Tagesprojektion additiv um Phasenname, Kategorie, Enddatum, Eingabeart und Prozentwerte erweitern. Alte Payloads ohne diese Felder werden während der Client-Übergangsphase mit den Migrationsdefaults interpretiert; neue Payloads werden vollständig validiert.
6. Eigenständige Gerichtebibliothek und Zielphasenverwaltung aktivieren; den gemeinsamen zielneutralen Lebensmittel-Hinzufügen-Dialog im Gerichtseditor anbinden und Cross-User-, Offline- und Browserregressionen vor dem Rollout ausführen. Coach-Ausgaben bleiben von Zielmutationen getrennt.
7. Rollback erfolgt über vorherige Images. Additive Spalten, Tabellen und unbekannte Change-Feed-Felder bleiben erhalten; ältere Clients können normale Ernährungstage und bestehende Grammziele weiter verwenden. Da keine Fotos oder Drafts persistiert werden, ist dafür keine Datenbereinigung nötig.
