# Mitwirken an Gainer

## Arbeitsweise

Änderungen folgen den Requirements, dem Design und den Tasks des aktiven OpenSpec-Changes. Halte jeden Schritt klein, fachlich fokussiert und nachvollziehbar. Neue APIs, Abhängigkeiten oder Produktfunktionen dürfen nicht ohne passende Planung eingeführt werden.

## Definition of Done

Eine Aufgabe ist erst abgeschlossen, wenn:

- die beschriebenen Akzeptanzkriterien erfüllt sind,
- relevante Unit-, Integrations-, Architektur-, Contract- oder Widget-Tests ergänzt wurden,
- Nutzerisolation und Fehlerpfade bei betroffenen Datenzugriffen geprüft wurden,
- keine Secrets oder persönlichen Fitnessdaten in Quellcode, Logs oder Testartefakten stehen,
- Dokumentation und generierte Verträge bei Bedarf aktualisiert sind,
- **betroffene Builds und Tests nach jedem Task grün** sind,
- die Checkbox in der OpenSpec-Taskliste erst nach erfolgreicher Verifikation gesetzt wurde.

Für die vollständige lokale Prüfung:

```powershell
pwsh ./scripts/verify.ps1
```

## Commits

Implementierungscommits verwenden Conventional Commits:

```text
<type>(<optionaler-scope>): <kurze beschreibung>
```

Geeignete Typen sind:

- `feat`: neue fachliche Funktion,
- `fix`: Fehlerkorrektur,
- `test`: ausschließlich Tests,
- `docs`: ausschließlich Dokumentation,
- `build`: Buildsystem oder Abhängigkeiten,
- `ci`: CI-Konfiguration,
- `refactor`: Verhaltensneutrale Umstrukturierung,
- `chore`: sonstige Wartung.

Beispiele:

```text
feat(sync): add idempotent mutation receipt
test(access): cover cross-user workout lookup
build(mobile): pin pigeon dependency
```

Ein Commit soll genau einen verständlichen Zweck haben. Breaking Changes müssen im Commit-Body mit `BREAKING CHANGE:` erläutert werden; für den Greenfield-MVP sind sie nur nach Anpassung der OpenSpec-Artefakte zulässig.

## Pull Requests

Beschreibe das gelöste Problem, den betroffenen OpenSpec-Task, die Sicherheits- und Datenfolgen sowie die ausgeführten Prüfungen. Vermische keine unabhängigen Refactorings mit einer Fachänderung.
