[CmdletBinding()]
param(
    [string] $FlutterSdkRoot,
    [ValidateSet('All', 'Toolchain', 'FlutterChecks', 'IosBuild', 'SimulatorBoot', 'NativeTests')]
    [string] $Phase = 'All',
    [string] $RepositoryRoot,
    [switch] $BuildIosSimulator
)

$ErrorActionPreference = 'Stop'
if ($BuildIosSimulator -and $Phase -ne 'All') {
    throw '-BuildIosSimulator is supported only with the default All phase.'
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    # This default is correct when this candidate replaces scripts/Verify-Mobile.ps1.
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$repositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$mobileRoot = Join-Path $repositoryRoot 'apps/mobile'
$toolchainPath = Join-Path $mobileRoot 'tool/toolchain.json'
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
$expectedFlutterVersion = $toolchain.flutter.version
$runToken = if ($env:GITHUB_RUN_ID) {
    "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
}
else {
    "local-$PID"
}
$runStateRoot = Join-Path $repositoryRoot 'artifacts/mobile/phase-state'
$doctorStatePath = Join-Path $runStateRoot 'doctor-status.json'
$simulatorStatePath = Join-Path $runStateRoot 'simulator-status.json'

if ([string]::IsNullOrWhiteSpace($FlutterSdkRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GAINER_FLUTTER_SDK_ROOT)) {
        $FlutterSdkRoot = $env:GAINER_FLUTTER_SDK_ROOT
    }
    else {
        $FlutterSdkRoot = Join-Path $repositoryRoot "artifacts/flutter-sdk/$expectedFlutterVersion/flutter"
    }
}

$flutterCommand = Join-Path $FlutterSdkRoot 'bin/flutter.bat'
$dartCommand = Join-Path $FlutterSdkRoot 'bin/dart.bat'
if ($IsMacOS -or $IsLinux) {
    $flutterCommand = Join-Path $FlutterSdkRoot 'bin/flutter'
    $dartCommand = Join-Path $FlutterSdkRoot 'bin/dart'
}

function Write-PhaseStart {
    param([string] $Name)
    $script:CurrentPhase = $Name
    $script:PhaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "PHASE START name=$Name utc=$([DateTime]::UtcNow.ToString('o'))"
}

function Write-PhaseEnd {
    param([string] $Name)
    $script:PhaseTimer.Stop()
    Write-Host "PHASE END name=$Name utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($script:PhaseTimer.Elapsed.TotalSeconds, 2))"
    $script:CurrentPhase = $null
}

function Invoke-Phase {
    param([string] $Name, [scriptblock] $Action)
    Write-PhaseStart $Name
    try {
        & $Action
    }
    finally {
        Write-PhaseEnd $Name
    }
}

function Invoke-Checked {
    param([string] $Executable, [string[]] $Arguments)
    $label = "$Executable $($Arguments -join ' ')"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "COMMAND START phase=$script:CurrentPhase utc=$([DateTime]::UtcNow.ToString('o')) command=$label"
    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    $timer.Stop()
    Write-Host "COMMAND END phase=$script:CurrentPhase utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($timer.Elapsed.TotalSeconds, 2)) exit_code=$exitCode command=$label"
    if ($exitCode -ne 0) {
        throw "Command failed ($exitCode): $label"
    }
}

function Stop-ManagedProcessTree {
    param([Parameter(Mandatory)][System.Diagnostics.Process] $Process)
    try { $Process.Kill($true) } catch { return $false }
    return $Process.WaitForExit(5000) -and $Process.HasExited
}

function Wait-ManagedOutputDrain {
    param([Parameter(Mandatory)][System.Threading.Tasks.Task[]] $Tasks, [int] $TimeoutMilliseconds = 3000)
    try { return [System.Threading.Tasks.Task]::WaitAll($Tasks, $TimeoutMilliseconds) }
    catch { return $false }
}

function Invoke-ManagedProcess {
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][string] $Label
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "MANAGED COMMAND START utc=$([DateTime]::UtcNow.ToString('o')) label=$Label timeout_seconds=$TimeoutSeconds"
    try {
        if (-not $process.Start()) { throw "Could not start managed command '$Label'." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        $timedOut = -not $completed
        $terminationConfirmed = $true
        if ($timedOut) {
            Write-Warning "Managed command timed out; terminating only its process tree: $Label"
            $terminationConfirmed = Stop-ManagedProcessTree $process
        }
        $exited = $process.HasExited
        if ($exited) { [void]$process.WaitForExit(1000) }
        $drainConfirmed = Wait-ManagedOutputDrain @($stdoutTask, $stderrTask) 3000
        $timer.Stop()
        $outText = if ($stdoutTask.IsCompleted) { $stdoutTask.GetAwaiter().GetResult() } else { '' }
        $errText = if ($stderrTask.IsCompleted) { $stderrTask.GetAwaiter().GetResult() } else { '' }
        if ($outText) { Write-Host "MANAGED STDOUT BEGIN label=$Label`n$outText`nMANAGED STDOUT END label=$Label" }
        if ($errText) { Write-Host "MANAGED STDERR BEGIN label=$Label`n$errText`nMANAGED STDERR END label=$Label" }
        $exitCode = if ($exited) { $process.ExitCode } else { $null }
        Write-Host "MANAGED COMMAND END utc=$([DateTime]::UtcNow.ToString('o')) label=$Label elapsed_seconds=$([Math]::Round($timer.Elapsed.TotalSeconds, 2)) timed_out=$timedOut exit_code=$exitCode termination_confirmed=$terminationConfirmed output_drained=$drainConfirmed"
        return [pscustomobject]@{ TimedOut = $timedOut; ExitCode = $exitCode; TerminationConfirmed = $terminationConfirmed; OutputDrained = $drainConfirmed; Stdout = $outText; Stderr = $errText }
    }
    finally { $process.Dispose() }
}

function Get-VerifiedSimulatorInventoryEntry {
    param(
        [Parameter(Mandatory)][string] $XcrunPath,
        [Parameter(Mandatory)][string] $SimulatorId,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][string] $Label,
        [string[]] $ExecutablePrefixArguments = @()
    )
    $inventoryArguments = @($ExecutablePrefixArguments) + @('simctl', 'list', 'devices', 'available', '--json')
    $query = Invoke-ManagedProcess $XcrunPath $inventoryArguments $TimeoutSeconds $Label
    if ($query.TimedOut -or -not $query.TerminationConfirmed -or -not $query.OutputDrained -or $query.ExitCode -ne 0) { throw "Could not obtain simulator inventory ($Label)." }
    try { $inventory = $query.Stdout | ConvertFrom-Json } catch { throw "Simulator inventory was invalid JSON ($Label)." }
    foreach ($runtime in $inventory.devices.PSObject.Properties) {
        foreach ($device in $runtime.Value) {
            if ([string]$device.udid -eq $SimulatorId) {
                return [pscustomobject]@{ RuntimeIdentifier = [string]$runtime.Name; Device = $device }
            }
        }
    }
    return $null
}

function Assert-OwnedSimulatorRecord {
    param(
        [Parameter(Mandatory)][string] $StatePath,
        [Parameter(Mandatory)][string] $RunToken,
        [Parameter(Mandatory)][string] $SimulatorId,
        [Parameter(Mandatory)][string] $SimulatorName,
        [Parameter(Mandatory)][string] $RuntimeIdentifier
    )
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw 'Owned simulator state record is missing; refusing boot retry.' }
    $record = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ($record.runToken -ne $RunToken -or $record.owned -ne $true -or
        $record.simulatorId -ne $SimulatorId -or $record.simulatorName -ne $SimulatorName -or
        $record.runtimeIdentifier -ne $RuntimeIdentifier -or $SimulatorName -ne "Gainer-CI-$RunToken" -or
        $SimulatorId -notmatch '^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') {
        throw 'Simulator ownership record does not match this workflow run; refusing boot retry.'
    }
}

function Invoke-CiSimulatorBootStatus {
    param(
        [Parameter(Mandatory)][string] $XcrunPath,
        [Parameter(Mandatory)][string] $RunToken,
        [Parameter(Mandatory)][string] $StatePath,
        [Parameter(Mandatory)][string] $SimulatorId,
        [Parameter(Mandatory)][string] $SimulatorName,
        [Parameter(Mandatory)][string] $RuntimeIdentifier,
        [int] $FirstAttemptSeconds = 180,
        [int] $RetryMaximumSeconds = 60,
        [int] $InternalBudgetSeconds = 270,
        [int] $InventoryTimeoutSeconds = 10,
        [string[]] $ExecutablePrefixArguments = @(),
        [int] $MinimumRetrySeconds = 10,
        [int] $MinimumFirstAttemptSeconds = 30
    )
    $phaseClock = [System.Diagnostics.Stopwatch]::StartNew()
    # Each timed-out client may use up to 5s to confirm process-tree termination
    # and 3s to drain redirected streams. Reserve that cleanup time per client.
    $processCleanupReserve = 8
    $inventoryWorstCase = $InventoryTimeoutSeconds + $processCleanupReserve
    $firstReserve = (2 * $inventoryWorstCase) + $MinimumRetrySeconds + (2 * $processCleanupReserve)
    $firstLimit = [Math]::Min($FirstAttemptSeconds, $InternalBudgetSeconds - $firstReserve)
    Write-Host "SIMULATOR BOOT BUDGET available_seconds=$InternalBudgetSeconds first_timeout_seconds=$firstLimit"
    if ($firstLimit -lt $MinimumFirstAttemptSeconds) { throw 'Insufficient simulator boot phase budget remains to start bootstatus safely.' }
    $bootArguments = @($ExecutablePrefixArguments) + @('simctl', 'bootstatus', $SimulatorId, '-b')
    $first = Invoke-ManagedProcess $XcrunPath $bootArguments $firstLimit 'simctl bootstatus attempt=1'
    if (-not $first.TerminationConfirmed -or -not $first.OutputDrained) { throw 'The bootstatus client did not terminate and drain its output safely; refusing retry/readiness.' }
    if (-not $first.TimedOut) {
        if ($first.ExitCode -ne 0) { throw "simctl bootstatus failed on first attempt with exit code $($first.ExitCode)." }
    }
    else {
        if (-not $first.TerminationConfirmed) { throw 'The first bootstatus process tree could not be confirmed terminated; refusing retry.' }
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
        $preRetryReserve = (2 * $processCleanupReserve) + $MinimumRetrySeconds + $inventoryWorstCase
        $preRetryTimeout = [Math]::Min($InventoryTimeoutSeconds, $remaining - $preRetryReserve)
        if ($preRetryTimeout -lt 1) { throw 'Insufficient internal boot phase budget remains for a safe ownership check and retry.' }
        $entry = Get-VerifiedSimulatorInventoryEntry $XcrunPath $SimulatorId $preRetryTimeout 'simctl inventory before retry' $ExecutablePrefixArguments
        if (-not $entry -or $entry.RuntimeIdentifier -ne $RuntimeIdentifier -or $entry.Device.name -ne $SimulatorName -or
            $entry.Device.state -notin @('Created', 'Shutdown', 'Booting', 'Booted')) {
            throw 'The exact run-owned simulator is absent or has unexpected identity/state; refusing boot retry.'
        }
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
        $retryLimit = [Math]::Min($RetryMaximumSeconds, $remaining - ($inventoryWorstCase + $processCleanupReserve))
        if ($retryLimit -lt $MinimumRetrySeconds) { throw 'Insufficient internal boot phase budget remains for a second bootstatus client.' }
        Write-Host "SIMULATOR BOOTSTATUS RETRY utc=$([DateTime]::UtcNow.ToString('o')) udid=$SimulatorId timeout_seconds=$retryLimit"
        $second = Invoke-ManagedProcess $XcrunPath $bootArguments $retryLimit 'simctl bootstatus attempt=2'
        if (-not $second.TerminationConfirmed -or -not $second.OutputDrained) { throw 'The retry bootstatus client did not terminate and drain its output safely.' }
        if ($second.TimedOut) { throw 'The fresh bootstatus client timed out; no further retry is permitted.' }
        if ($second.ExitCode -ne 0) { throw "simctl bootstatus failed on retry with exit code $($second.ExitCode)." }
    }
    $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
    $finalInventoryTimeout = [Math]::Min($InventoryTimeoutSeconds, $remaining - $processCleanupReserve)
    if ($finalInventoryTimeout -lt 1) { throw 'Internal simulator boot phase deadline was exceeded.' }
    $ready = Get-VerifiedSimulatorInventoryEntry $XcrunPath $SimulatorId $finalInventoryTimeout 'simctl final readiness inventory' $ExecutablePrefixArguments
    if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) {
        throw 'Internal simulator boot phase deadline was exceeded while checking final readiness.'
    }
    if (-not $ready -or $ready.RuntimeIdentifier -ne $RuntimeIdentifier -or $ready.Device.name -ne $SimulatorName -or $ready.Device.state -ne 'Booted') {
        throw "Simulator $SimulatorId did not pass bootstatus and exact Booted inventory verification."
    }
    Write-Host "SIMULATOR BOOTSTATUS VERIFIED utc=$([DateTime]::UtcNow.ToString('o')) udid=$SimulatorId state=$($ready.Device.state)"
    return $ready.Device
}

function Get-EligibleIphoneSimulatorCandidates {
    param(
        [Parameter(Mandatory)] $DeviceInventory,
        [Parameter(Mandatory)][object[]] $RuntimeMetadata
    )
    $runtimeByIdentifier = @{}
    foreach ($runtime in $RuntimeMetadata) {
        if (-not [string]::IsNullOrWhiteSpace([string]$runtime.identifier)) {
            $runtimeByIdentifier[[string]$runtime.identifier] = $runtime
        }
    }
    $candidates = @(
        foreach ($runtimeGroup in $DeviceInventory.devices.PSObject.Properties) {
            $identifierMatch = [regex]::Match([string]$runtimeGroup.Name, '^com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$')
            if (-not $identifierMatch.Success) { continue }
            $identifierMajor = [int]$identifierMatch.Groups[1].Value
            $identifierMinor = [int]$identifierMatch.Groups[2].Value
            $identifierHasPatch = $identifierMatch.Groups[3].Success
            $identifierPatch = if ($identifierHasPatch) { [int]$identifierMatch.Groups[3].Value } else { 0 }
            $identifierVersion = [version]::new($identifierMajor, $identifierMinor, $identifierPatch)
            $metadata = $runtimeByIdentifier[[string]$runtimeGroup.Name]
            if (-not $metadata -or $metadata.isAvailable -ne $true) { continue }
            $versionText = [string]$metadata.version
            $versionSource = 'simctl-runtime-metadata.version'
            if ([string]::IsNullOrWhiteSpace($versionText)) {
                $runtimeNameMatch = [regex]::Match([string]$metadata.name, '^iOS\s+(\d+\.\d+(?:\.\d+)?)$')
                if ($runtimeNameMatch.Success) {
                    $versionText = $runtimeNameMatch.Groups[1].Value
                    $versionSource = 'simctl-runtime-metadata.name'
                }
            }
            if ([string]::IsNullOrWhiteSpace($versionText)) {
                $versionText = [string]$metadata.SimulatorVersion
                if (-not [string]::IsNullOrWhiteSpace($versionText)) { $versionSource = 'simctl-runtime-metadata.SimulatorVersion' }
            }
            if ([string]::IsNullOrWhiteSpace($versionText)) { continue }
            $versionMatch = [regex]::Match($versionText, '^(\d+)\.(\d+)(?:\.(\d+))?$')
            if (-not $versionMatch.Success) { continue }
            $metadataPatch = if ($versionMatch.Groups[3].Success) { [int]$versionMatch.Groups[3].Value } else { 0 }
            $runtimeVersion = [version]::new([int]$versionMatch.Groups[1].Value, [int]$versionMatch.Groups[2].Value, $metadataPatch)
            if ($runtimeVersion.Major -ne $identifierVersion.Major -or $runtimeVersion.Minor -ne $identifierVersion.Minor) { continue }
            if ($identifierHasPatch -and $identifierPatch -ne $runtimeVersion.Build) { continue }
            if ($runtimeVersion -lt [version]'17.0') { continue }
            foreach ($device in $runtimeGroup.Value) {
                if ($device.isAvailable -ne $true -or [string]$device.name -notlike 'iPhone*') { continue }
                [pscustomobject]@{
                    RuntimeVersion = $runtimeVersion
                    RuntimeVersionSource = $versionSource
                    RuntimeIdentifier = [string]$runtimeGroup.Name
                    RuntimeMajor = $runtimeVersion.Major
                    Device = $device
                }
            }
        }
    )
    @($candidates | Sort-Object `
        @{ Expression = 'RuntimeVersion'; Descending = $true }, `
        @{ Expression = 'RuntimeIdentifier'; Descending = $false }, `
        @{ Expression = { [string]$_.Device.name }; Descending = $false }, `
        @{ Expression = { [string]$_.Device.udid }; Descending = $false })
}

function Assert-PinnedFlutter {
    Write-Host "SDK CHECK START utc=$([DateTime]::UtcNow.ToString('o'))"
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
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX) -and
        $toolchain.flutter.macos.archive -match 'macos_arm64') {
        $actualArch = & /usr/bin/uname -m
        if ($LASTEXITCODE -ne 0 -or $actualArch.Trim() -ne 'arm64') {
            throw "Pinned Flutter archive requires native arm64; found '$actualArch'."
        }
    }
    Write-Host "SDK CHECK END utc=$([DateTime]::UtcNow.ToString('o')) version=$($versionJson.frameworkVersion) revision=$($versionJson.frameworkRevision) dart=$($versionJson.dartSdkVersion)"
}

function Invoke-ToolchainPhase {
    Assert-PinnedFlutter
    New-Item -ItemType Directory -Force -Path $runStateRoot | Out-Null
    $doctorReportRoot = Join-Path $repositoryRoot 'artifacts/mobile/toolchain'
    New-Item -ItemType Directory -Force -Path $doctorReportRoot | Out-Null
    $doctorPath = Join-Path $doctorReportRoot 'flutter-doctor.txt'
    Write-Host "COMMAND START phase=Toolchain utc=$([DateTime]::UtcNow.ToString('o')) command=flutter doctor --verbose"
    $doctorTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $doctorOutput = & $flutterCommand doctor --verbose 2>&1
    $doctorExitCode = $LASTEXITCODE
    $doctorTimer.Stop()
    $doctorText = $doctorOutput | Out-String
    $doctorOutput | Tee-Object -FilePath $doctorPath
    $xcodeConfirmed = $doctorText -match '\[✓\] Xcode - develop for iOS and macOS'
    $xcodeMatchesPin = $false
    $xcodeVersionText = ''
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        $xcodeVersion = & /usr/bin/xcodebuild -version 2>&1
        $xcodeExitCode = $LASTEXITCODE
        $xcodeVersionText = $xcodeVersion | Out-String
        $xcodeMatchesPin = $xcodeExitCode -eq 0 -and $xcodeVersionText -match "(?m)^Xcode $([regex]::Escape([string]$toolchain.xcode.version))\s*$"
    }
    $doctorState = [ordered]@{
        runToken = $runToken
        recordedAtUtc = [DateTime]::UtcNow.ToString('o')
        doctorExitCode = $doctorExitCode
        xcodeConfirmed = [bool]$xcodeConfirmed
        xcodeMatchesPin = [bool]$xcodeMatchesPin
        xcodeVersion = $xcodeVersionText.Trim()
        doctorReport = $doctorPath
    }
    $doctorState | ConvertTo-Json | Set-Content -LiteralPath $doctorStatePath -Encoding utf8
    Write-Host "COMMAND END phase=Toolchain utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($doctorTimer.Elapsed.TotalSeconds, 2)) exit_code=$doctorExitCode xcode_confirmed=$xcodeConfirmed xcode_matches_pin=$xcodeMatchesPin"
    if ($doctorExitCode -ne 0) {
        Write-Warning "flutter doctor exited $doctorExitCode. Full report saved at '$doctorPath'; Android or optional host warnings do not replace the explicit Xcode check."
    }
}

function Invoke-FlutterChecksPhase {
    Assert-PinnedFlutter
    Push-Location $mobileRoot
    try {
        Invoke-Checked $flutterCommand @('pub', 'get', '--enforce-lockfile')
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
        Invoke-Checked $dartCommand @('run', 'pigeon', '--input', $candidateInput)
        Invoke-Checked $dartCommand @('format', $candidateDart)
        $committedDart = Join-Path $mobileRoot 'lib/data/services/platform/generated/mobile_platform_api.dart'
        $committedSwift = Join-Path $mobileRoot 'ios/Runner/MobilePlatformApi.g.swift'
        foreach ($pair in @(
                @{ Expected = $committedDart; Actual = $candidateDart },
                @{ Expected = $committedSwift; Actual = $candidateSwift }
            )) {
            if (-not (Test-Path -LiteralPath $pair.Expected -PathType Leaf)) {
                throw "Generated Pigeon binding is missing: '$($pair.Expected)'."
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
    }
    finally {
        Pop-Location
    }
}

function Assert-IosBuildPrerequisites {
    if (-not (Test-Path -LiteralPath $doctorStatePath -PathType Leaf)) {
        throw "Missing fresh Toolchain phase record '$doctorStatePath'; run the Toolchain phase first."
    }
    $doctorState = Get-Content -LiteralPath $doctorStatePath -Raw | ConvertFrom-Json
    if ($doctorState.runToken -ne $runToken -or -not $doctorState.xcodeConfirmed -or -not $doctorState.xcodeMatchesPin) {
        throw "The preceding Toolchain phase did not confirm pinned Xcode for this workflow run (expected token '$runToken')."
    }
    if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::OSX)) {
        throw 'An iOS Simulator build requires macOS and Xcode; this host is not macOS.'
    }
    $xcodePath = "/Applications/Xcode_$($toolchain.xcode.version).app/Contents/Developer"
    if (-not (Test-Path -LiteralPath $xcodePath -PathType Container)) {
        $available = & /usr/bin/xcode-select -p 2>$null
        throw "Pinned Xcode $($toolchain.xcode.version) is required at '$xcodePath'; selected Xcode is '$available'."
    }
    Invoke-Checked '/usr/bin/sudo' @('/usr/bin/xcode-select', '--switch', $xcodePath)
    $xcodeVersion = & /usr/bin/xcodebuild -version
    if ($LASTEXITCODE -ne 0 -or $xcodeVersion -notcontains "Xcode $($toolchain.xcode.version)") {
        throw "Expected Xcode $($toolchain.xcode.version), found '$($xcodeVersion -join ' ')'."
    }
    Write-Host ($xcodeVersion -join "`n")
}

function Invoke-IosBuildPhase {
    Assert-PinnedFlutter
    Assert-IosBuildPrerequisites
    Push-Location $mobileRoot
    try {
        Invoke-Checked $flutterCommand @('build', 'ios', '--simulator', '--no-codesign')
        $widgetInfoPlist = Join-Path $mobileRoot 'build/ios/iphonesimulator/Runner.app/PlugIns/WidgetExtension.appex/Info.plist'
        if (-not (Test-Path -LiteralPath $widgetInfoPlist -PathType Leaf)) {
            throw "Built Widget extension Info.plist is missing: '$widgetInfoPlist'."
        }
        Invoke-Checked '/usr/bin/plutil' @('-lint', $widgetInfoPlist)
        $extensionPoint = & /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' $widgetInfoPlist
        if ($LASTEXITCODE -ne 0 -or $extensionPoint -ne 'com.apple.widgetkit-extension') {
            throw "Built Widget extension has an invalid NSExtensionPointIdentifier: '$extensionPoint'."
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-SimulatorBootPhase {
    Assert-PinnedFlutter
    Assert-IosBuildPrerequisites
    $simulatorOutput = & /usr/bin/xcrun simctl list devices available --json
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate available iOS simulators.' }
    $simulatorInventory = $simulatorOutput | ConvertFrom-Json
    $runtimeOutput = & /usr/bin/xcrun simctl list runtimes --json
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate iOS Simulator runtime metadata from the pinned Xcode.' }
    $runtimeInventory = $runtimeOutput | ConvertFrom-Json
    if (-not $runtimeInventory.runtimes) { throw 'Pinned Xcode returned no Simulator runtime metadata.' }
    $availableIPhones = @(Get-EligibleIphoneSimulatorCandidates $simulatorInventory ([object[]]$runtimeInventory.runtimes))
    if ($availableIPhones.Count -eq 0) {
        throw 'No available iPhone simulator for iOS 17+ matched the pinned Xcode runtime metadata.'
    }
    $selected = $availableIPhones[0]
    $device = $selected.Device
    $isGitHubActions = $env:GITHUB_ACTIONS -eq 'true'
    $simulatorOwned = $false
    if ($isGitHubActions) {
        $deviceTypeIdentifier = [string]$device.deviceTypeIdentifier
        if ([string]::IsNullOrWhiteSpace($deviceTypeIdentifier)) {
            $deviceTypesOutput = & /usr/bin/xcrun simctl list devicetypes --json
            if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate simulator device types.' }
            $deviceTypesInventory = $deviceTypesOutput | ConvertFrom-Json
            $matchingTypes = @(
                $deviceTypesInventory.devicetypes |
                    Where-Object { $_.name -eq $device.name -and ($_.productFamily -eq 'iPhone' -or $_.name -like 'iPhone*') }
            )
            if ($matchingTypes.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$matchingTypes[0].identifier)) {
                throw "Could not resolve one iPhone simulator device type for '$($device.name)' from simctl JSON."
            }
            $deviceTypeIdentifier = [string]$matchingTypes[0].identifier
        }
        $simulatorName = "Gainer-CI-$runToken"
        Write-Host "SIMULATOR CREATE START utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName runtime=$($selected.RuntimeIdentifier) deviceType=$deviceTypeIdentifier sourceDevice=$($device.name)"
        $createOutput = & /usr/bin/xcrun simctl create $simulatorName $deviceTypeIdentifier $selected.RuntimeIdentifier
        $createExitCode = $LASTEXITCODE
        $simulatorId = [string]($createOutput | Select-Object -Last 1)
        $simulatorId = $simulatorId.Trim()
        if ($createExitCode -ne 0 -or $simulatorId -notmatch '^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') {
            throw "Could not create an isolated CI simulator; simctl returned '$simulatorId' (exit $createExitCode)."
        }
        $simulatorOwned = $true
        $initialState = 'Created'
    }
    else {
        $simulatorId = [string]$device.udid
        $simulatorName = [string]$device.name
        $initialState = [string]$device.state
        if ($initialState -notin @('Shutdown', 'Booted', 'Booting')) {
            throw "Selected iPhone simulator is in an unexpected state '$initialState'."
        }
    }

    $simulatorState = [ordered]@{
        runToken = $runToken
        recordedAtUtc = [DateTime]::UtcNow.ToString('o')
        simulatorId = $simulatorId
        simulatorName = $simulatorName
        runtimeIdentifier = $selected.RuntimeIdentifier
        runtimeMajor = $selected.RuntimeMajor
        deviceTypeIdentifier = if ($isGitHubActions) { $deviceTypeIdentifier } else { [string]$device.deviceTypeIdentifier }
        owned = $simulatorOwned
        state = $initialState
    }
    New-Item -ItemType Directory -Force -Path $runStateRoot | Out-Null
    $simulatorState | ConvertTo-Json | Set-Content -LiteralPath $simulatorStatePath -Encoding utf8
    Write-Host "SIMULATOR SELECTED utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName ios_version=$($selected.RuntimeVersion) version_source=$($selected.RuntimeVersionSource) xcode=$($toolchain.xcode.version) runtime=$($selected.RuntimeIdentifier) udid=$simulatorId owned=$simulatorOwned initialState=$initialState"
    if ($isGitHubActions) {
        Write-Host "SIMULATOR DYLD CACHE PREPARE START utc=$([DateTime]::UtcNow.ToString('o')) runtime=$($selected.RuntimeIdentifier)"
        Invoke-Checked '/usr/bin/xcrun' @('simctl', 'runtime', 'dyld_shared_cache', 'update', $selected.RuntimeIdentifier)
        Write-Host "SIMULATOR DYLD CACHE PREPARE END utc=$([DateTime]::UtcNow.ToString('o')) runtime=$($selected.RuntimeIdentifier)"
    }
    Write-Host "SIMULATOR BOOTSTATUS START utc=$([DateTime]::UtcNow.ToString('o')) udid=$simulatorId"
    if ($isGitHubActions) {
        $availableBootBudget = 270 - [int][Math]::Ceiling($script:PhaseTimer.Elapsed.TotalSeconds)
        $deviceAfterBoot = Invoke-CiSimulatorBootStatus '/usr/bin/xcrun' $runToken $simulatorStatePath $simulatorId $simulatorName $selected.RuntimeIdentifier -InternalBudgetSeconds $availableBootBudget
    }
    else {
        Invoke-Checked '/usr/bin/xcrun' @('simctl', 'bootstatus', $simulatorId, '-b')
        $deviceOutput = & /usr/bin/xcrun simctl list devices available --json
        if ($LASTEXITCODE -ne 0) { throw 'Could not re-check simulator state after boot.' }
        $deviceAfterBoot = $null
        $devicesAfterBoot = ($deviceOutput | ConvertFrom-Json).devices
        foreach ($runtime in $devicesAfterBoot.PSObject.Properties) {
            foreach ($candidateDevice in $runtime.Value) {
                if ($candidateDevice.udid -eq $simulatorId) { $deviceAfterBoot = $candidateDevice; break }
            }
            if ($deviceAfterBoot) { break }
        }
    }
    if (-not $deviceAfterBoot -or $deviceAfterBoot.state -ne 'Booted') {
        throw "Simulator $simulatorId did not reach Booted state after bootstatus."
    }
    $simulatorState.state = $deviceAfterBoot.state
    $simulatorState.recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    $simulatorState | ConvertTo-Json | Set-Content -LiteralPath $simulatorStatePath -Encoding utf8
    Write-Host "SIMULATOR READY utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName runtimeMajor=$($selected.RuntimeMajor) runtime=$($selected.RuntimeIdentifier) udid=$simulatorId owned=$simulatorOwned state=$($deviceAfterBoot.state)"
}

function Invoke-NativeTestsPhase {
    Assert-PinnedFlutter
    Assert-IosBuildPrerequisites
    if (-not (Test-Path -LiteralPath $simulatorStatePath -PathType Leaf)) {
        throw "Missing simulator boot record '$simulatorStatePath'; run SimulatorBoot first."
    }
    $simulatorState = Get-Content -LiteralPath $simulatorStatePath -Raw | ConvertFrom-Json
    if ($simulatorState.runToken -ne $runToken -or $simulatorState.state -ne 'Booted') {
        throw "Simulator boot record is stale or incomplete for this workflow run (expected token '$runToken')."
    }
    if ($env:GITHUB_ACTIONS -eq 'true' -and $simulatorState.owned -ne $true) {
        throw 'The CI native test phase requires a simulator created and owned by this workflow run.'
    }
    $nativeTestRoot = Join-Path $repositoryRoot 'artifacts/mobile/native-tests'
    $resultBundlePath = Join-Path $nativeTestRoot 'RunnerTests.xcresult'
    if (Test-Path -LiteralPath $resultBundlePath) {
        Remove-Item -LiteralPath $resultBundlePath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $nativeTestRoot | Out-Null
    Push-Location $mobileRoot
    try {
        Invoke-Checked '/usr/bin/xcodebuild' @(
            '-workspace', 'ios/Runner.xcworkspace',
            '-scheme', 'Runner',
            '-destination', "platform=iOS Simulator,id=$($simulatorState.simulatorId)",
            '-parallel-testing-enabled', 'NO',
            '-resultBundlePath', $resultBundlePath,
            'CODE_SIGNING_ALLOWED=NO',
            'CODE_SIGNING_REQUIRED=NO',
            'test'
        )
    }
    finally {
        Pop-Location
    }
}

$phaseMap = [ordered]@{
    Toolchain = { Invoke-ToolchainPhase }
    FlutterChecks = { Invoke-FlutterChecksPhase }
    IosBuild = { Invoke-IosBuildPhase }
    SimulatorBoot = { Invoke-SimulatorBootPhase }
    NativeTests = { Invoke-NativeTestsPhase }
}

if ($Phase -eq 'All') {
    foreach ($phaseName in @('Toolchain', 'FlutterChecks')) {
        Invoke-Phase $phaseName $phaseMap[$phaseName]
    }
    if ($BuildIosSimulator) {
        foreach ($phaseName in @('IosBuild', 'SimulatorBoot', 'NativeTests')) {
            Invoke-Phase $phaseName $phaseMap[$phaseName]
        }
    }
}
else {
    Invoke-Phase $Phase $phaseMap[$Phase]
}
