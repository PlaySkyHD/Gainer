# iOS-Build-, Device- und Beta-Runbook

Stand: 12. Oktober 2026. Nutzer hat ein iPhone 15 Pro (iOS 26.6.2), keinen Mac und einen bezahlten individuellen Apple Developer Account; Team-ID `Q7GTYQ282F` wurde vom Nutzer genannt und muss im Portal verifiziert werden. iOS-Builds laufen über GitHub CI/CD mit macOS Runner. Kein Upload oder Versand geschieht durch diese Vorbereitung. Die Einrichtungsschritte für Zertifikat, Profile und GitHub-Secrets stehen in [Apple Developer Setup](apple-developer-setup.md).

Repository: [PlaySkyHD/Gainer](https://github.com/PlaySkyHD/Gainer.git), öffentlich, MIT-lizenziert. Windows + iPhone ermöglicht keinen lokalen nativen iOS/Xcode-Build oder Codesign. Windows-Checks ersetzen keinen iOS-Nachweis.

Die CI-Zieltoolchain ist Flutter **3.47.7 stable**, Dart **3.13.5**, GitHub Runner **macos-15**, Xcode **26.3**. Der SDK-Pfad `artifacts/flutter-sdk/3.47.7/flutter` ist separat installiert; das globale Flutter-Master-SDK bleibt unverändert. Der erste macOS-Simulatorlauf war erfolgreich: [GitHub Actions run 38270878066](https://github.com/PlaySkyHD/Gainer/actions/runs/38270878066). Er belegt den damaligen Bootstrapstand; die aktuelle Widget-Extension und die späteren Änderungen sind durch diesen Lauf nicht abgenommen. Physische iPhone-Nachweise sind offen.

## Workflowaufteilung

1. **PR/Push CI, ohne Signatur:** macOS runner mit gepinnter Flutter Stable-/Dart-/Xcode-Toolchain, `flutter pub get --enforce-lockfile`, Format, Analyze, Unit-/Widget-Tests, Simulatorbuild und Backend-/PWA-Regressionchecks. Artefakte bleiben im CI; ein GitHub Actions-Artefakt ist nicht als privat zu behandeln.
2. **Signierter Vorbereitungsbuild:** ausschließlich manueller `workflow_dispatch` im GitHub Environment `ios-beta`; Workflow verlangt `main` und prüft, dass der Commit von `origin/main` abstammt. Signing-Secrets erst nach Environment-Freigabe. Der Export ist eine IPA ohne Upload. Da das Repository öffentlich ist, kann ein IPA-Artefakt für Repository-Leser herunterladbar sein; Zugriffspolitik/Verteilung ist vor einem signierten Lauf festzulegen.
3. **TestFlight:** separater Workflow/Schritt und gesonderte Freigabe. App Store Connect API-Key erst dafür erforderlich. IPA-Build darf keine Upload-Aktion enthalten.

Beobachtete GitHub-Einstellungen: Repository public/MIT; Environment `ios-beta` ist auf `main` beschränkt und verlangt manuelle Freigabe durch `PlaySkyHD`. Der manuelle Dispatch ist der Ausgangspunkt. Der öffentliche Artefaktzugriff bleibt vor einem signierten Lauf zu klären.

## Benötigte GitHub-Konfiguration

Die vier Bezeichner liegen als nicht geheime Variablen im GitHub Environment `ios-beta`; nur Zertifikat, Passwort und Profile sind Secrets. Keine davon als Workflow-Input übergeben oder in Logs ausgeben.

| Name | Typ | Verwendung und offener Beschaffungsnachweis |
|---|---|---|
| `APPLE_TEAM_ID` | Environment variable | `Q7GTYQ282F` (Nutzerangabe; Apple-Portal-Verknüpfung verifizieren). |
| `IOS_BUNDLE_ID` | Environment variable | `xyz.markfort.gainer`; App-ID-Registrierung/Capabilities vor Signierung verifizieren. |
| `IOS_WIDGET_BUNDLE_ID` | Environment variable | `xyz.markfort.gainer.Widgets`; App-ID-Registrierung vor Signierung verifizieren. |
| `IOS_APP_GROUP_ID` | Environment variable | `group.xyz.markfort.gainer`; Registrierung und beide Profilzuweisungen verifizieren. |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Secret | Canonical Workflowname für Apple Distribution `.p12` Base64; Zertifikat noch zu erzeugen/exportieren. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Secret | Canonical Workflowname für P12-Passwort; nie echoen. |
| `IOS_PROVISIONING_PROFILE_BASE64` | Secret | Canonical Workflowname für App-Profil, passend zu IDs, Entitlements und Beta-Verfahren. |
| `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` | Secret | Provisioning-Profil für die Widget-Extension. |
| `APP_STORE_CONNECT_KEY_ID` | später, Secret/Variable | Nur für separaten Upload, derzeit nicht benötigt. |
| `APP_STORE_CONNECT_ISSUER_ID` | später, Secret/Variable | Nur für separaten Upload, derzeit nicht benötigt. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | später, Secret | `.p8` erst anlegen, wenn Upload ausdrücklich freigegeben ist. |

Bundle-/App-Group-IDs und Signiermaterial fehlen. HealthKit entitlement, Usage Descriptions, Extension profile und ExportOptions nach Wahl von SDK und App IDs verifizieren. Keine persönlichen Fitnessdaten in Artefakten.

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
| TestFlight Upload | separater freigegebener Schritt | Upload-/Buildstatus und private Testergruppe | Nicht ausgeführt, kein Upload autorisiert. |

Simulator beweist keine HealthKit-, Kamera-, Notification-, Widget-/Activity- oder Signierfunktion am Gerät. iOS 17+ ist Mindestmatrix; Gerät/OS je Nachweis protokollieren. Tests auf einem Gerät mit und ohne Dynamic Island soweit verfügbar.

## Private Beta vorbereiten (ohne Upload)

1. Team, App-/Extension-Bundle-ID, App Group und Capabilities festlegen; danach GitHub `ios-beta` mit den beobachteten `main`-/Reviewer-Regeln nutzen.
2. Erst unsignierte CI stabilisieren; dann Profile/Entitlements/ExportOptions gegen dieselben IDs prüfen. Secrets nicht als workflow_dispatch-Eingaben verwenden und nie loggen.
3. Einen signierten Lauf erst starten, wenn die Zugriffspolitik für IPA-Artefakte im öffentlichen Repository entschieden ist. Das Artefakt nicht als privat oder zugriffsbeschränkt bezeichnen; Run-ID, SHA und IPA-SHA256 dokumentieren.
4. Privacy-/Permission-Texte für Kamera, HealthKit Read Body Mass, HealthKit Write Workouts und Notifications vorbereiten; Denied-State prüfen.
5. TestFlight interne Beschreibung, Buildzweck, bekannte Einschränkungen, Support-/Recoveryhinweise vorbereiten. Keine Testergruppe/Verteilung bis Freigabe.
6. App Store Connect API-Key und Upload erst nach gesonderter Freigabe. Bis dahin kein Upload-Schritt im Workflow.

## Manueller Vorbereitungs-Build

1. Geprüften Commit mergen und SHA notieren; Simulator-/Dart-/Backend-/PWA-Gates müssen grün sein.
2. GitHub Actions Signing-Workflow per `workflow_dispatch` für den geprüften `main`-Commit starten und `build_signed_ipa` auf `true` setzen. Der Workflow hat keinen Upload-Schritt.
3. Bei fehlenden Secrets/Profiles abbrechen und fehlende Namen protokollieren. Keine Ersatzwerte oder Profile committen.
4. Deployment Target, Signatur, App-/Extension-Entitlements, HealthKit, App Group und Profilzuordnung validieren. Run-ID, SHA, IPA SHA-256 notieren; Secretwerte bleiben verborgen.
5. Gerätetest durch den Nutzer erst über vereinbarten geschützten Installationsweg. Kein TestFlight Upload hier.
6. Separaten Uploadschritt erst nach Freigabe; Beta bleibt privat. Öffentliche Veröffentlichung gehört nicht zu diesem Change.

PWA bleibt bis zur nutzerweisen bestätigten Übergabe zugänglich. Recovery nach Beta-Fehler läuft über Sync, Konfliktprüfung und bestätigte Rückgabe. Keine Deinstallation als Recovery und keine PWA-Stilllegung.
