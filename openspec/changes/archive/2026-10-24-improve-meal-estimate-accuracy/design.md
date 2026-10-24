# Design

## D1 Anfrage

- **Werkzeug:** `tools: [{ type: "web_search", filters: { allowed_domains: [...] }, search_context_size: "low" }]`, `tool_choice` bleibt automatisch.
- **Ausgabe:** Die strukturierte Ausgabe (`json_schema`, strict) bleibt.
- **Auswertung:** Der Server liest weiterhin nur `message`/`output_text`. Elemente vom Typ `web_search_call` werden übergangen.
- **Ohne Suche:** Bei abgeschalteter Suche oder im Rückfall entfällt das Feld `tools` ganz, und der Prompt sagt „No tools or external data are available“.

## D2 Rückfall

Die Doku sagt nicht verlässlich, ob jedes Modell die Websuche zusammen mit strikter Schemaausgabe kann. Deshalb gilt:
- Wirft der Provider `OpenAiProviderException` mit Status 400, wiederholt der Schätzer die Anfrage einmal ohne Werkzeug und protokolliert eine Warnung.
- Andere Fehler (Zeitüberschreitung, 429, 5xx) behandelt er wie bisher.

## D3 Quellen

- `sourceUrl` ist im Schema Pflicht, darf aber `null` sein (höchstens 300 Zeichen).
- Der Server behält den Link nur, wenn er absolut ist, mit https beginnt und der Host eine erlaubte Domain oder deren Subdomain ist. So zeigt die App nie einen erfundenen oder fremden Link.

## D4 Zeiten

| Stelle | Vorher | Jetzt |
| --- | --- | --- |
| Server → OpenAI | 30 s | 75 s |
| App → Server (nur Schätzung) | 30 s | 90 s |
| Ausgabelimit | 1200 Token | 2000 Token |

Die App wartet länger als der Server. So kommt eine Zeitüberschreitung als verständliche Fehlermeldung (`provider_timeout`) an und nicht als Netzwerkfehler.
