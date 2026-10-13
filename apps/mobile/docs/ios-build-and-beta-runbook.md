# iOS-Build-, Device- und Beta-Runbook

Stand: 13. Oktober 2026. Nutzer hat ein iPhone 15 Pro (iOS 26.6.2), keinen Mac und einen bezahlten individuellen Apple Developer Account. Team-ID `Q7GTYQ282F`, Bundle-IDs, App Group sowie die vier Signier-Secrets sind im GitHub Environment `ios-beta` eingerichtet. Apple-Profil-/Signaturprüfungen müssen beim signierten CI-Lauf weiterhin tatsächlich bestehen. App-Store-Connect-API-Secrets fehlen noch und werden in [Apple Developer Setup](apple-developer-setup.md) angeleitet. Kein Upload geschieht durch diese Vorbereitung.

Repository: [PlaySkyHD/Gainer](https://github.com/PlaySkyHD/Gainer.git), öffentlich, MIT-lizenziert. Windows + iPhone ermöglicht keinen lokalen nativen iOS/Xcode-Build oder Codesign. Windows-Checks ersetzen keinen iOS-Nachweis.

Die CI-Zieltoolchain ist Flutter **3.47.7 stable**, Dart **3.13.5**, GitHub Runner **macos-15** (ARM64-Image), Xcode **26.3**. CI nutzt das offizielle ARM64-Archiv derselben Flutter-Revision, damit Flutter nativ auf dem Apple-Silicon-Runner läuft; die SHA-256-Prüfung bleibt aktiv. Der SDK-Pfad `artifacts/flutter-sdk/3.47.7/flutter` ist separat installiert; das globale Flutter-Master-SDK bleibt unverändert. Der erste macOS-Simulatorlauf war erfolgreich: [GitHub Actions run 38270878066](https://github.com/PlaySkyHD/Gainer/actions/runs/38270878066). Er belegt den damaligen Bootstrapstand; die aktuelle Widget-Extension und die späteren Änderungen sind durch diesen Lauf nicht abgenommen. Physische iPhone-Nachweise sind offen.

## Workflowaufteilung

1. **PR/Push CI, ohne Signatur:** macOS runner mit gepinnter Flutter Stable-/Dart-/Xcode-Toolchain, `flutter pub get --enforce-lockfile`, Format, Analyze, Unit-/Widget-Tests, Simulatorbuild und Backend-/PWA-Regressionchecks. Artefakte bleiben im CI; ein GitHub Actions-Artefakt ist nicht als privat zu behandeln.
2. **Signierter Vorbereitungsbuild:** ausschließlich manueller `workflow_dispatch` im GitHub Environment `ios-beta`; Workflow verlangt `main`, prüft, dass der Commit von `origin/main` abstammt, und wartet auf erfolgreiche Simulator-CI. Signing-Secrets erst nach Environment-Freigabe. `build_signed_ipa` erzeugt ein signiertes IPA-Artefakt, das im öffentlichen Repository für Leser abrufbar sein kann.
3. **TestFlight-Upload:** dieselbe manuelle Dispatch kann mit `upload_testflight=true` die Signatur bauen, prüfen und die IPA hochladen. Der Job verlangt weiterhin `main`, erfolgreiche Simulator-CI und die manuelle Environment-Freigabe. API-Key-Secrets werden nur in diesem Pfad benötigt. Dieser Pfad legt kein IPA-Artefakt ab, reicht die App nicht zur öffentlichen Prüfung ein und lädt keine Tester ein.

Beobachtete GitHub-Einstellungen: Repository public/MIT; Environment `ios-beta` ist auf `main` beschränkt und verlangt manuelle Freigabe durch `PlaySkyHD`. Der manuelle Dispatch ist der Ausgangspunkt. IPA-Artefakte des reinen Signierpfads können für Repository-Leser herunterladbar sein; der TestFlight-Pfad legt kein IPA-Artefakt ab.

## Benötigte GitHub-Konfiguration

Die vier Bezeichner liegen als nicht geheime Variablen im GitHub Environment `ios-beta`; nur Zertifikat, Passwort und Profile sind Secrets. Keine davon als Workflow-Input übergeben oder in Logs ausgeben.

| Name | Typ | Verwendung und offener Beschaffungsnachweis |
|---|---|---|
| `APPLE_TEAM_ID` | Environment variable | `Q7GTYQ282F`, eingerichtet; Workflow prüft die Übereinstimmung mit beiden Profilen. |
| `IOS_BUNDLE_ID` | Environment variable | `xyz.markfort.gainer`, eingerichtet; Profil/Entitlements werden im Workflow geprüft. |
| `IOS_WIDGET_BUNDLE_ID` | Environment variable | `xyz.markfort.gainer.Widgets`, eingerichtet; Profilzuordnung wird im Workflow geprüft. |
| `IOS_APP_GROUP_ID` | Environment variable | `group.xyz.markfort.gainer`, eingerichtet; Mitgliedschaft muss in beiden Profilen stehen. |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Secret | Eingerichtet; privater Wert wurde in diesem Review nicht gelesen. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Secret | Eingerichtet; privater Wert wurde in diesem Review nicht gelesen. |
| `IOS_PROVISIONING_PROFILE_BASE64` | Secret | Eingerichtet; Profilinhalt wird erst im signierten Workflow geprüft. |
| `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` | Secret | Eingerichtet; Profilinhalt wird erst im signierten Workflow geprüft. |
| `APP_STORE_CONNECT_KEY_ID` | Environment secret | Team API-Key-ID; nur bei `upload_testflight=true` gebraucht. |
| `APP_STORE_CONNECT_ISSUER_ID` | Environment secret | Issuer-ID der Team-API-Key-Seite; nur beim Upload gebraucht. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Environment secret | Unveränderter mehrzeiliger PEM-Inhalt der `.p8`-Team-Key-Datei; nur beim Upload gebraucht. |

Der API-Key wird im Portal durch den Account Holder erzeugt und auf die Rolle
Developer beschränkt. Apple bewahrt den privaten Schlüssel nicht für einen
erneuten Download auf; siehe [Apple Developer Setup](apple-developer-setup.md)
für die sichere Anlage und Speicherung. Eine Individual API Key hat keine
Issuer-ID und ist nicht mit dem derzeitigen Team-Key-Uploadpfad kompatibel.

Die IDs und vier Signier-Secrets sind eingerichtet. HealthKit-Entitlement, Widget-Profil und Export müssen durch einen signierten macOS-Lauf bestätigt werden. Keine persönlichen Fitnessdaten in Artefakten.

## Build- und iPhone-Nachweismatrix

| Gate | Umgebung | Nachweis | Status |
|---|---|---|---|
| Bootstrap-Simulatorbuild | GitHub macOS runner | [Run 38270878066](https://github.com/PlaySkyHD/Gainer/actions/runs/38270878066) | Erfolgreich für den damaligen Bootstrapstand; aktuelle Extension/Änderungen offen. |
| Stable Flutter/Dart/Xcode festgelegt, Lockfile-Restore | GitHub macOS runner | Versionen, `flutter pub get --enforce-lockfile`, erfolgreicher aktueller Run | Versionen sind gepinnt; aktueller vollständiger Run bleibt offen. |
| Format/Analyze/Unit-/Widget-/API-Integrationstests | macOS runner + Backend/PWA jobs | Run-URL, Commit SHA, secret-free Reports | Offen. |
| iOS Simulator build/test | macOS runner | xcodebuild/Flutter-Artefakt, Simulatorziel und SDK-Version | Offen; kein Gerätetest. |
| Installation und Basisnavigation | Nutzer-iPhone | Modell/iOS-Version, Build SHA, Journey-Screens ohne Kontodaten | iPhone 15 Pro / iOS 26.6.2 gemeldet; Gerätetest offen. |
| Offline, Kill/Resume, 401, Replay, Konflikt, Handover/Rückwechsel, 2 Konten | iPhone + kontrollierte Testkonten | Erwartet/Ist, Zeit, Build SHA, bereinigte Logs | Offen. |
| Kamera/Picker, Upload/Review, Notification Resume | iPhone | Permission-Fälle, synthetisches Testbild und Retry-Ergebnis | Offen. |
| HealthKit getrennt Read/Write, Konto A/B, Crash-Retry | iPhone + synthetische Werte | Review/Consent und Testfälle; keine realen Gesundheitsdaten in Artefakten | Offen; erster iOS-Release erfordert dies. |
| Widget, Live Activity, Shortcuts | iPhone, Dynamic-Island und Fallback soweit Hardware verfügbar | Routes, stale/logout/A→B, VoiceOver, neutrale Anzeige | Offen; erster iOS-Release erfordert dies. |
| Signierte IPA | manueller `workflow_dispatch` | Run-ID, Commit SHA, IPA SHA-256, Entitlements/Profile-Validierung ohne Secretwerte | Offen; Signierwerte fehlen. Vor Lauf muss der mögliche Download durch Repository-Leser bewertet sein. |
| TestFlight Upload | manueller `workflow_dispatch`, `upload_testflight=true`, `ios-beta` Freigabe | Upload-/Buildstatus; Testergruppe bleibt manuell | Nicht ausgeführt. Erfolgreicher Upload bedeutet noch keine abgeschlossene Apple-Verarbeitung oder Tester-Verfügbarkeit. |

Simulator beweist keine HealthKit-, Kamera-, Notification-, Widget-/Activity- oder Signierfunktion am Gerät. iOS 17+ ist Mindestmatrix; Gerät/OS je Nachweis protokollieren. Tests auf einem Gerät mit und ohne Dynamic Island soweit verfügbar.

## Private Beta vorbereiten (ohne Upload)

1. Team, App-/Extension-Bundle-ID, App Group und Capabilities festlegen; danach GitHub `ios-beta` mit den beobachteten `main`-/Reviewer-Regeln nutzen.
2. Erst unsignierte CI stabilisieren; dann Profile/Entitlements/ExportOptions gegen dieselben IDs prüfen. Secrets nicht als workflow_dispatch-Eingaben verwenden und nie loggen.
3. Einen signierten Lauf erst starten, wenn die Zugriffspolitik für IPA-Artefakte im öffentlichen Repository entschieden ist. Das Artefakt nicht als privat oder zugriffsbeschränkt bezeichnen; Run-ID, SHA und IPA-SHA256 dokumentieren.
4. Privacy-/Permission-Texte für Kamera, HealthKit Read Body Mass, HealthKit Write Workouts und Notifications vorbereiten; Denied-State prüfen.
5. TestFlight interne Beschreibung, Buildzweck, bekannte Einschränkungen, Support-/Recoveryhinweise vorbereiten. Keine Testergruppe/Verteilung in CI.
6. Nach der erforderlichen Freigabe API-Key eintragen und `upload_testflight=true` im manuellen Dispatch auswählen. Der Upload geht an App Store Connect; Verarbeitung und manuelle interne Tester-Zuordnung folgen separat.

## Manueller Vorbereitungs-Build

1. Geprüften Commit mergen und SHA notieren; Simulator-/Dart-/Backend-/PWA-Gates müssen grün sein.
2. GitHub Actions **Mobile CI** per `workflow_dispatch` für den geprüften `main`-Commit starten. `build_signed_ipa=true` erzeugt nur ein IPA-Artefakt. `upload_testflight=true` impliziert den signierten Build und lädt stattdessen zur Verarbeitung hoch. Standardmäßig verwendet CI `GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`; falls App Store Connect bereits höhere oder in anderen Buildwegen vergebene Nummern hat, vor dem Upload eine unbenutzte `build_number` eintragen.
3. Bei fehlenden Secrets/Profiles abbrechen und fehlende Namen protokollieren. Keine Ersatzwerte oder Profile committen.
4. Deployment Target, Signatur, App-/Extension-Entitlements, HealthKit, App Group und Profilzuordnung validieren. Run-ID, SHA, IPA SHA-256 notieren; Secretwerte bleiben verborgen.
5. Ein TestFlight-Build wird erst sichtbar, wenn Apple ihn verarbeitet hat. Interne Testergruppe anschließend von Hand zuweisen; CI versendet keine Einladung.
6. Eine öffentliche App-Review/Veröffentlichung wird von diesem Workflow nicht ausgelöst und bleibt ein gesonderter manueller Schritt.

PWA bleibt bis zur nutzerweisen bestätigten Übergabe zugänglich. Recovery nach Beta-Fehler läuft über Sync, Konfliktprüfung und bestätigte Rückgabe. Keine Deinstallation als Recovery und keine PWA-Stilllegung.
