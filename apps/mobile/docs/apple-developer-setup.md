# Apple Developer für Gainer Mobile einrichten

Diese Anleitung richtet den manuellen Signier-Build `ios-beta` ein. Er lädt
nichts zu App Store Connect oder TestFlight hoch. Das Repository ist öffentlich;
ein signiertes IPA-Artefakt kann deshalb für Repository-Leser herunterladbar
sein. Vor einem signierten Lauf muss der mögliche Download des IPA durch
Repository-Leser geklärt sein.

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
5. Unter [App Store Connect → Apps](https://appstoreconnect.apple.com/apps) auf
   **+ → New App** gehen: Plattform **iOS**, Name **Gainer**, Primärsprache
   **German**, Bundle ID `xyz.markfort.gainer`, SKU `gainer-ios`. Das ist der
   App-Eintrag; für das Widget keinen separaten Eintrag anlegen.

Die App nutzt HealthKit für Körpergewicht-Lesezugriff und ausdrücklich
bestätigte Workout-Schreibvorgänge. **Clinical Records** und **Background
Delivery** werden nicht benötigt. **Keychain Sharing** ist nicht nötig. Die aktuelle
Live-Activity verwendet keinen zusätzlichen Push- oder Background-Mode-Schalter.
Das Widget liest nur neutrale App-Group-Snapshots; HealthKit, Push, Background
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
auf `main` und manuelle Freigabe durch `PlaySkyHD` beibehalten. Die Base64-Werte
werden als Environment-Secrets eingetragen, nie als Workflow-Inputs. Mapping:
P12 → `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`, App-Profil →
`IOS_PROVISIONING_PROFILE_BASE64`, Widget-Profil →
`IOS_WIDGET_PROVISIONING_PROFILE_BASE64`; die P12-Passphrase kommt separat in
`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`. `ExportOptions.plist` erstellt CI aus
den geprüften Profilnamen; dafür gibt es weder Secret noch Base64-Upload.

| Secret | Wert |
|---|---|
| `APPLE_TEAM_ID` | `Q7GTYQ282F` (vorher im Portal verifizieren) |
| `IOS_BUNDLE_ID` | `xyz.markfort.gainer` |
| `IOS_WIDGET_BUNDLE_ID` | `xyz.markfort.gainer.Widgets` |
| `IOS_APP_GROUP_ID` | `group.xyz.markfort.gainer` |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Base64 des geschützten P12 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | P12-Exportpassphrase |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64 des App-Profils |
| `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` | Base64 des Widget-Profils |

Der Workflow prüft Team, Bundle-IDs, exakte App-Group-Mitgliedschaft in beiden
Profilen und das aktivierte HealthKit-Entitlement der App vor dem Archivieren.
`GAINER_API_ORIGIN` und `GAINER_TRUSTED_FRONTEND_ORIGIN` sind nicht geheim und
verwenden standardmäßig `https://gainer.markfort.xyz`; bei Änderung müssen es
weiterhin reine HTTPS-Ursprünge ohne Pfad oder Zugangsdaten sein.

Der signierte Lauf startet ausschließlich manuell von `main`, nachdem die
unsignierte Simulator-CI erfolgreich war. Er erzeugt ein IPA-Artefakt, hat
aber keinen Upload-Schritt. Ein App-Store-Connect-API-Key wird erst für einen
separaten, später freizugebenden TestFlight-Upload benötigt. Ein App-Store-IPA
ist kein direkter Installationsweg auf das iPhone; vor einem Gerätetest muss
ein eigener Verteilungsweg wie TestFlight eingerichtet und freigegeben werden.

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
