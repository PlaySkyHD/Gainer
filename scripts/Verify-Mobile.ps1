[CmdletBinding()]
param(
    [string] $FlutterSdkRoot,
    [switch] $BuildIosSimulator
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mobileRoot = Join-Path $repositoryRoot 'apps/mobile'
$toolchain = Get-Content (Join-Path $mobileRoot 'tool/toolchain.json') -Raw | ConvertFrom-Json
$expectedFlutterVersion = $toolchain.flutter.version

if ([string]::IsNullOrWhiteSpace($FlutterSdkRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GAINER_FLUTTER_SDK_ROOT)) {
        $FlutterSdkRoot = $env:GAINER_FLUTTER_SDK_ROOT
    }
    else {
        $FlutterSdkRoot = Join-Path $repositoryRoot "artifacts/flutter-sdk/$expectedFlutterVersion/flutter"
    }
}

$flutterCommand = Join-Path $FlutterSdkRoot 'bin/flutter.bat'
if ($IsMacOS -or $IsLinux) {
    $flutterCommand = Join-Path $FlutterSdkRoot 'bin/flutter'
}
if (-not (Test-Path -LiteralPath $flutterCommand -PathType Leaf)) {
    throw "Pinned Flutter SDK not found at '$flutterCommand'. Set -FlutterSdkRoot or GAINER_FLUTTER_SDK_ROOT."
}

$versionJson = & $flutterCommand --version --machine | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Flutter could not report its SDK version.'
}
if ($versionJson.channel -ne $toolchain.flutter.channel -or
    $versionJson.frameworkVersion -ne $expectedFlutterVersion -or
    $versionJson.frameworkRevision -ne $toolchain.flutter.revision -or
    $versionJson.dartSdkVersion -ne $toolchain.flutter.dartVersion) {
    throw "Flutter SDK mismatch. Required stable Flutter $expectedFlutterVersion (revision $($toolchain.flutter.revision), Dart $($toolchain.flutter.dartVersion)); found channel '$($versionJson.channel)', Flutter '$($versionJson.frameworkVersion)', revision '$($versionJson.frameworkRevision)', Dart '$($versionJson.dartSdkVersion)'."
}

Write-Host "Using verified Flutter $($versionJson.frameworkVersion) stable / Dart $($versionJson.dartSdkVersion)."
$doctorDirectory = Join-Path $repositoryRoot 'artifacts/mobile/toolchain'
New-Item -ItemType Directory -Force -Path $doctorDirectory | Out-Null
$doctorOutput = & $flutterCommand doctor --verbose 2>&1
$doctorExitCode = $LASTEXITCODE
$doctorPath = Join-Path $doctorDirectory 'flutter-doctor.txt'
$doctorOutput | Tee-Object -FilePath $doctorPath
if ($doctorExitCode -ne 0) {
    Write-Warning "flutter doctor exited $doctorExitCode. Full report saved at '$doctorPath'; this alone does not certify iOS toolchain availability."
}

function Invoke-Checked {
    param([string] $Executable, [string[]] $Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Executable $($Arguments -join ' ')"
    }
}

Push-Location $mobileRoot
try {
    Invoke-Checked $flutterCommand @('pub', 'get', '--enforce-lockfile')
    $dartCommand = Join-Path $FlutterSdkRoot 'bin/dart.bat'
    if ($IsMacOS -or $IsLinux) { $dartCommand = Join-Path $FlutterSdkRoot 'bin/dart' }
    Invoke-Checked $dartCommand @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'pigeons')
    $codegenRoot = Join-Path $repositoryRoot 'artifacts/mobile-codegen-check'
    New-Item -ItemType Directory -Force -Path $codegenRoot | Out-Null
    $candidateDart = Join-Path $codegenRoot 'mobile_platform_api.dart'
    $candidateSwift = Join-Path $codegenRoot 'MobilePlatformApi.g.swift'
    $candidateInput = Join-Path $codegenRoot 'pigeon_input.dart'
    $schema = Get-Content -LiteralPath 'pigeons/mobile_platform_api.dart' -Raw
    $schema = $schema.Replace(
        "dartOut: 'lib/data/services/platform/generated/mobile_platform_api.dart'",
        "dartOut: '$($candidateDart.Replace('\', '/'))'"
    )
    $schema = $schema.Replace(
        "swiftOut: 'ios/Runner/MobilePlatformApi.g.swift'",
        "swiftOut: '$($candidateSwift.Replace('\', '/'))'"
    )
    Set-Content -LiteralPath $candidateInput -Value $schema -NoNewline -Encoding utf8
    Invoke-Checked $dartCommand @(
        'run', 'pigeon', '--input', $candidateInput
    )
    Invoke-Checked $dartCommand @('format', $candidateDart)
    $committedDart = Join-Path $mobileRoot 'lib/data/services/platform/generated/mobile_platform_api.dart'
    $committedSwift = Join-Path $mobileRoot 'ios/Runner/MobilePlatformApi.g.swift'
    foreach ($pair in @(
            @{ Expected = $committedDart; Actual = $candidateDart },
            @{ Expected = $committedSwift; Actual = $candidateSwift }
        )) {
        if (-not (Test-Path -LiteralPath $pair.Expected -PathType Leaf)) {
            throw "Generated Pigeon binding is missing: $($pair.Expected)"
        }
        $expectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Expected).Hash
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Actual).Hash
        if ($expectedHash -ne $actualHash) {
            throw "Pigeon bindings are stale: '$($pair.Expected)'. Regenerate with the pinned toolchain and include the result."
        }
    }
    Invoke-Checked $dartCommand @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'pigeons')
    Invoke-Checked $flutterCommand @('analyze', '--fatal-infos')
    Invoke-Checked $flutterCommand @('test')

    if ($BuildIosSimulator) {
        if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [System.Runtime.InteropServices.OSPlatform]::OSX)) {
            throw 'An iOS Simulator build requires macOS and Xcode; this host is not macOS.'
        }
        $xcodePath = "/Applications/Xcode_$($toolchain.xcode.version).app/Contents/Developer"
        if (-not (Test-Path -LiteralPath $xcodePath -PathType Container)) {
            $available = & /usr/bin/xcode-select -p 2>$null
            throw "Pinned Xcode $($toolchain.xcode.version) is required at '$xcodePath'; selected Xcode is '$available'."
        }
        & /usr/bin/sudo /usr/bin/xcode-select --switch $xcodePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned Xcode installation.' }
        $xcodeVersion = & /usr/bin/xcodebuild -version
        if ($LASTEXITCODE -ne 0 -or $xcodeVersion -notcontains "Xcode $($toolchain.xcode.version)") {
            throw "Expected Xcode $($toolchain.xcode.version), found '$($xcodeVersion -join ' ')'."
        }
        if (($doctorOutput -join "`n") -notmatch '\[✓\] Xcode - develop for iOS and macOS') {
            throw "flutter doctor did not confirm its iOS/Xcode tooling. See '$doctorPath'."
        }
        Write-Host ($xcodeVersion -join "`n")
        Invoke-Checked $flutterCommand @('build', 'ios', '--simulator', '--no-codesign')
    }
}
finally {
    Pop-Location
}
