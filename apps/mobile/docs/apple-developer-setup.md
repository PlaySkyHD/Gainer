# Apple Developer für Gainer Mobile einrichten

Diese Anleitung richtet den manuellen Signier-Build `ios-beta` und den optionalen
TestFlight-Upload ein. Ein Upload wird nur durch die zusätzliche manuelle
`upload_testflight`-Auswahl auf `main` ausgelöst. Das Repository ist öffentlich;
ein signiertes IPA-Artefakt kann deshalb für Repository-Leser herunterladbar
sein. Der TestFlight-Pfad legt kein IPA-Artefakt ab.

Der Nutzer meldet ein bezahltes individuelles Apple-Developer-Konto mit Team-ID
`Q7GTYQ282F` sowie ein iPhone 15 Pro mit iOS 26.6.2. Team-ID und Gerätenachweis
im Portal bzw. am Gerät prüfen. Die folgenden Kennungen sind vorgeschlagen,
aber noch nicht registriert oder verifiziert:

| Zweck | Kennung |
|---|---|
| Apple Developer Team | `Q7GTYQ282F` (Nutzerangabe) |
| App | `xyz.markfort.gainer` |
| Widget-Erweiterung | `xyz.markfort.gainer.Widgets` |
| App Group | `group.xyz.markfort.gainer` |

Das Widget ist eine Erweiterung der App; dafür wird kein eigener App-Store-
Connect-App-Eintrag angelegt. Aktuelle Xcode-Simulatorwerte sind Beispiele.

## Kennungen und Fähigkeiten im Apple-Portal

Öffne [Apple Developer – Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) und prüfe zuerst die Team-ID. Apple beschreibt [App-ID-Registrierung](https://developer.apple.com/help/account/identifiers/register-an-app-id/), [App-Group-Registrierung](https://developer.apple.com/help/account/identifiers/register-an-app-group), [Capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/) und [App-Store-Connect-Profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile) im Detail.

1. Unter **Identifiers → + → App Groups** die App Group
   `group.xyz.markfort.gainer` registrieren.
2. Unter **Identifiers → + → App IDs → Continue** die explizite App-ID
   `xyz.markfort.gainer` erstellen und mit **Register** abschließen. Danach die
   ID erneut öffnen, **App Groups → Configure** auswählen, die zuvor angelegte
   Gruppe markieren, über **Continue → Assign** zuordnen und speichern.
3. Ebenso die explizite Erweiterungs-ID `xyz.markfort.gainer.Widgets` erstellen
   und registrieren. Danach erneut öffnen, unter **App Groups → Configure**
   dieselbe Gruppe markieren und mit **Continue → Assign** speichern.
4. Bei der Haupt-App-ID `xyz.markfort.gainer` **HealthKit** aktivieren. **Clinical Records**
   und **Background Delivery** ausgeschaltet lassen.
5. Unter [App Store Connect → Apps](https://appstoreconnect.apple.com/apps)
   prüfen, dass bereits ein App-Eintrag mit Bundle ID `xyz.markfort.gainer`
   existiert. Nur falls er fehlt, **+ → New App** wählen: Plattform **iOS**,
   Name **Gainer**, Primärsprache **German**, Bundle ID
   `xyz.markfort.gainer`, SKU `gainer-ios`. Für das Widget keinen separaten
   Eintrag anlegen.

Die App nutzt HealthKit für Körpergewicht-Lesezugriff und ausdrücklich
bestätigte Workout-Schreibvorgänge. **Clinical Records** und **Background
Delivery** werden nicht benötigt. **Keychain Sharing** ist nicht nötig. Die aktuelle
Live-Activity verwendet keinen zusätzlichen Push- oder Background-Mode-Schalter.
Das Widget zeigt neutrale Einstiege; die Haupt-App hält neutrale App-Group-Snapshots bereit. HealthKit, Push, Background
Modes und Keychain Sharing bleiben beim Widget aus. Für Kamera/Fotoauswahl,
lokale Mitteilungen und App Intents ist keine zusätzliche Portal-Capability nötig.

Für die geplanten Universal Links kann **Associated Domains** auf der Haupt-
App-ID aktiviert werden; nicht auf der Widget-ID. Die App-Entitlement-,
Domain- und AASA-Konfiguration samt Installationsnachweis steht noch aus.
Das Aktivieren im Portal allein schaltet Universal Links nicht frei.

## Apple-Distribution-Zertifikat unter Windows mit Git Bash

Git Bash ist der primäre Ablauf, da dort die OpenSSL-Kommandosyntax aus dem
bisherigen Arbeitsverlauf passt. Verwende eine vertrauenswürdige
OpenSSL-Installation und prüfe `openssl version`; OpenSSL muss nicht bereits
installiert sein. Arbeite in einem geschützten Verzeichnis außerhalb des
Repositories, zum Beispiel `$HOME/AppleSigning/Gainer`. Lege einen neuen
Arbeitsordner an, beschränke dessen Windows-ACL auf dein Benutzerkonto und
prüfe vor jedem Befehl, dass die Zieldatei noch nicht existiert. So bleiben
vorhandene Schlüssel und Profile unangetastet. Schlüssel, CSR, Zertifikat,
P12 und Profile gehören nie in Git, CI-Artefakte oder Chat.

Im neuen Ordner einen verschlüsselten RSA-2048-Schlüssel erzeugen. OpenSSL
fragt interaktiv nach einer starken Schlüssel-Passphrase. Die CSR verwendet
Platzhalter: `YOUR_EMAIL` und `YOUR_NAME` nur lokal ersetzen, nicht im
Repository eintragen.

```bash
set -euo pipefail
mkdir -p "$HOME/AppleSigning/Gainer"
signing_dir="$HOME/AppleSigning/Gainer/ios-$(date +%Y%m%d-%H%M%S)"
mkdir "$signing_dir"
cd "$signing_dir"
openssl genrsa -aes256 -out ios_distribution.key 2048
MSYS_NO_PATHCONV=1 openssl req -new -sha256 \
  -key ios_distribution.key \
  -out distribution.csr \
  -subj "/emailAddress=YOUR_EMAIL/CN=YOUR_NAME/C=DE"
```

`MSYS_NO_PATHCONV=1` verhindert, dass Git Bash den slash-formatierten `-subj`
Wert als lokalen Pfad umschreibt. MSYS2-Umgebungen unterstützen dafür auch
`MSYS2_ARG_CONV_EXCL='*'`; Details stehen in der [Git-for-Windows-Historie](https://github.com/git-for-windows/build-extra/blob/main/ReleaseNotes.md?plain=1) und der [MSYS2-Pfaddokumentation](https://www.msys2.org/docs/filesystem-paths/).

Im Developer-Portal unter **Certificates → + → Apple Distribution** die CSR
hochladen und das DER-Zertifikat `distribution.cer` herunterladen. Zertifikat
umwandeln und ein P12 mit dem Anzeigenamen **Apple Distribution** exportieren:

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export \
  -inkey ios_distribution.key \
  -in distribution.pem \
  -out distribution.p12 \
  -name "Apple Distribution"
```

OpenSSL fragt interaktiv nach Schlüssel-Passphrase und neuer P12-Exportpassphrase.
Verwende ein neues, starkes Passwort und gib es nicht als `-passout`-Argument
an.
Die P12-Passphrase kommt in `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` und wird
direkt als GitHub-Secret eingetragen. Wird ein neues P12 exportiert, müssen die
Secrets `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` und
`IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` gemeinsam auf das zusammengehörige
neue Passwort und P12 aktualisiert werden.

Base64 ohne Zeilenumbrüche direkt in die Windows-Zwischenablage kopieren, ohne
den Wert im Terminal auszugeben oder eine zweite Datei anzulegen:

```bash
base64 -w0 distribution.p12 | clip.exe
```

Als `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` speichern und die Zwischenablage
leeren. Referenzen: OpenSSL [genrsa](https://docs.openssl.org/3.6/man1/openssl-genrsa/),
[req](https://docs.openssl.org/3.6/man1/openssl-req/) und
[pkcs12](https://docs.openssl.org/3.6/man1/openssl-pkcs12/).

Ein bestehendes Apple-Distribution-Zertifikat kann nur wiederverwendet werden,
wenn sein privater Schlüssel dazu passt, das Zertifikat zur selben Team-ID
gehört und noch gültig ist. Das lässt sich lokal prüfen, ohne den privaten
Schlüssel auszugeben. Ersetze im folgenden Beispiel `ios_distribution.key` und
`distribution.pem` durch die tatsächlichen Dateinamen des vorhandenen
Schlüssels und des zugehörigen PEM-Zertifikats:

```bash
openssl pkey -in ios_distribution.key -pubout | openssl sha256
openssl x509 -in distribution.pem -pubkey -noout | openssl sha256
openssl x509 -in distribution.pem -noout -subject -issuer -dates
```

Die beiden Hashes müssen identisch sein. Bei anderer Team-ID, abgelaufenem
Zertifikat oder abweichenden Hashes ein neues Zertifikat samt Schlüssel anlegen.

### PowerShell-Alternative

Prüfe `openssl version` und arbeite im gleichen geschützten Ordner außerhalb
des Repositories. `req -newkey` fragt interaktiv nach einer verschlüsselten
Privatkey-Passphrase. Nur in einem frischen Ordner ausführen, damit vorhandene
Dateien nicht überschrieben werden:

```powershell
openssl req -new -newkey rsa:2048 -sha256 `
  -keyout ios_distribution.key `
  -out distribution.csr `
  -subj "/emailAddress=YOUR_EMAIL/CN=YOUR_NAME/C=DE"
```

Lade `distribution.csr` im Apple-Portal hoch, lade das ausgestellte
`distribution.cer` herunter und führe dann im selben Ordner aus:

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export `
  -inkey ios_distribution.key `
  -in distribution.pem `
  -out distribution.p12 `
  -name "Apple Distribution"
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\distribution.p12))) | Set-Clipboard
```

OpenSSL fragt beim P12-Export interaktiv nach dem neuen Passwort. Zwischenablage
direkt als `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` speichern und leeren. Das
Passwort muss zugleich das Secret `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` sein.

CI prüft vor dem Import die P12-Integritäts-MAC. Für Apples Keychain wird eine
kompatible Kopie mit 3DES/SHA-1 erstellt; der private Schlüssel liegt dafür nur
verschlüsselt in einer kurzlebigen Datei mit restriktiven Rechten. Eine fehlende
oder ungültige MAC führt zum Abbruch. Die GitHub-Secrets werden dabei nicht
umgeschrieben; eine gültige Quelle muss nicht manuell neu exportiert werden.

## Zwei App-Store-Profile und GitHub-Environment

Unter **Profiles → +** zwei neue **App Store Connect**-Profile mit dem Apple
Distribution-Zertifikat erstellen: ein App-Profil für `xyz.markfort.gainer`
mit HealthKit und App Group, sowie ein Erweiterungsprofil für
`xyz.markfort.gainer.Widgets` mit App Group. Die App Group braucht keinen
Team-ID-Präfix. Profile aus früheren Tests, insbesondere Profile für die
MCP-App oder andere Bundle-IDs, passen nicht; beide Gainer-Profile mit den oben
registrierten IDs und Capabilities neu erzeugen. Das Widget ist kein eigener
App-Store-Connect-Eintrag.

Jedes `.mobileprovision` geschützt speichern und ohne Ausgabe direkt in die
Zwischenablage Base64-kodieren. Git Bash für das App-Profil:

```bash
base64 -w0 gainer-app.mobileprovision | clip.exe
```

Für das Widget-Profil:

```bash
base64 -w0 gainer-widget.mobileprovision | clip.exe
```

PowerShell-Alternative für jedes Profil:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\gainer-app.mobileprovision))) | Set-Clipboard
```

App-Profil: `IOS_PROVISIONING_PROFILE_BASE64`; Widget-Profil:
`IOS_WIDGET_PROVISIONING_PROFILE_BASE64`. Nach jedem Speichern Zwischenablage
leeren.

In GitHub **Settings → Environments → ios-beta** die vorhandene Beschränkung
auf `main` und manuelle Freigabe durch `PlaySkyHD` beibehalten. Die vier
öffentlichen Kennungen sind Environment-Variablen; nur die vier
Signiermaterialien werden als Environment-Secrets eingetragen. Nichts davon als
Workflow-Input übermitteln.

| Typ | Name | Wert |
|---|---|---|
| Variable | `APPLE_TEAM_ID` | `Q7GTYQ282F` |
| Variable | `IOS_BUNDLE_ID` | `xyz.markfort.gainer` |
| Variable | `IOS_WIDGET_BUNDLE_ID` | `xyz.markfort.gainer.Widgets` |
| Variable | `IOS_APP_GROUP_ID` | `group.xyz.markfort.gainer` |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Base64 des geschützten P12 |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Neue P12-Exportpassphrase |
| Secret | `IOS_PROVISIONING_PROFILE_BASE64` | Base64 des App-Profils |
| Secret | `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` | Base64 des Widget-Profils |

`ExportOptions.plist` erstellt CI aus den geprüften Profilnamen; dafür gibt es
weder Secret noch Base64-Upload.

Der Workflow prüft Team, Bundle-IDs, exakte App-Group-Mitgliedschaft in beiden
Profilen und das aktivierte HealthKit-Entitlement der App vor dem Archivieren.
`GAINER_API_ORIGIN` ist nicht geheim und verwendet standardmäßig
`https://gainer.markfort.xyz`; bei Änderung muss es weiterhin ein reiner
HTTPS-Ursprung ohne Pfad oder Zugangsdaten sein.

Der signierte Lauf startet ausschließlich manuell von `main`, nachdem die
unsignierte Simulator-CI erfolgreich war und `ios-beta` manuell freigegeben
wurde. `build_signed_ipa` erzeugt ein IPA-Artefakt zur Prüfung. `upload_testflight`
impliziert denselben Build und lädt ihn nach erfolgreicher lokaler
Identitätsprüfung an App Store Connect hoch; in diesem Modus wird kein
öffentliches IPA-Artefakt abgelegt. Keine Variante reicht die App zur
öffentlichen Store-Prüfung ein oder lädt Tester ein.

Die Marketing-Version kommt aus `apps/mobile/pubspec.yaml`. Ohne manuellen
Override setzt CI die CFBundleVersion auf `GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`;
Runner-App und Widget erhalten dieselben Werte. Wenn der App-Eintrag bereits
eine höhere Buildnummer hat oder ein anderer Buildweg Nummern verbraucht hat,
`build_number` im manuellen Dispatch auf eine bisher unbenutzte Apple-konforme
Nummer setzen. GitHub kann keine von anderen Buildwegen verbrauchten Nummern
erkennen; App Store Connect akzeptiert eine Buildnummer nicht erneut. Ein
Upload-Erfolg bedeutet nur, dass Apple den Upload angenommen hat. Die
Verarbeitung kann noch ausstehen, bevor der Build in TestFlight erscheint.

## App Store Connect API-Schlüssel für TestFlight

Der App-Eintrag `xyz.markfort.gainer` muss bereits in App Store Connect
existieren. Erzeuge für diesen CI-Upload eine **Team API Key** mit Rolle
**Developer**. Eine Team-Key-Erstellung erfordert laut Apple Account Holder
oder Admin; bei einem individuellen Konto ist das der Account Holder. Die Rolle
Developer genügt zum Upload und lässt die Rechte enger als Admin. Eine
Individual API Key hat keine Issuer ID und passt deshalb nicht zum hier
verwendeten Team-Key-Upload.

1. Melde dich bei [App Store Connect](https://appstoreconnect.apple.com/) an.
   Unter **Users and Access → Integrations → App Store Connect API** muss der
   Account Holder den API-Zugang einmalig beantragen, falls er noch nicht
   aktiviert wurde.
2. Öffne **Users and Access → Integrations → App Store Connect API → Team Keys**.
   Erzeuge einen Schlüssel namens `Gainer TestFlight CI` und wähle als Rolle
   **Developer**.
3. Notiere die angezeigte **Key ID** und die **Issuer ID** auf der API-Seite.
   Lade die `.p8`-Datei genau einmal herunter und speichere sie vorübergehend
   geschützt. Team Keys gelten kontoweit für alle Apps; die gewählte Rolle
   begrenzt die erlaubten Aktionen, nicht den App-Umfang. Apple bewahrt den
   privaten Teil nicht erneut zum Download auf.
4. In GitHub **Settings → Environments → ios-beta** die drei Werte als
   Environment-Secrets anlegen. `APP_STORE_CONNECT_PRIVATE_KEY` enthält den
   unveränderten mehrzeiligen Inhalt der `.p8`-Datei, einschließlich PEM-
   Kopf- und Fußzeile. Bewahre eine verschlüsselte Offline-Sicherung der
   einmalig ladbaren Datei auf; entferne unnötige Arbeitskopien nach dem
   Eintragen und Prüfen der Secrets. Die Datei gehört nie in Git oder Chat.

| Secret | Wert |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | Team API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID aus App Store Connect API |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Unveränderter PEM-Inhalt der einmalig heruntergeladenen `.p8`-Datei |

Der Workflow prüft diese Eingaben nur, wenn `upload_testflight` gewählt ist.
Vor dem Aufruf von `altool` prüft er die IDs, Version, Buildnummer und
Signatur des IPA auf die erwartete App, Widget und Team-ID. Die `.p8`-Datei
liegt nur während des Uploadschritts in einem zugriffsbeschränkten Verzeichnis
des kurzlebigen macOS-Runners und wird dort bereinigt. Sie wird weder
gecached noch als Artefakt hochgeladen oder ausgegeben.

Zum Starten in GitHub **Actions → Mobile CI → Run workflow** auf `main`:

- `upload_testflight = true` für Build und Upload; dadurch muss
  `build_signed_ipa` nicht zusätzlich aktiviert werden.
- `build_number` leer lassen für die CI-Nummer oder nur dann manuell setzen,
  wenn App Store Connect bereits höhere/anderweitig verwendete Builds kennt.

Der bestehende Environment-Schutz verlangt weiterhin die manuelle Freigabe
durch `PlaySkyHD`. Der Upload startet keine App-Review und ändert keine
TestFlight-Testergruppe. Nach dem Upload muss die Verarbeitung in App Store
Connect abgeschlossen sein; anschließend kann der Kontoinhaber den Build
manuell einer internen Testgruppe zuweisen. Tester-Einladung und Verteilung
bleiben außerhalb dieses Workflows.

## Export-Compliance für den geprüften Build

Der API-Transport läuft über Dio und `dart:io` mit der im Dart-SDK enthaltenen
BoringSSL-TLS-Implementierung. `CryptoKit.SHA256` wird zusätzlich nur zum
Hashen interner Kennungen verwendet; eine eigene Verschlüsselung von App- oder
SQLite-Daten wurde im aktuellen Build nicht gefunden. Deshalb ist die Antwort
nicht „keine Verschlüsselung“ oder „ausschließlich Apple-OS-Verschlüsselung“:
der HTTPS-Pfad verwendet standardisiertes TLS aus einer Drittanbieter-
Implementierung.

Wähle im Export-Compliance-Dialog für den bereits hochgeladenen Build **34.1**
die Kategorie für einen Standardalgorithmus außerhalb des Apple-Betriebssystems.
Beantworte die Frage zur Verfügbarkeit in Frankreich entsprechend der
bestätigten Vertriebsplanung; derzeit ist keine Veröffentlichung in Frankreich
vorgesehen. Diese Dokumentation ändert weder die Store-Verfügbarkeit noch den
bereits hochgeladenen Build 34.1. Das `Info.plist`-Kennzeichen
`ITSAppUsesNonExemptEncryption = false` gilt für künftig erstellte Builds. Es
bedeutet, dass für die aktuelle Verschlüsselungs- und Markt-Konfiguration keine
nicht ausgenommene Verschlüsselung deklariert wird; es bedeutet nicht, dass die
App gar keine Verschlüsselung nutzt. Bei zusätzlicher Kryptografie oder einer
späteren Veröffentlichung in Frankreich die Einordnung in App Store Connect
erneut prüfen, bevor der Build verteilt wird.

Apple-Referenzen: [`ITSAppUsesNonExemptEncryption`](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption),
[Export-Compliance-Übersicht](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance),
[Dokumente nach Algorithmus und Frankreich-Verfügbarkeit](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption),
[Dart 3.13.5 TLS-Implementierung](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/bin/security_context.cc),
[Dart-SDK-Abhängigkeiten](https://github.com/dart-lang/sdk/blob/3.13.5/DEPS),
[Dio nativer HTTP-Adapter](https://pub.dev/documentation/dio/5.11.1/dio/).

Prüfe nach der Verarbeitung auch die Beta-Testinformationen in App Store
Connect. Die mitgelieferten
Privacy-Manifeste deklarieren die nachgewiesenen nativen API-Nutzungsgründe;
sie ersetzen nicht die Angaben zu Konto-, Gesundheits- und Bilddaten oder die
Prüfung der eingebundenen SDKs. Die physische iPhone-Abnahme bleibt offen.

Apple-Referenzen: [API-Zugang und Team-/Individual-Schlüssel](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/),
[API-Key-Erstellung und Schutz](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api),
[Build hochladen und verarbeiten](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/),
[CFBundleVersion-Regeln](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleVersion).

## Android-Keystore für einen späteren Android-Build

Der iOS-Workflow braucht keinen Android-Keystore. Falls Android später
hinzukommt, den Upload-Keystore mit `keytool` separat in einem geschützten
Verzeichnis außerhalb des Repositories erzeugen. Keystore-Passphrase und
Zertifikatsdaten interaktiv eingeben. Den privaten JKS sicher sichern und
niemals veröffentlichen.

```bash
keytool -genkeypair -v \
  -keystore gainer-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias gainer-upload
keytool -exportcert -rfc \
  -keystore gainer-upload.jks \
  -alias gainer-upload \
  -file gainer-upload-cert.pem
```

Der öffentliche Zertifikats-Export ersetzt den privaten Keystore nicht.
Android-Signierung und Play-Upload sind ein eigener späterer Schritt; der
aktuelle iOS-Workflow verwendet diese Dateien nicht.
