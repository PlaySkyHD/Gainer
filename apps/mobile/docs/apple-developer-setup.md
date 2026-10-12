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

## Apple-Distribution-Zertifikat unter Windows

Eine vertrauenswürdige OpenSSL-Installation ist nötig; sie ist nicht zwingend
vorhanden. In PowerShell mit `openssl version` prüfen. Schlüssel und Profile
außerhalb des Repositories aufbewahren, etwa in einem nur für den Nutzer
zugänglichen Ordner `C:\Users\<du>\AppleSigning\Gainer`, und dessen ACLs
einschränken. Niemals Schlüssel, CSR, Zertifikat, P12 oder Profile in Git,
Artefakte oder Chat legen.

Im geschützten Ordner erzeugt der folgende Befehl einen verschlüsselten
Privatschlüssel und CSR. OpenSSL fragt interaktiv nach einer starken
Schlüssel-Passphrase; `-nodes` oder `-passout` nicht verwenden.

```powershell
openssl req -new -newkey rsa:2048 -sha256 `
  -keyout gainer_distribution_private_key.pem `
  -out gainer_distribution.csr
```

Im Developer-Portal unter **Certificates → + → Apple Distribution** den CSR
hochladen und das `.cer` in denselben geschützten Ordner herunterladen. Dann
DER-Zertifikat in PEM umwandeln und ein passwortgeschütztes P12 erzeugen:

```powershell
openssl x509 -inform DER -in apple_distribution.cer -out apple_distribution.pem
openssl pkcs12 -export `
  -inkey gainer_distribution_private_key.pem `
  -in apple_distribution.pem `
  -out gainer_distribution.p12
```

OpenSSL fragt nach Schlüssel- und P12-Passphrase. Sicher aufbewahren. Die
P12-Passphrase gehört in `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`. P12 ohne
Ausgabe direkt in die Zwischenablage Base64-kodieren:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\gainer_distribution.p12))) | Set-Clipboard
```

Den Inhalt direkt als `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` speichern und
danach die Zwischenablage leeren.

## Zwei App-Store-Profile und GitHub-Environment

Unter **Profiles → +** zwei **App Store Connect**-Profile mit dem Apple
Distribution-Zertifikat erstellen: ein App-Profil für `xyz.markfort.gainer`
mit HealthKit und App Group, sowie ein Erweiterungsprofil für
`xyz.markfort.gainer.Widgets` mit App Group. Die App Group braucht keinen
Team-ID-Präfix. Das Widget ist kein eigener App-Store-Connect-Eintrag.

Jedes `.mobileprovision` geschützt speichern und ohne Ausgabe direkt in die
Zwischenablage Base64-kodieren:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\gainer-app.mobileprovision))) | Set-Clipboard
```

App-Profil: `IOS_PROVISIONING_PROFILE_BASE64`; Widget-Profil:
`IOS_WIDGET_PROVISIONING_PROFILE_BASE64`. Nach jedem Speichern Zwischenablage
leeren.

In GitHub **Settings → Environments → ios-beta** die vorhandene Beschränkung
auf `main` und manuelle Freigabe durch `PlaySkyHD` beibehalten. Folgende Werte
als Environment-Secrets eintragen, nie als Workflow-Inputs:

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
