# Design

## Decisions

### D1 – Zustandsloser Dialog

Die App schickt bei jeder Anfrage Name, Typ, Notiz und alle bisherigen Rückfragen mit Antworten (höchstens zwei). Der Server speichert nichts. Nach zwei Rückfragen nutzt er ein Schema, das nur einen Vorschlag erlaubt, und lehnt eine weitere Frage als ungültige Antwort ab.

### D2 – Antwortschema

Striktes JSON-Schema über die OpenAI Responses API ohne Tools: `kind` (`question` | `suggestion`), `question`, `options` (bis zu vier), `primaryMuscles` (1–3) und `secondaryMuscles` (0–6) als Enum der 17 Muskel-Schlüssel, `explanation`. Der Server prüft zusätzlich mit `MuscleKeys.Validate`. Übungsdetails gelten im Prompt ausdrücklich als Daten, nicht als Anweisungen.

### D3 – Kontingent

`MuscleSuggestion:DailyRequestsPerUser` (Standard 40) und `MaximumConcurrentRequests` (Standard 2). Die gemeinsame Klasse `DailyRequestQuota` ersetzt den bisher eigenen Code der Mahlzeiten-Schätzung. Überschreitung → 429 `daily_budget_exhausted`.

### D4 – Oberfläche

Button „Mit KI ermitteln“ unter dem lokalen Vorschlag, nur im Bearbeitungsmodus, deaktiviert ohne Namen. Das Sheet zeigt Laden, Rückfrage (Optionen als Listenzeilen, Freitext, „Antworten“), Vorschlag (Körperkarte, Haupt- und Hilfsmuskeln, Begründung, „Übernehmen“) oder Fehler mit „Erneut versuchen“. Fehlertexte: Tageslimit, keine Verbindung, KI nicht erreichbar, unbrauchbare Antwort.
