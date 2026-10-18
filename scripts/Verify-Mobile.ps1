[CmdletBinding()]
param(
    [string] $FlutterSdkRoot,
    [ValidateSet('All', 'Toolchain', 'FlutterChecks', 'IosBuild', 'SimulatorBoot', 'NativeTests', 'UiCapture')]
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
    Write-Information "PHASE START name=$Name utc=$([DateTime]::UtcNow.ToString('o'))" -InformationAction Continue
}

function Write-PhaseEnd {
    param([string] $Name)
    $script:PhaseTimer.Stop()
    Write-Information "PHASE END name=$Name utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($script:PhaseTimer.Elapsed.TotalSeconds, 2))" -InformationAction Continue
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
    Write-Information "COMMAND START phase=$script:CurrentPhase utc=$([DateTime]::UtcNow.ToString('o')) command=$label" -InformationAction Continue
    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    $timer.Stop()
    Write-Information "COMMAND END phase=$script:CurrentPhase utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($timer.Elapsed.TotalSeconds, 2)) exit_code=$exitCode command=$label" -InformationAction Continue
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

function Write-ManagedOutputPreview {
    param(
        [Parameter(Mandatory)][string] $Label,
        [AllowEmptyString()][string] $Stdout,
        [AllowEmptyString()][string] $Stderr,
        [int] $OutputPreviewLimit = 12000
    )
    foreach ($stream in @(@{ Name = 'STDOUT'; Text = $Stdout }, @{ Name = 'STDERR'; Text = $Stderr })) {
        if ($stream.Text) {
            $preview = [string]$stream.Text
            $wasTruncated = $preview.Length -gt $OutputPreviewLimit
            if ($wasTruncated) {
                $headLength = [int][Math]::Min(4000, [Math]::Floor($OutputPreviewLimit / 3))
                $tailLength = $OutputPreviewLimit - $headLength
                $preview = $preview.Substring(0, $headLength) +
                    "`n... output omitted; final process output follows ...`n" +
                    $preview.Substring($preview.Length - $tailLength)
            }
            Write-Information "MANAGED $($stream.Name) BEGIN label=$Label`n$preview" -InformationAction Continue
            if ($wasTruncated) { Write-Information "MANAGED $($stream.Name) TRUNCATED label=$Label original_characters=$($stream.Text.Length) limit=$OutputPreviewLimit" -InformationAction Continue }
            Write-Information "MANAGED $($stream.Name) END label=$Label" -InformationAction Continue
        }
    }
}

function New-ManagedProcess {
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $WorkingDirectory
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    if ($WorkingDirectory) {
        if (-not [System.IO.Path]::IsPathFullyQualified($WorkingDirectory) -or
            -not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
            throw "Managed process working directory must be an existing absolute directory: $WorkingDirectory"
        }
        $startInfo.WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    return $process
}

function Get-OpenManagedReads {
    param([Parameter(Mandatory)][hashtable] $State)
    for ($index = 0; $index -lt 2; $index++) {
        if ($State.Open[$index]) { $State.Pending[$index] }
    }
}

function Update-ManagedStallClock {
    param([Parameter(Mandatory)][hashtable] $State, [AllowEmptyString()][string] $Line)
    if ($State.StallEnd.IsMatch($Line)) { $State.StallClock = $null }
    elseif ($State.StallStart.IsMatch($Line)) { $State.StallClock = [System.Diagnostics.Stopwatch]::StartNew() }
}

function Read-ReadyManagedLines {
    # Consumes every line already available on one stream; a null line marks its end.
    param([Parameter(Mandatory)][hashtable] $State, [Parameter(Mandatory)][int] $Index)
    while ($State.Open[$Index] -and $State.Pending[$Index].IsCompleted) {
        $line = $State.Pending[$Index].GetAwaiter().GetResult()
        if ($null -eq $line) {
            $State.Open[$Index] = $false
            return
        }
        [void]$State.Buffers[$Index].AppendLine($line)
        Update-ManagedStallClock $State $line
        $State.Pending[$Index] = $State.Readers[$Index].ReadLineAsync()
    }
}

function Wait-ManagedStreams {
    # Returns 'ended' when both streams closed, 'timeout' or 'stalled' otherwise.
    param(
        [Parameter(Mandatory)][hashtable] $State,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][int] $StallTimeoutSeconds
    )
    while ($State.Open[0] -or $State.Open[1]) {
        if ($State.Timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { return 'timeout' }
        if ($null -ne $State.StallClock -and $State.StallClock.Elapsed.TotalSeconds -ge $StallTimeoutSeconds) { return 'stalled' }
        [void][System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@(Get-OpenManagedReads $State), 250)
        Read-ReadyManagedLines $State 0
        Read-ReadyManagedLines $State 1
    }
    return 'ended'
}

function Complete-ManagedProcess {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process] $Process,
        [Parameter(Mandatory)][string] $Outcome,
        [Parameter(Mandatory)][double] $RemainingSeconds,
        [Parameter(Mandatory)][string] $Label
    )
    if ($Outcome -eq 'ended' -and $Process.WaitForExit([int][Math]::Max(1000, $RemainingSeconds * 1000))) {
        return @{ TimedOut = $false; Stalled = $false; TerminationConfirmed = $true }
    }
    $stalled = $Outcome -eq 'stalled'
    $reason = if ($stalled) { 'stalled' } else { 'timed out' }
    Write-Warning "Managed command $reason; terminating only its process tree: $Label"
    return @{ TimedOut = -not $stalled; Stalled = $stalled; TerminationConfirmed = (Stop-ManagedProcessTree $Process) }
}

function Invoke-ManagedProcessWithStallGuard {
    # Like Invoke-ManagedProcess, but reads output line by line so a known
    # waiting state (StallStartPattern) that is not resolved by a progress line
    # (StallEndPattern) within StallTimeoutSeconds ends the process tree early
    # and reports Stalled instead of consuming the whole budget.
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][regex] $StallStartPattern,
        [Parameter(Mandatory)][regex] $StallEndPattern,
        [Parameter(Mandatory)][int] $StallTimeoutSeconds,
        [int] $OutputPreviewLimit = 12000,
        [string] $WorkingDirectory
    )
    $process = New-ManagedProcess $Executable $Arguments $WorkingDirectory
    $state = @{
        Timer = [System.Diagnostics.Stopwatch]::StartNew()
        Buffers = @([System.Text.StringBuilder]::new(), [System.Text.StringBuilder]::new())
        Open = @($true, $true)
        StallStart = $StallStartPattern
        StallEnd = $StallEndPattern
        StallClock = $null
    }
    Write-Information "MANAGED COMMAND START utc=$([DateTime]::UtcNow.ToString('o')) label=$Label timeout_seconds=$TimeoutSeconds stall_timeout_seconds=$StallTimeoutSeconds" -InformationAction Continue
    try {
        if (-not $process.Start()) { throw "Could not start managed command '$Label'." }
        $state.Readers = @($process.StandardOutput, $process.StandardError)
        $state.Pending = @($state.Readers[0].ReadLineAsync(), $state.Readers[1].ReadLineAsync())
        $outcome = Wait-ManagedStreams $state $TimeoutSeconds $StallTimeoutSeconds
        $end = Complete-ManagedProcess $process $outcome ($TimeoutSeconds - $state.Timer.Elapsed.TotalSeconds) $Label
        $exited = $process.HasExited
        if ($exited) { [void]$process.WaitForExit(1000) }
        $drainTasks = @(Get-OpenManagedReads $state)
        $drainConfirmed = $drainTasks.Count -eq 0 -or (Wait-ManagedOutputDrain ([System.Threading.Tasks.Task[]]$drainTasks) 3000)
        $state.Timer.Stop()
        $outText = $state.Buffers[0].ToString()
        $errText = $state.Buffers[1].ToString()
        Write-ManagedOutputPreview $Label $outText $errText $OutputPreviewLimit
        $exitCode = if ($exited) { $process.ExitCode } else { $null }
        Write-Information "MANAGED COMMAND END utc=$([DateTime]::UtcNow.ToString('o')) label=$Label elapsed_seconds=$([Math]::Round($state.Timer.Elapsed.TotalSeconds, 2)) timed_out=$($end.TimedOut) stalled=$($end.Stalled) exit_code=$exitCode termination_confirmed=$($end.TerminationConfirmed) output_drained=$drainConfirmed" -InformationAction Continue
        return [pscustomobject]@{ TimedOut = $end.TimedOut; Stalled = $end.Stalled; ExitCode = $exitCode; TerminationConfirmed = $end.TerminationConfirmed; OutputDrained = $drainConfirmed; Stdout = $outText; Stderr = $errText }
    }
    finally { $process.Dispose() }
}

function Invoke-ManagedProcess {
    param(
        [Parameter(Mandatory)][string] $Executable,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][string] $Label,
        [switch] $SuppressOutputPreview,
        [int] $OutputPreviewLimit = 12000,
        [string] $WorkingDirectory
    )
    $process = New-ManagedProcess $Executable $Arguments $WorkingDirectory
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Information "MANAGED COMMAND START utc=$([DateTime]::UtcNow.ToString('o')) label=$Label timeout_seconds=$TimeoutSeconds" -InformationAction Continue
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
        if (-not $SuppressOutputPreview) {
            Write-ManagedOutputPreview $Label $outText $errText $OutputPreviewLimit
        }
        $exitCode = if ($exited) { $process.ExitCode } else { $null }
        Write-Information "MANAGED COMMAND END utc=$([DateTime]::UtcNow.ToString('o')) label=$Label elapsed_seconds=$([Math]::Round($timer.Elapsed.TotalSeconds, 2)) timed_out=$timedOut exit_code=$exitCode termination_confirmed=$terminationConfirmed output_drained=$drainConfirmed" -InformationAction Continue
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
        [string[]] $ExecutablePrefixArguments = @(),
        [Parameter(Mandatory)][string] $ExpectedRuntimeIdentifier,
        [Parameter(Mandatory)][string] $ExpectedName,
        [switch] $RequireBooted,
        [switch] $ReturnConfirmedTimeout
    )
    $inventoryArguments = @($ExecutablePrefixArguments) + @('simctl', 'list', 'devices', '--json')
    $commandLabel = "$Label command=xcrun simctl list devices --json"
    $query = Invoke-ManagedProcess $XcrunPath $inventoryArguments $TimeoutSeconds $commandLabel -SuppressOutputPreview
    if ($query.TimedOut -and $ReturnConfirmedTimeout -and $query.TerminationConfirmed -and $query.OutputDrained) {
        return [pscustomobject]@{ InventoryTimedOut = $true }
    }
    if ($query.TimedOut -or -not $query.TerminationConfirmed -or -not $query.OutputDrained -or $query.ExitCode -ne 0) { throw "Could not obtain simulator inventory ($Label)." }
    try { $inventory = $query.Stdout | ConvertFrom-Json } catch { throw "Simulator inventory was invalid JSON ($Label)." }
    foreach ($runtime in $inventory.devices.PSObject.Properties) {
        foreach ($device in $runtime.Value) {
            if ([string]$device.udid -eq $SimulatorId) {
                Write-Information "SIMULATOR INVENTORY MATCH label=$Label runtime=$($runtime.Name) name=$($device.name) udid=$($device.udid) state=$($device.state) is_available=$($device.isAvailable)" -InformationAction Continue
                if ([string]$runtime.Name -ne $ExpectedRuntimeIdentifier -or [string]$device.name -ne $ExpectedName -or $device.isAvailable -ne $true) {
                    throw "Exact simulator identity/availability check failed ($Label)."
                }
                if ($RequireBooted -and [string]$device.state -ne 'Booted') { throw "Exact simulator is not Booted ($Label)." }
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
        [int] $InventoryTimeoutSeconds = 60,
        [string[]] $ExecutablePrefixArguments = @(),
        [int] $MinimumRetrySeconds = 10,
        [int] $MinimumFirstAttemptSeconds = 30,
        [int] $MinimumInventoryRetrySeconds = 10
    )
    $phaseClock = [System.Diagnostics.Stopwatch]::StartNew()
    # Each timed-out client may use up to 5s to confirm process-tree termination
    # and 3s to drain redirected streams. Reserve that cleanup time per client.
    $processCleanupReserve = 8
    $minimumInventoryTimeout = 1
    $inventoryMinimumWorstCase = $minimumInventoryTimeout + $processCleanupReserve
    $firstReserve = (2 * $inventoryMinimumWorstCase) + $MinimumRetrySeconds + (2 * $processCleanupReserve)
    $firstLimit = [Math]::Min($FirstAttemptSeconds, $InternalBudgetSeconds - $firstReserve)
    Write-Information "SIMULATOR BOOT BUDGET available_seconds=$InternalBudgetSeconds first_timeout_seconds=$firstLimit" -InformationAction Continue
    if ($firstLimit -lt $MinimumFirstAttemptSeconds) { throw 'Insufficient simulator boot phase budget remains to start bootstatus safely.' }
    $bootArguments = @($ExecutablePrefixArguments) + @('simctl', 'bootstatus', $SimulatorId, '-b')
    $first = Invoke-ManagedProcess $XcrunPath $bootArguments $firstLimit 'simctl bootstatus attempt=1'
    if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) { throw 'Simulator boot phase deadline was exceeded after first bootstatus client.' }
    if (-not $first.TerminationConfirmed -or -not $first.OutputDrained) { throw 'The bootstatus client did not terminate and drain its output safely; refusing retry/readiness.' }
    if (-not $first.TimedOut) {
        if ($first.ExitCode -ne 0) { throw "simctl bootstatus failed on first attempt with exit code $($first.ExitCode)." }
    }
    else {
        if (-not $first.TerminationConfirmed) { throw 'The first bootstatus process tree could not be confirmed terminated; refusing retry.' }
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
        $preRetryReserve = (3 * $processCleanupReserve) + $MinimumRetrySeconds + $minimumInventoryTimeout
        $preRetryTimeout = [Math]::Min($InventoryTimeoutSeconds, $remaining - $preRetryReserve)
        if ($preRetryTimeout -lt 1) { throw 'Insufficient internal boot phase budget remains for a safe ownership check and retry.' }
        $entry = Get-VerifiedSimulatorInventoryEntry $XcrunPath $SimulatorId $preRetryTimeout 'simctl inventory before retry' $ExecutablePrefixArguments $RuntimeIdentifier $SimulatorName
        if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) { throw 'Simulator boot phase deadline was exceeded while checking ownership before retry.' }
        if (-not $entry -or $entry.RuntimeIdentifier -ne $RuntimeIdentifier -or $entry.Device.name -ne $SimulatorName -or
            $entry.Device.state -notin @('Created', 'Shutdown', 'Booting', 'Booted')) {
            throw 'The exact run-owned simulator is absent or has unexpected identity/state; refusing boot retry.'
        }
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
        $retryLimit = [Math]::Min($RetryMaximumSeconds, $remaining - ($inventoryMinimumWorstCase + (2 * $processCleanupReserve)))
        if ($retryLimit -lt $MinimumRetrySeconds) { throw 'Insufficient internal boot phase budget remains for a second bootstatus client.' }
        Write-Information "SIMULATOR BOOTSTATUS RETRY utc=$([DateTime]::UtcNow.ToString('o')) udid=$SimulatorId timeout_seconds=$retryLimit" -InformationAction Continue
        $second = Invoke-ManagedProcess $XcrunPath $bootArguments $retryLimit 'simctl bootstatus attempt=2'
        if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) { throw 'Simulator boot phase deadline was exceeded after retry bootstatus client.' }
        if (-not $second.TerminationConfirmed -or -not $second.OutputDrained) { throw 'The retry bootstatus client did not terminate and drain its output safely.' }
        if ($second.TimedOut) { throw 'The fresh bootstatus client timed out; no further retry is permitted.' }
        if ($second.ExitCode -ne 0) { throw "simctl bootstatus failed on retry with exit code $($second.ExitCode)." }
    }
    $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
    # Reserve enough time for one fresh inventory client if this first readiness
    # query times out, including bounded process termination/output-drain time.
    $finalRetryReserve = (2 * $processCleanupReserve) + $MinimumInventoryRetrySeconds
    $finalInventoryTimeout = [Math]::Min($InventoryTimeoutSeconds, $remaining - $finalRetryReserve)
    if ($finalInventoryTimeout -lt $MinimumInventoryRetrySeconds) { throw 'Insufficient internal simulator boot phase budget remains for readiness and one bounded inventory retry.' }
    $ready = Get-VerifiedSimulatorInventoryEntry $XcrunPath $SimulatorId $finalInventoryTimeout 'simctl final readiness inventory attempt=1' $ExecutablePrefixArguments $RuntimeIdentifier $SimulatorName -RequireBooted -ReturnConfirmedTimeout
    if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) {
        throw 'Internal simulator boot phase deadline was exceeded while checking final readiness.'
    }
    if ($ready -and $ready.PSObject.Properties['InventoryTimedOut']) {
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        $remaining = $InternalBudgetSeconds - [int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds)
        $inventoryRetryTimeout = [Math]::Min($InventoryTimeoutSeconds, $remaining - $processCleanupReserve)
        if ($inventoryRetryTimeout -lt $MinimumInventoryRetrySeconds) {
            throw 'Insufficient internal simulator boot phase budget remains for the one permitted fresh readiness inventory client.'
        }
        Assert-OwnedSimulatorRecord $StatePath $RunToken $SimulatorId $SimulatorName $RuntimeIdentifier
        Write-Information "SIMULATOR INVENTORY RETRY utc=$([DateTime]::UtcNow.ToString('o')) udid=$SimulatorId timeout_seconds=$inventoryRetryTimeout reason=first_client_timed_out_terminated_and_drained" -InformationAction Continue
        $ready = Get-VerifiedSimulatorInventoryEntry $XcrunPath $SimulatorId $inventoryRetryTimeout 'simctl final readiness inventory attempt=2' $ExecutablePrefixArguments $RuntimeIdentifier $SimulatorName -RequireBooted
        if ([int][Math]::Ceiling($phaseClock.Elapsed.TotalSeconds) -gt $InternalBudgetSeconds) {
            throw 'Internal simulator boot phase deadline was exceeded after the one permitted readiness inventory retry.'
        }
    }
    if (-not $ready -or $ready.RuntimeIdentifier -ne $RuntimeIdentifier -or $ready.Device.name -ne $SimulatorName -or $ready.Device.state -ne 'Booted') {
        throw "Simulator $SimulatorId did not pass bootstatus and exact Booted inventory verification."
    }
    Write-Information "SIMULATOR BOOTSTATUS VERIFIED utc=$([DateTime]::UtcNow.ToString('o')) udid=$SimulatorId state=$($ready.Device.state)" -InformationAction Continue
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
    Write-Information "SDK CHECK START utc=$([DateTime]::UtcNow.ToString('o'))" -InformationAction Continue
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
    Write-Information "SDK CHECK END utc=$([DateTime]::UtcNow.ToString('o')) version=$($versionJson.frameworkVersion) revision=$($versionJson.frameworkRevision) dart=$($versionJson.dartSdkVersion)" -InformationAction Continue
}

function Invoke-ToolchainPhase {
    Assert-PinnedFlutter
    New-Item -ItemType Directory -Force -Path $runStateRoot | Out-Null
    $doctorReportRoot = Join-Path $repositoryRoot 'artifacts/mobile/toolchain'
    New-Item -ItemType Directory -Force -Path $doctorReportRoot | Out-Null
    $doctorPath = Join-Path $doctorReportRoot 'flutter-doctor.txt'
    Write-Information "COMMAND START phase=Toolchain utc=$([DateTime]::UtcNow.ToString('o')) command=flutter doctor --verbose" -InformationAction Continue
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
    Write-Information "COMMAND END phase=Toolchain utc=$([DateTime]::UtcNow.ToString('o')) elapsed_seconds=$([Math]::Round($doctorTimer.Elapsed.TotalSeconds, 2)) exit_code=$doctorExitCode xcode_confirmed=$xcodeConfirmed xcode_matches_pin=$xcodeMatchesPin" -InformationAction Continue
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
        # Goldens are Linux references; rasterization differs on macOS, so the
        # Sonar app pipeline (ubuntu) runs them instead.
        Invoke-Checked $flutterCommand @('test', '--exclude-tags', 'golden')
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
    Write-Information ($xcodeVersion -join "`n") -InformationAction Continue
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
        Write-Information "SIMULATOR CREATE START utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName runtime=$($selected.RuntimeIdentifier) deviceType=$deviceTypeIdentifier sourceDevice=$($device.name)" -InformationAction Continue
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
    Write-Information "SIMULATOR SELECTED utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName ios_version=$($selected.RuntimeVersion) version_source=$($selected.RuntimeVersionSource) xcode=$($toolchain.xcode.version) runtime=$($selected.RuntimeIdentifier) udid=$simulatorId owned=$simulatorOwned initialState=$initialState" -InformationAction Continue
    if ($isGitHubActions) {
        Write-Information "SIMULATOR DYLD CACHE PREPARE START utc=$([DateTime]::UtcNow.ToString('o')) runtime=$($selected.RuntimeIdentifier)" -InformationAction Continue
        Invoke-Checked '/usr/bin/xcrun' @('simctl', 'runtime', 'dyld_shared_cache', 'update', $selected.RuntimeIdentifier)
        Write-Information "SIMULATOR DYLD CACHE PREPARE END utc=$([DateTime]::UtcNow.ToString('o')) runtime=$($selected.RuntimeIdentifier)" -InformationAction Continue
    }
    Write-Information "SIMULATOR BOOTSTATUS START utc=$([DateTime]::UtcNow.ToString('o')) udid=$simulatorId" -InformationAction Continue
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
    Write-Information "SIMULATOR READY utc=$([DateTime]::UtcNow.ToString('o')) name=$simulatorName runtimeMajor=$($selected.RuntimeMajor) runtime=$($selected.RuntimeIdentifier) udid=$simulatorId owned=$simulatorOwned state=$($deviceAfterBoot.state)" -InformationAction Continue
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

function Stop-SimulatorRunnerApp {
    # Native XCTest uses Runner.app as its test host on this same simulator, and a
    # stalled capture attempt can leave the app running. A surviving process can
    # make `simctl launch` reuse an app started without the integration-test
    # entrypoint, so only this bundle on the exact owned simulator is terminated.
    param(
        [Parameter(Mandatory)][string] $SimulatorId,
        [Parameter(Mandatory)][string] $BundleId
    )
    Write-Information "SIMULATOR APP TERMINATE START utc=$([DateTime]::UtcNow.ToString('o')) udid=$($SimulatorId) bundle=$BundleId" -InformationAction Continue
    $terminateResult = Invoke-ManagedProcess '/usr/bin/xcrun' @(
        'simctl', 'terminate', $SimulatorId, $BundleId
    ) 20 'terminate prior Runner test-host process' -OutputPreviewLimit 2000
    if ($terminateResult.TimedOut -or -not $terminateResult.TerminationConfirmed -or
        -not $terminateResult.OutputDrained) {
        throw 'Could not confirm bounded cleanup of the Runner test-host process.'
    }
    $terminationMessage = "$($terminateResult.Stdout)`n$($terminateResult.Stderr)"
    $knownNotRunningMessage =
        $terminationMessage -match '(?i)domain=NSPOSIXErrorDomain,\s*code=3' -and
        $terminationMessage -match '(?i)(?:no such process|found nothing to terminate)'
    if ($terminateResult.ExitCode -eq 0) {
        Write-Information 'SIMULATOR APP TERMINATE END result=terminated' -InformationAction Continue
    }
    elseif ($terminateResult.ExitCode -eq 3 -and $knownNotRunningMessage) {
        Write-Information 'SIMULATOR APP TERMINATE END result=not_running' -InformationAction Continue
    }
    else {
        throw "Could not safely confirm the prior Runner process was absent: $($terminateResult.Stderr) $($terminateResult.Stdout)"
    }
}

function Invoke-UiCapturePhase {
    Assert-PinnedFlutter
    Assert-IosBuildPrerequisites
    $phaseClock = [System.Diagnostics.Stopwatch]::StartNew()
    $phaseBudgetSeconds = 690
    if (-not (Test-Path -LiteralPath $simulatorStatePath -PathType Leaf)) {
        throw "Missing simulator boot record '$simulatorStatePath'; run SimulatorBoot first."
    }
    $simulatorState = Get-Content -LiteralPath $simulatorStatePath -Raw | ConvertFrom-Json
    if ($simulatorState.runToken -ne $runToken -or $simulatorState.owned -ne $true -or $simulatorState.state -ne 'Booted') {
        throw 'UI capture requires the Booted simulator owned by this workflow run.'
    }
    Assert-OwnedSimulatorRecord -StatePath $simulatorStatePath -RunToken $runToken `
        -SimulatorId $simulatorState.simulatorId -SimulatorName $simulatorState.simulatorName `
        -RuntimeIdentifier $simulatorState.runtimeIdentifier
    $inventory = $null
    for ($attempt = 1; $attempt -le 2 -and $null -eq $inventory; $attempt++) {
        $remaining = [int][Math]::Floor($phaseBudgetSeconds - $phaseClock.Elapsed.TotalSeconds - 20)
        if ($remaining -lt 12) { throw 'UI capture ownership check exceeded its reserved phase budget.' }
        $result = Invoke-ManagedProcess '/usr/bin/xcrun' @('simctl', 'list', 'devices', '--json') `
            ([Math]::Min(25, $remaining)) "UI capture simulator inventory attempt $attempt" -SuppressOutputPreview
        if ($result.TimedOut) {
            if (-not $result.TerminationConfirmed -or -not $result.OutputDrained -or $attempt -eq 2) {
                throw 'Simulator inventory timed out without confirmed cleanup; refusing UI capture.'
            }
            continue
        }
        if (-not $result.TerminationConfirmed -or -not $result.OutputDrained -or $result.ExitCode -ne 0) {
            throw 'Simulator inventory failed; refusing UI capture.'
        }
        try { $inventory = $result.Stdout | ConvertFrom-Json }
        catch { throw 'Simulator inventory was invalid JSON; refusing UI capture.' }
    }
    $deviceFound = $false
    foreach ($runtime in $inventory.devices.PSObject.Properties) {
        foreach ($device in $runtime.Value) {
            if ([string]$device.udid -eq [string]$simulatorState.simulatorId -and
                [string]$runtime.Name -eq [string]$simulatorState.runtimeIdentifier -and
                [string]$device.name -eq [string]$simulatorState.simulatorName -and
                $device.isAvailable -eq $true -and [string]$device.state -eq 'Booted') {
                $deviceFound = $true
            }
        }
    }
    if (-not $deviceFound) { throw 'The exact workflow-owned simulator is unavailable or not Booted; refusing UI capture.' }

    $expectedScreenshots = @(
        'tab-heute', 'tab-checkin', 'tab-essen', 'tab-training', 'tab-mehr',
        'tab-dark-heute', 'tab-dark-checkin', 'tab-dark-essen', 'tab-dark-training', 'tab-dark-mehr',
        'sheet-checkin', 'sheet-goal', 'date-picker', 'training-workout', 'training-minimized', 'editor-essen',
        'sheet-dark-checkin', 'editor-dark-essen'
    )
    $captureRoot = Join-Path $repositoryRoot 'artifacts/mobile/ui-captures'
    New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null
    # Remove only the named generated outputs; a prior run must never make a
    # missing screenshot pass this verification phase.
    foreach ($name in $expectedScreenshots) {
        $path = Join-Path $captureRoot "$name.png"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    # Confirm the built bundle identity before terminating the app between attempts.
    $runnerInfoPlist = Join-Path $mobileRoot 'build/ios/iphonesimulator/Runner.app/Info.plist'
    if (-not (Test-Path -LiteralPath $runnerInfoPlist -PathType Leaf)) {
        throw "Built Runner app Info.plist is missing: '$runnerInfoPlist'."
    }
    $appBundleId = (& '/usr/libexec/PlistBuddy' -c 'Print :CFBundleIdentifier' $runnerInfoPlist | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appBundleId) -or
        $appBundleId -notmatch '^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$') {
        throw "Built Runner app has an invalid CFBundleIdentifier '$appBundleId'."
    }
    # On the CI simulator `flutter drive` occasionally launches the app but never
    # discovers its Dart VM service and then waits until the phase budget is gone.
    # That single, recognizable state is retried once after a fresh app launch;
    # every other failure still fails the phase immediately.
    $vmServiceWait = [regex]'Waiting for VM Service port to be available'
    $vmServiceFound = [regex]'(?i)Connected to Flutter application|Dart VM [Ss]ervice (is listening|was found)|VM Service URL'
    Push-Location $mobileRoot
    try {
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            Stop-SimulatorRunnerApp $simulatorState.simulatorId $appBundleId
            $commandBudget = [int][Math]::Floor($phaseBudgetSeconds - $phaseClock.Elapsed.TotalSeconds - 15)
            if ($commandBudget -lt 30) { throw 'UI capture has insufficient time remaining for the simulator test.' }
            $result = Invoke-ManagedProcessWithStallGuard $flutterCommand @(
                'drive',
                '--driver=test_driver/ui_design_driver.dart',
                '--target=integration_test/ui_design_test.dart',
                '-d', $simulatorState.simulatorId,
                '--no-pub',
                '--verbose'
            ) $commandBudget "fixture-backed native iOS UI capture attempt=$attempt" `
                -StallStartPattern $vmServiceWait -StallEndPattern $vmServiceFound -StallTimeoutSeconds 120 `
                -WorkingDirectory $mobileRoot -OutputPreviewLimit 20000
            $cleanlyEnded = $result.TerminationConfirmed -and $result.OutputDrained
            if ($result.Stalled -and $cleanlyEnded -and $attempt -lt 2) {
                Write-Information "UI CAPTURE RETRY utc=$([DateTime]::UtcNow.ToString('o')) reason=vm_service_not_discovered remaining_seconds=$([int]($phaseBudgetSeconds - $phaseClock.Elapsed.TotalSeconds))" -InformationAction Continue
                continue
            }
            if ($result.Stalled -or $result.TimedOut -or -not $cleanlyEnded -or $result.ExitCode -ne 0) {
                throw 'Fixture-backed iOS UI capture failed or exceeded its remaining phase budget.'
            }
            break
        }
    }
    finally {
        Pop-Location
    }
    foreach ($name in $expectedScreenshots) {
        $path = Join-Path $captureRoot "$name.png"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required native UI screenshot '$name.png' is missing or empty."
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -lt 1000) {
            throw "Required native UI screenshot '$name.png' is missing or empty."
        }
        $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
        for ($index = 0; $index -lt $signature.Length; $index++) {
            if ($bytes[$index] -ne $signature[$index]) {
                throw "Required native UI screenshot '$name.png' is not a PNG."
            }
        }
        if ([System.Text.Encoding]::ASCII.GetString($bytes, 12, 4) -ne 'IHDR') {
            throw "Required native UI screenshot '$name.png' has no PNG IHDR."
        }
        $width = [uint32]($bytes[16] * 16777216 + $bytes[17] * 65536 + $bytes[18] * 256 + $bytes[19])
        $height = [uint32]($bytes[20] * 16777216 + $bytes[21] * 65536 + $bytes[22] * 256 + $bytes[23])
        if ($width -lt 1 -or $height -lt 1 -or $width -gt 6000 -or $height -gt 12000) {
            throw "Required native UI screenshot '$name.png' has unreasonable dimensions ${width}x${height}."
        }
    }
    Write-Information "UI CAPTURES READY count=$($expectedScreenshots.Count) simulator=$($simulatorState.simulatorName) udid=$($simulatorState.simulatorId) elapsed_seconds=$([Math]::Round($phaseClock.Elapsed.TotalSeconds, 2))" -InformationAction Continue
}

$phaseMap = [ordered]@{
    Toolchain = { Invoke-ToolchainPhase }
    FlutterChecks = { Invoke-FlutterChecksPhase }
    IosBuild = { Invoke-IosBuildPhase }
    SimulatorBoot = { Invoke-SimulatorBootPhase }
    NativeTests = { Invoke-NativeTestsPhase }
    UiCapture = { Invoke-UiCapturePhase }
}

if ($Phase -eq 'All') {
    foreach ($phaseName in @('Toolchain', 'FlutterChecks')) {
        Invoke-Phase $phaseName $phaseMap[$phaseName]
    }
    if ($BuildIosSimulator) {
        foreach ($phaseName in @('IosBuild', 'SimulatorBoot', 'NativeTests', 'UiCapture')) {
            Invoke-Phase $phaseName $phaseMap[$phaseName]
        }
    }
}
else {
    Invoke-Phase $Phase $phaseMap[$Phase]
}
