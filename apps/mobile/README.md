# Gainer Mobile

This is the iOS-first Flutter bootstrap. The tabs currently show clearly marked
work-in-progress states; they do not represent completed PWA feature parity.

## Pinned toolchain

`tool/toolchain.json` records the official Flutter stable release, Dart version,
archive SHA-256 values, iOS deployment target and pinned macOS/Xcode runner. The
Windows SDK is cached under the repository's ignored `artifacts/flutter-sdk`
directory and is deliberately separate from any preinstalled Flutter SDK.
CI downloads the matching official macOS archive and verifies its SHA-256
before use. `pubspec.lock` locks all Dart packages.

On Windows, install or extract the pinned Flutter SDK to
`artifacts/flutter-sdk/3.47.7/flutter`, then run:

```powershell
pwsh ./scripts/Verify-Mobile.ps1
```

The script rejects a non-stable channel, another Flutter revision or another
Dart version before resolving packages. It runs Dart formatting, Pigeon code
generation, analysis and widget tests. Add `-BuildIosSimulator` on macOS with
the pinned Xcode installation to include an unsigned simulator build. Windows
cannot build iOS targets.

The shell preview at `artifacts/mobile-preview/mobile-shell-390x844.png` comes
from Flutter's widget-test renderer. Its Ahem test font makes text and icons
appear as blocks, so it is useful only for checking basic layout and spacing;
typography and native appearance require a later simulator or device review.

Drift schemas use the pinned code generator. Regenerate their Dart bindings with
`dart run build_runner build --delete-conflicting-outputs` from `apps/mobile`.

The manual `Mobile CI` dispatch can produce a signed IPA for review without
uploading it to Apple. It requires an `ios-beta` GitHub Environment with
`APPLE_TEAM_ID`, `IOS_BUNDLE_ID`, `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`,
`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` and
`IOS_PROVISIONING_PROFILE_BASE64`. Missing or mismatched signing data fails
before archiving. Configure environment reviewer protection in GitHub settings
if the repository plan supports it; the workflow does not imply that such
protection is enabled.

## Architecture boundary

The Cupertino shell is driven by `MobileShellViewModel` and provided with
Provider. Network, persistence and Apple system services belong in injected
services/repositories. Typed platform ports live under
`lib/data/services/platform`; Pigeon schema changes belong in
`pigeons/mobile_platform_api.dart` and generated bindings must be regenerated
with the pinned Pigeon version. No platform adapter or feature journey is
implemented by this bootstrap.
