# Lessons Learned für Agents

Erkenntnisse aus der Umsetzung von Trainingssystem, App-Design, Health-Check-in, Timer und Sync (Oktober 2026). Jeder Agent, der in diesem Repo arbeitet oder Subagents steuert, liest diese Datei vor dem ersten Schritt.

## 1. Subagents und Worktrees

- **Worktrees starten auf `main`, nicht auf deinem Feature-Branch.** Ein Subagent mit `isolation: worktree` sieht deine neuen Bausteine und OpenSpec-Dateien nicht. Erster Schritt in jedem Subagent-Prompt: `git merge --no-edit <feature-branch>`.
- **Gemeinsame Bausteine zuerst, dann parallel.** Wenn mehrere Agents dieselbe Komponente brauchen (z. B. einen neuen Parameter an `GainerGroupedSection`), baut der Orchestrator sie vorher auf dem Basis-Branch. Sonst erfindet jeder Agent seine eigene Variante und es entstehen Merge-Konflikte.
- **Ein Agent pro Dateibereich.** Zwei Agents, die gleichzeitig `sync_repository.dart` oder dieselbe große Screen-Datei ändern, blockieren sich. Abhängige Arbeit nacheinander und gestapelt (Branch B auf Branch A) erledigen.
- **„Fertig“ ist nicht geprüft.** Jedes Agent-Ergebnis vor dem PR selbst prüfen: `flutter analyze`, `flutter test`, Format-Check und eine lesbare Vorschau (siehe 3). Beim Review gefunden: falsch platzierte Einheiten in Formularzeilen, Überlauf bei Textgröße 2, eine falsch gerechnete Zahl in einer Spec.
- **Modellwahl:** Kleinere, abgegrenzte UI-Umbauten gelingen mit einem kleinen Modell. Bereichsübergreifende Arbeit (Sync, nativer Code mit Pigeon, große Screens) braucht ein stärkeres Modell.

## 2. iOS und nativer Code

- **Swift wird nur in der CI gebaut.** Auf dem Linux-Host gibt es keinen Swift-Compiler. Jede Swift-Änderung zeilenweise reviewen, bevor gepusht wird.
- **Main-Actor-Falle:** Ein `@MainActor`-Initialisierer als Standardargument (`init(x: Foo = Foo())`) kompiliert nicht, weil Standardargumente nicht auf dem Main Actor laufen. Stattdessen Optional übergeben und im Initialisierer erzeugen: `self.x = x ?? Foo()`.
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
- **Simulator-Timeouts** („Insufficient internal simulator boot phase budget“) sind Infrastruktur. Den fehlgeschlagenen Job neu starten (`gh run rerun <id> --failed`), keinen Code ändern.
- **Deploy sofort auslösen, nicht in einem Warte-Befehl verketten.** Hintergrundbefehle sterben, wenn die Sitzung endet. Nach dem Merge direkt `gh workflow run mobile.yml --ref main -f build_signed_ipa=false -f upload_testflight=true` ausführen und mit `gh run list` bestätigen, dass der Lauf existiert.
- **Das Environment `ios-beta`** hat keine Freigabepflicht mehr, nur noch die Regel „nur `main`“. Kein Freigabeschritt nötig.
- **TestFlight braucht nach dem Upload 10–30 Minuten**, bis der Build auf dem Gerät erscheint. Das ist kein Fehler.
- **`git pull --ff-only`** auf `main` verwenden. Nie `git restore`, `git stash` oder `git reset --hard`.

## 5. Produkt und Design

- **Der Nutzer bewertet auf dem Gerät, nicht anhand von Goldens.** Erst Geräte-Screenshots zeigten: Sheets in voller Höhe, überladene Übersichten, doppelte Überschriften, unklare Zahlen ohne Beschriftung.
- **Maßstab ist der Trainings-Tab:** großer Titel ohne Untertitel, Aktionen in der Toolbar, gruppierte Karten, Wischen zum Löschen, Kontext-Sheet per langem Drücken, Sheets mit Griff und passender Höhe, wenig Text. Jede Karte hat eine Aufgabe.
- **Zahlen deutsch formatieren** (Komma, Tausenderpunkt, keine überflüssigen Nachkommastellen) und **immer beschriften** (z. B. „1RM 101,3 kg“).
- **Nichts anbieten, was nicht funktionieren kann.** Buttons, die in einem Zustand nur einen Fehler erzeugen (Gerätewechsel ohne Daten, „erneut senden“ für nicht wiederholbare Fehler, „Serverstand nutzen“ ohne Serverstand), werden deaktiviert oder ausgeblendet und der Grund wird erklärt.

## 6. Sync

- **Ein wartender Stand je Ressource.** Zwischenschritte (gestartet → geändert → beendet) einzeln nachzuspielen erzeugt Konflikte, sobald ein früher Schritt hängt. Neue Änderungen fassen den noch nicht gesendeten Eintrag zusammen.
- **Einzelschreiber-Modell sichtbar machen.** Ist das Gerät nicht Schreibgerät, muss der Nutzer das sofort sehen und übernehmen können. Sonst sammeln sich unbemerkt Änderungen.
- **Abhängigkeiten zuerst senden** (Übung vor Training). Fehlende Referenzen sind kein Konflikt, sondern ein Grund zu warten.
- **Abgeleitete Logik bei neuen Features prüfen.** Vorwerte wurden nach Position zugeordnet; mit Aufwärmsätzen verrutschten sie. Zuordnung jetzt nach Position innerhalb des Satztyps.

## 7. Arbeitsweise, die sich bewährt hat

- Jede Änderung als OpenSpec-Change mit `openspec validate <change> --strict`, dann ein PR pro Thema.
- Merge erst, wenn alle Checks grün sind, dann sofort TestFlight.
- Ein Subagent-Brief mit festen Regeln (graphify, keine `.gymapp/`, kein `git restore`, Format nur geänderter Dateien, Tests, Vorschau, Bericht) spart Rückfragen.
- Ursachen im Code belegen, bevor ein Fix gebaut wird (HealthKit-Ende, Schreibgerät-Registrierung, Konfliktcodes).
