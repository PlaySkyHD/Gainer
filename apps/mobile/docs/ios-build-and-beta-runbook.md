# iOS-Build-, Device- und private Beta-Runbook

Stand: 12. Oktober 2026. Nutzer hat ein iPhone, keinen Mac und einen privaten Apple Developer Account. iOS-Builds laufen über GitHub CI/CD mit macOS Runner. Kein Upload oder Versand geschieht durch diese Vorbereitung.

Repository: [PlaySkyHD/Gainer](https://github.com/PlaySkyHD/Gainer.git). Windows + iPhone ermöglicht keinen lokalen nativen iOS/Xcode-Build oder Codesign. Windows-Checks ersetzen keinen iOS-Nachweis.

Bootstrap hat die CI-Zieltoolchain festgelegt: Flutter **3.47.7 stable**, Dart **3.13.5**, GitHub Runner **macos-15**, Xcode **26.3**. Der SDK-Pfad `artifacts/flutter-sdk/3.47.7/flutter` ist separat installiert; das globale Flutter-Master-SDK bleibt unverändert. Der Workflow prüft die Toolchain und baut den Simulator. Eine erfolgreiche macOS-Run-URL und physische iPhone-Nachweise sind noch offen.

## Workflowaufteilung

1. **PR/Push CI, ohne Signatur:** macOS runner mit gepinnter Flutter Stable-/Dart-/Xcode-Toolchain, `flutter pub get --enforce-lockfile`, Format, Analyze, Unit-/Widget-Tests, Simulatorbuild und Backend-/PWA-Regressionchecks. Artefakte bleiben im CI, keine Verteilung.
2. **Signierter Vorbereitungsbuild:** ausschließlich `workflow_dispatch`, GitHub Environment `ios-beta` falls verfügbar; Ref/Commit explizit wählen. Zertifikat/Profile importieren und signierte IPA als zugriffsbeschränktes CI-Artefakt exportieren. **Kein App Store Connect Upload.**
3. **TestFlight:** separater Workflow/Schritt und gesonderte Freigabe. App Store Connect API-Key erst dafür erforderlich. IPA-Build darf keine Upload-Aktion enthalten.

Private-Repos unterstützen Required Reviewers abhängig von GitHub-Plan/Org-Einstellungen; das darf nicht vorausgesetzt werden. Manueller Dispatch ist die Basis. Tatsächlich verfügbare Environment-Regeln vor Nutzung prüfen.

## Benötigte GitHub-Konfiguration

Werte fehlen und dürfen nicht geraten werden. GitHub Environment `ios-beta` verwenden; Zertifikat-/Profilwerte ausschließlich als Secrets. Nichts davon in Code/Logs/Chat ausgeben.

| Name | Typ | Verwendung und offener Beschaffungsnachweis |
|---|---|---|
| `APPLE_TEAM_ID` | Variable/Secret | Teamkennung vom privaten Developer Account bestätigen; offen. |
| `IOS_BUNDLE_ID` | Variable | App Bundle ID auswählen und im Developer Portal anlegen; offen. |
| `IOS_WIDGET_BUNDLE_ID` | Variable | Extension Bundle ID passend zum App-Namespace festlegen; offen. |
| `IOS_APP_GROUP_ID` | Variable | App Group auswählen, im Portal registrieren und Capability zuordnen; offen. |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Secret | Canonical Workflowname für Apple Distribution `.p12` Base64; Zertifikat noch zu erzeugen/exportieren. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Secret | Canonical Workflowname für P12-Passwort; nie echoen. |
| `IOS_PROVISIONING_PROFILE_BASE64` | Secret | Canonical Workflowname für App-Profil, passend zu IDs, Entitlements und Beta-Verfahren. |
| `IOS_WIDGET_PROVISION_PROFILE_BASE64` | Secret | Extension-Profil, soweit Signingweg separat erfordert. |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | optionales zukünftiges Secret; aktuelle CI erzeugt die Datei zur Laufzeit | Falls später als Input benötigt: Methode/Team/IDs/Profiles konsistent halten. Der aktuelle Workflow benötigt keinen Wert. |
| `APP_STORE_CONNECT_KEY_ID` | später, Secret/Variable | Nur für separaten Upload, derzeit nicht benötigt. |
| `APP_STORE_CONNECT_ISSUER_ID` | später, Secret/Variable | Nur für separaten Upload, derzeit nicht benötigt. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | später, Secret | `.p8` erst anlegen, wenn Upload ausdrücklich freigegeben ist. |

Bundle-/App-Group-IDs und Signiermaterial fehlen. HealthKit entitlement, Usage Descriptions, Extension profile und ExportOptions nach Wahl von SDK und App IDs verifizieren. Keine persönlichen Fitnessdaten in Artefakten.

## Build- und iPhone-Nachweismatrix

| Gate | Umgebung | Nachweis | Status |
|---|---|---|---|
| Stable Flutter/Dart/Xcode festgelegt, Lockfile-Restore | GitHub macOS runner | Versionen, `flutter pub get --enforce-lockfile`, erfolgreiche Run-URL | Versionen sind gepinnt; erfolgreicher CI-Run bleibt offen. |
| Format/Analyze/Unit-/Widget-/API-Integrationstests | macOS runner + Backend/PWA jobs | Run-URL, Commit SHA, secret-free Reports | Offen. |
| iOS Simulator build/test | macOS runner | xcodebuild/Flutter-Artefakt, Simulatorziel und SDK-Version | Offen; kein Gerätetest. |
| Installation und Basisnavigation | Nutzer-iPhone | Modell/iOS-Version, Build SHA, Journey-Screens ohne Kontodaten | iPhone vorhanden; Modell/OS nicht dokumentiert. |
| Offline, Kill/Resume, 401, Replay, Konflikt, Handover/Rückwechsel, 2 Konten | iPhone + kontrollierte Testkonten | Erwartet/Ist, Zeit, Build SHA, bereinigte Logs | Offen. |
| Kamera/Picker, Upload/Review, Notification Resume | iPhone | Permission-Fälle, synthetisches Testbild und Retry-Ergebnis | Offen. |
| HealthKit getrennt Read/Write, Konto A/B, Crash-Retry | iPhone + synthetische Werte | Review/Consent und Testfälle; keine realen Gesundheitsdaten in Artefakten | Offen; erster iOS-Release erfordert dies. |
| Widget, Live Activity, Shortcuts | iPhone, Dynamic-Island und Fallback soweit Hardware verfügbar | Routes, stale/logout/A→B, VoiceOver, neutrale Anzeige | Offen; erster iOS-Release erfordert dies. |
| Signierte private IPA | manueller `workflow_dispatch` | Run-ID, Commit SHA, IPA SHA-256, Entitlements/Profile-Validierung ohne Secretwerte | Offen; Signierwerte fehlen. |
| TestFlight Upload | separater freigegebener Schritt | Upload-/Buildstatus und private Testergruppe | Nicht ausgeführt, kein Upload autorisiert. |

Simulator beweist keine HealthKit-, Kamera-, Notification-, Widget-/Activity- oder Signierfunktion am Gerät. iOS 17+ ist Mindestmatrix; Gerät/OS je Nachweis protokollieren. Tests auf einem Gerät mit und ohne Dynamic Island soweit verfügbar.

## Private Beta vorbereiten (ohne Upload)

1. Team, App-/Extension-Bundle-ID, App Group und Capabilities festlegen; nur dann GitHub `ios-beta` konfigurieren.
2. Erst unsignierte CI stabilisieren; dann Profile/Entitlements/ExportOptions gegen dieselben IDs prüfen. Secrets nicht als workflow_dispatch-Eingaben verwenden und nie loggen.
3. Manuell IPA vorbereiten, eingeschränktes Artefakt mit kurzer Aufbewahrung; Run-ID, SHA, IPA-SHA256 dokumentieren.
4. Privacy-/Permission-Texte für Kamera, HealthKit Read Body Mass, HealthKit Write Workouts und Notifications vorbereiten; Denied-State prüfen.
5. TestFlight interne Beschreibung, Buildzweck, bekannte Einschränkungen, Support-/Recoveryhinweise vorbereiten. Keine Testergruppe/Verteilung bis Freigabe.
6. App Store Connect API-Key und Upload erst nach gesonderter Freigabe. Bis dahin kein Upload-Schritt im Workflow.

## Manueller Vorbereitungs-Build

1. Geprüften Commit mergen und SHA notieren; Simulator-/Dart-/Backend-/PWA-Gates müssen grün sein.
2. GitHub Actions Signing-Workflow per `workflow_dispatch` für exakten Ref starten, Modus `prepare-only`. Niemals Upload wählen.
3. Bei fehlenden Secrets/Profiles abbrechen und fehlende Namen protokollieren. Keine Ersatzwerte oder Profile committen.
4. Deployment Target, Signatur, App-/Extension-Entitlements, HealthKit, App Group und Profilzuordnung validieren. Run-ID, SHA, IPA SHA-256 notieren; Secretwerte bleiben verborgen.
5. Gerätetest durch den Nutzer erst über vereinbarten geschützten Installationsweg. Kein TestFlight Upload hier.
6. Separaten Uploadschritt erst nach Freigabe; Beta bleibt privat. Öffentliche Veröffentlichung gehört nicht zu diesem Change.

PWA bleibt bis zur nutzerweisen bestätigten Übergabe zugänglich. Recovery nach Beta-Fehler läuft über Sync, Konfliktprüfung und bestätigte Rückgabe. Keine Deinstallation als Recovery und keine PWA-Stilllegung.
