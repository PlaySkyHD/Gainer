# Lessons Learned für Agents

Erkenntnisse aus der Umsetzung von Trainingssystem, App-Design, Health-Check-in, Timer und Sync (Oktober 2026). Jeder Agent, der in diesem Repo arbeitet oder Subagents steuert, liest diese Datei vor dem ersten Schritt.

## 1. Subagents und Worktrees

- **Worktrees starten auf `main`, nicht auf deinem Feature-Branch.** Ein Subagent mit `isolation: worktree` sieht deine neuen Bausteine und OpenSpec-Dateien nicht. Bei gestapelter Arbeit auf einem Feature-Branch ist der erste Schritt im Subagent-Prompt `git merge --no-edit <feature-branch>`; für ein Issue direkt von `main` stattdessen `git fetch origin` und danach `git switch -c <branch> origin/main`.
- **Shell in isolierten Worktrees.** Die Isolation hat verkettete Git-Startbefehle (`git fetch … && git switch … && graphify update .`) und `git -C ..` (Pfad außerhalb des Worktrees) abgelehnt. Git-Setup deshalb als einzelne Befehle ausführen, kein `git -C` auf Pfade außerhalb. Das Arbeitsverzeichnis wird zwischen Aufrufen zurückgesetzt: App-Prüfungen als ein Aufruf `cd apps/mobile && flutter test …`. Wird ein zusammengesetzter Befehl abgelehnt, ihn in Einzelbefehle mit absoluten Pfaden zerlegen.
- **Graphify-Graph im Worktree zuerst bauen.** `graphify-out/` steht in `.gitignore`, ein neuer Worktree hat also keinen Graphen, und die Regel „erst `graphify query`“ läuft ins Leere. Erster Schritt in jedem Worktree und in jedem Subagent-Prompt: `graphify update .` (nur AST, keine API-Kosten, etwa 35 Sekunden). Danach erst suchen oder Dateien lesen.
- **Gemeinsame Bausteine zuerst, dann parallel.** Wenn mehrere Agents dieselbe Komponente brauchen (z. B. einen neuen Parameter an `GainerGroupedSection`), baut der Orchestrator sie vorher auf dem Basis-Branch. Sonst erfindet jeder Agent seine eigene Variante und es entstehen Merge-Konflikte.
- **Ein Agent pro Dateibereich.** Zwei Agents, die gleichzeitig `sync_repository.dart` oder dieselbe große Screen-Datei ändern, blockieren sich. Abhängige Arbeit nacheinander und gestapelt (Branch B auf Branch A) erledigen.
- **„Fertig“ ist nicht geprüft.** Jedes Agent-Ergebnis vor dem PR selbst prüfen: `flutter analyze`, `flutter test`, Format-Check und eine lesbare Vorschau (siehe 3). Beim Review gefunden: falsch platzierte Einheiten in Formularzeilen, Überlauf bei Textgröße 2, eine falsch gerechnete Zahl in einer Spec.
- **Modellwahl:** Kleinere, abgegrenzte UI-Umbauten gelingen mit einem kleinen Modell. Bereichsübergreifende Arbeit (Sync, nativer Code mit Pigeon, große Screens) braucht ein stärkeres Modell.

## 2. iOS und nativer Code

- **Swift wird nur in der CI gebaut.** Auf dem Linux-Host gibt es keinen Swift-Compiler. Jede Swift-Änderung zeilenweise reviewen, bevor gepusht wird.
- **Main-Actor-Falle:** Ein `@MainActor`-Initialisierer als Standardargument (`init(x: Foo = Foo())`) kompiliert nicht, weil Standardargumente nicht auf dem Main Actor laufen. Stattdessen Optional übergeben und im Initialisierer erzeugen: `self.x = x ?? Foo()`.
- **Swift-Compilerverhalten nur mit Beleg festhalten** (allgemein: Abschnitt 8, Ursachen belegen). Belegt ist eine Swift-Regel erst durch einen roten CI-Lauf oder gleichartigen Code, der auf `main` baut; vorher nach Gegenbeispielen suchen. Gegenbeispiel zur verworfenen Regel „`guard let x` darf eine lokale Variable `x` nicht verdecken“: `let window = …` gefolgt von `guard let window else { return nil }` in `GainerMobilePlatform.readSleep`, grün gebaut für `aa95c44`. Belegt ist damit der `let`-Fall; für `var` gibt es noch keinen Beleg.
- **Neue Swift-Dateien** müssen in `Runner.xcodeproj/project.pbxproj` eingetragen werden (PBXBuildFile, PBXFileReference, Gruppe, Sources-Phase). Das Projekt synchronisiert Ordner nicht automatisch.
- **Pigeon:** Nach jeder Änderung an `pigeons/mobile_platform_api.dart` neu generieren und **die generierte Dart-Datei formatieren**. Die CI prüft `dart format --set-exit-if-changed lib test pigeons` inklusive generiertem Code.
- **HealthKit lehnt Zeiträume ab, die in der Zukunft enden.** „Bis heute“ endet jetzt, nicht um Mitternacht.
- **Live Activities** können in den iOS-Einstellungen aus sein. Nie dauerhaft aufgeben („nicht verfügbar“-Flag für die ganze Sitzung), sondern bei Rückkehr in die App erneut prüfen und dem Nutzer einen Hinweis mit Weg in die Einstellungen zeigen.
- **Sheets mit Textfeldern** brauchen den Tastaturabstand (`GainerKeyboardInset` bzw. `showGainerSheet`). Ohne ihn liegt die Tastatur über dem Feld.

## 3. Tests und visuelle Kontrolle

- **Goldens zeigen Blockschrift.** Für Layout-Entscheidungen lesbare Vorschauen erzeugen: `cd apps/mobile && tool/preview_goldens.sh test/ui/<bereich>`. Danach `rm -rf test/zz_preview`.
- **`failures/`-Ordner nie committen.** Sie stehen in `.gitignore`. Trotzdem nach `--update-goldens` prüfen, dass nur echte Goldens im Diff sind.
- **Textgröße 2 testen.** Zeilen mit Beschriftung, Eingabe und Einheit laufen sonst über. Bei großer Schrift Beschriftung über die Eingabe stapeln.
- **`AppLifecycleListener` im Code** braucht in reinen `test()`-Tests `TestWidgetsFlutterBinding.ensureInitialized()`.
- **Wenn ein Screen entfällt,** auch die Liste erwarteter Screenshots in `scripts/Verify-Mobile.ps1` anpassen, sonst schlägt der iOS-Simulator-Job fehl.
- **Zahlen in Specs nachrechnen.** Ein Beispiel „80 % von 80 kg → 62,5 kg“ widersprach der eigenen Rundungsregel (richtig: 65 kg).

## 4. CI, PRs und Deploy

- **Basis eines PRs umhängen startet keine Checks.** Nach `base`-Wechsel `main` in den Branch mergen und pushen.
- **`gh pr edit` und `gh issue view` scheitern hier** mit einem GraphQL-Fehler zu „Projects (classic)“ (gh 2.46.0). Stattdessen REST nutzen: lesen mit `gh api repos/PlaySkyHD/Gainer/issues/<n> --jq .body`, ändern mit `gh api -X PATCH repos/PlaySkyHD/Gainer/pulls/<n> -F body=@<datei>` (oder `-f title=...`).
- **Simulator-Timeouts** („Insufficient internal simulator boot phase budget“) sind Infrastruktur. Den fehlgeschlagenen Job neu starten (`gh run rerun <id> --failed`), keinen Code ändern.
- **Deploy sofort auslösen, nicht in einem Warte-Befehl verketten.** Hintergrundbefehle sterben, wenn die Sitzung endet. Nach dem Merge direkt `gh workflow run mobile.yml --ref main -f build_signed_ipa=false -f upload_testflight=true` ausführen und mit `gh run list` bestätigen, dass der Lauf existiert.
- **Das Environment `ios-beta`** hat keine Freigabepflicht mehr, nur noch die Regel „nur `main`“. Kein Freigabeschritt nötig.
- **TestFlight braucht nach dem Upload 10–30 Minuten**, bis der Build auf dem Gerät erscheint. Das ist kein Fehler.
- **Datenbank immer über Docker, nie nativ.** Integrationstests starten Postgres per Testcontainers in Docker.
  - Aufruf: `sg docker -c 'dotnet test …'`. Das gilt auch für `docker compose config` und alle anderen Docker-Befehle, weil die Shell meist älter ist als die Mitgliedschaft in der Gruppe `docker`.
  - Schlägt `docker ps` ohne `sg` fehl, ist das kein Grund für einen Workaround. Kein lokales Postgres, kein `apt install`, kein Dienst auf dem Host.
  - Geht es auch mit `sg docker` nicht, beim Nutzer nachfragen.
- **EF-Migrationen nach `dotnet ef migrations add` mit `dotnet format` nachziehen.** Generierte Dateien haben BOM und Block-Namespace, die CI prüft `--verify-no-changes`. Startprojekt ist `src/Gainer.Infrastructure` (dort liegt die Design-Time-Factory).
- **`git pull --ff-only`** auf `main` verwenden. Nie `git restore`, `git stash` oder `git reset --hard`.
- **History von `main` nur mit Backup und Vorher-nachher-Vergleich umschreiben.**
  - Vorher `git clone --mirror` als Backup, umgeschrieben wird in einem separaten Clone. Kein `--prune-empty`, das entfernt absichtlich leere Commits (z. B. „ci: trigger checks …“).
  - Anzahl der Commits und Merges sowie die Betreffzeilen vorher und nachher vergleichen.
  - Offene PRs vorher mergen oder schließen. GitHub schließt sie beim Force-Push automatisch und öffnet sie nach dem Force-Push des Branches nicht wieder, ein neuer PR ist nötig.
  - Das Ruleset nur für den Push deaktivieren, mit `git push --force-with-lease=main:<alter-sha>` pushen und das Ruleset sofort wieder aktivieren.
  - `refs/pull/*` halten alte Commits auf GitHub weiter sichtbar. Löschen kann nur der GitHub Support.

## 5. Produkt und Design

- **Der Nutzer bewertet auf dem Gerät, nicht anhand von Goldens.** Erst Geräte-Screenshots zeigten: Sheets in voller Höhe, überladene Übersichten, doppelte Überschriften, unklare Zahlen ohne Beschriftung.
- **Maßstab ist der Trainings-Tab:** großer Titel ohne Untertitel, Aktionen in der Toolbar, gruppierte Karten, Wischen zum Löschen, Kontext-Sheet per langem Drücken, Sheets mit Griff und passender Höhe, wenig Text. Jede Karte hat eine Aufgabe.
- **Zahlen deutsch formatieren** (Komma, Tausenderpunkt, keine überflüssigen Nachkommastellen) und **immer beschriften** (z. B. „1RM 101,3 kg“).
- **Nichts anbieten, was nicht funktionieren kann.** Buttons, die in einem Zustand nur einen Fehler erzeugen (Gerätewechsel ohne Daten, „erneut senden“ für nicht wiederholbare Fehler, „Serverstand nutzen“ ohne Serverstand), werden deaktiviert oder ausgeblendet und der Grund wird erklärt.

- **Screens nur einmal öffnen.** Vollbilder, die von außen (Live Activity, Widget) oder nach einer Wartezeit geöffnet werden, laufen über `pushSingleInstance` (`lib/ui/core/navigation/single_instance_route.dart`). Sonst liegt eine zweite Instanz mit altem Stand darunter, die beim Schließen wieder erscheint und beim Speichern neuere Werte überschreiben kann.
- **Prüfen-dann-Anlegen serialisieren.** Ein Doppeltipp startet asynchrone Abläufe zweimal. Abläufe wie „kein aktives Training → anlegen“ brauchen eine Warteschlange oder einen gemeinsamen laufenden Future; Flutter verhindert nur das doppelte Pushen synchroner Taps.

## 6. Sync

- **Ein wartender Stand je Ressource.** Zwischenschritte (gestartet → geändert → beendet) einzeln nachzuspielen erzeugt Konflikte, sobald ein früher Schritt hängt. Neue Änderungen fassen den noch nicht gesendeten Eintrag zusammen.
- **Einzelschreiber-Modell sichtbar machen.** Ist das Gerät nicht Schreibgerät, muss der Nutzer das sofort sehen und übernehmen können. Sonst sammeln sich unbemerkt Änderungen.
- **Abhängigkeiten zuerst senden** (Übung vor Training). Fehlende Referenzen sind kein Konflikt, sondern ein Grund zu warten.
- **Kindzeilen ersetzen: Löschen zuerst speichern.** Handler, die alle Unterzeilen ersetzen und dabei dieselben IDs wiederverwenden (Ernährungseinträge, Gerichtskomponenten, Trainingssätze), müssen das Entfernen mit `SaveChanges` abschließen, bevor sie die neuen Zeilen anlegen, beides in einer Transaktion. EF Core ordnet die Befehle sonst so, dass eindeutige Indizes wie Mahlzeit + Position kurzzeitig doppelt belegt sind. Löschen des ersten Eintrags, Einfügen oben oder Tauschen scheitern dann.
- **Datenbankfehler nicht als Versionskonflikt tarnen.** Ein Unique-Fehler, den der Server als `stale_base_version` meldet, erscheint in der App als „neuere Version auf dem Server“, auch mit nur einem Gerät. Die Selbstheilung greift nicht, weil der lokale Stand genau der abgelehnte ist. Bei unerklärlichen Konflikten den Ablauf als Integrationstest gegen Postgres nachstellen, bevor am Client gesucht wird.
- **Abgeleitete Logik bei neuen Features prüfen.** Vorwerte wurden nach Position zugeordnet; mit Aufwärmsätzen verrutschten sie. Zuordnung jetzt nach Position innerhalb des Satztyps.
- **Neue Sync-Ressource ⇒ Protokollversion erhöhen.** Ausgelieferte Apps brechen den Pull bei einem unbekannten Ressourcentyp ab und rücken den Cursor nicht vor. Der Sync aller alten Geräte des Kontos stünde dann still. Den neuen Typ in `SyncResourceProtocol` mit Mindestprotokoll eintragen und `SyncProtocol.CurrentVersion` sowie `nativeSyncProtocolVersion` erhöhen. Registrierung und Pull antworten alten Clients dann mit `upgrade_required` (Beispiel: Wasser, Protokoll 4).

## 7. Agent-Konfiguration

- **Quelle ist `.agents/`.** Skills liegen in `.agents/skills/<name>/SKILL.md`, Instructions in `.agents/instructions/`. `.claude/skills/<name>` und `.claude/rules/<name>.md` sind relative Symlinks darauf; nie Kopien anlegen.
- **Instructions:** `backend`, `mobile` und `security` gelten beim Programmieren, `code-review` nur beim Review (Skill `gainer-review`). Sie beschreiben Gainer-Konventionen in wenigen Zeilen; Fallstricke gehören in diese Datei. Keine allgemeinen Vorlagen aus anderen Projekten übernehmen: Die frühere Sammlung verlangte Azure Tables statt EF Core und englische Specs.
- **Retro nach jedem PR.** Direkt nach `gh pr create` läuft der Skill `retro` (in Claude Code erinnert ein Hook daran, andere Agents rufen ihn selbst auf). Er legt belegte Findings zur Agent-Umgebung als Issues mit Label `agent-retro` an. Die Fixes kommen in eigenen PRs mit `Fixes #<n>`, nie in den gerade erstellten PR.
- **Neuer Skill:** in `.agents/skills/` anlegen, dann `ln -s ../../.agents/skills/<name> .claude/skills/<name>`. Der Ordnername muss dem `name:` im Frontmatter entsprechen.
- **Neue Instruction:** neben `applyTo` (Copilot) auch `paths:` (Claude) ins Frontmatter schreiben und nach `.claude/rules/` verlinken. Ohne `paths:` lädt Claude die Regel in jede Sitzung.

## 8. Arbeitsweise, die sich bewährt hat

- Jede Änderung als OpenSpec-Change mit `openspec validate <change> --strict`, dann ein PR pro Thema.
- **Im selben PR archivieren.** Als letzten Schritt vor dem Merge übernimmt `openspec archive <change> -y` die Deltas in `openspec/specs`. Danach zusätzlich `openspec validate --specs --strict` ausführen, weil die Change-Validierung MODIFIED-Anforderungen nicht vollständig prüft (z. B. die Länge); die CI prüft das ebenfalls, mit der CLI-Version aus `tools/openspec/package.json` (Quelle der CI-Version, mit Lockdatei). Der Workflow „OpenSpec“ schlägt fehl, solange unter `openspec/changes/` ein Change außerhalb von `archive/` liegt. Bis Oktober 2026 blieben 40 Changes offen, die Specs widersprachen sich und mussten von Hand zusammengeführt werden. Deltas gehören in die passende fachliche Spec (z. B. `training-session`, `meal-tracking`), nicht in eine neue Mini-Capability je Feature. Ändert ein Feature eine bestehende Anforderung, nutze `MODIFIED` oder `REMOVED`, statt im Proposal auf einen anderen Change zu verweisen.
- Merge erst, wenn alle Checks grün sind, dann sofort TestFlight.
- Ein Subagent-Brief mit festen Regeln (graphify, keine `.gymapp/`, kein `git restore`, Format nur geänderter Dateien, Tests, Vorschau, Bericht) spart Rückfragen.
- Ursachen im Code belegen, bevor ein Fix gebaut wird (HealthKit-Ende, Schreibgerät-Registrierung, Konfliktcodes).
