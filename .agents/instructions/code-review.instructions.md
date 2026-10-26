---
description: 'Review-Methode für Gainer. Nur für Reviews, nicht beim Programmieren laden.'
applyTo: '**'
excludeAgent: ["coding-agent"]
---

# Code-Review

Antworte auf Deutsch. Prüfe zuerst den Diff, dann den betroffenen Code drumherum.

## Was ein Befund ist

- Fehler im Verhalten, Regressionen, Sicherheitslücken, Datenverlust.
- Verletzte Nutzerisolation oder eine `UserId` aus untrusted Input.
- Sync-Risiken: fehlende Basisversion, nicht idempotente Mutation, falsch gemeldeter Konflikt, Outbox ohne atomaren Fachstand.
- Vertragsbrüche zwischen API, App und `contracts/openapi`.
- Fehlende Tests für neues Verhalten oder einen Bugfix.
- Ein Fix in Repository oder ViewModel, dessen Aufrufer (Controller, Screen) eigene Logik hat und nicht mitgetestet ist. Ein Guard, der still zurückkehrt, muss dem Aufrufer das Ergebnis melden (z. B. `Future<bool>`); sonst behandelt die UI ihn als Erfolg.
- Verstöße gegen `backend.instructions.md`, `mobile.instructions.md`, `security.instructions.md` oder `docs/agent-lessons-learned.md`.

Kein Befund: Stil, den Formatter oder Analyzer schon prüfen; Refactoring-Ideen ohne konkretes Risiko; spekulative Optimierungen.

## Schweregrade

- **Kritisch:** Sicherheit, Datenverlust, falsches Verhalten, Vertragsbruch.
- **Wichtig:** plausibles Risiko für Fehler oder Betrieb, fehlender Test für kritisches Verhalten.
- **Hinweis:** klarer Nutzen, aber nicht nötig für einen sicheren Merge.

## Ausgabe

Befunde nach Schweregrad, je mit Datei und Zeile, konkretem Auslöser („bei Eingabe X passiert Y“) und Richtung für den Fix. Bestätigte Fehler von Vermutungen trennen. Ohne Befund das ausdrücklich sagen.

## OpenSpec

- Ein PR trägt genau einen Change, archiviert mit `openspec archive <change> -y`; unter `openspec/changes/` bleibt nichts außerhalb von `archive/`. Danach muss `openspec validate --specs --strict` grün sein (prüft u. a. die Länge von MODIFIED-Anforderungen; die CI tut das ebenfalls).
- Deltas stehen in der passenden fachlichen Spec. `MODIFIED` ersetzt den alten Text vollständig, `REMOVED` löscht ihn.
- Artefakte sind auf Deutsch. Jede Anforderung hat ein Given/When/Then-Szenario, jede Aufgabe einen prüfenden Test.
- Specs und Code müssen übereinstimmen; Zahlen in Beispielen nachrechnen.
