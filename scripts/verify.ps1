[CmdletBinding()]
param(
    [switch] $SkipRestore
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$powerShellCommand = Get-Command "pwsh" -ErrorAction SilentlyContinue
if ($null -eq $powerShellCommand) {
    $powerShellCommand = Get-Command "powershell" -ErrorAction Stop
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)]
        [string] $Executable,

        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    Push-Location $WorkingDirectory

    try {
        & $Executable @Arguments

        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $SkipRestore) {
    Invoke-CheckedCommand -Executable "dotnet" -Arguments @("restore", "Gainer.slnx", "--locked-mode") -WorkingDirectory $repositoryRoot
}

Invoke-CheckedCommand -Executable "dotnet" -Arguments @("format", "Gainer.slnx", "--verify-no-changes", "--no-restore") -WorkingDirectory $repositoryRoot
Invoke-CheckedCommand -Executable "dotnet" -Arguments @("build", "Gainer.slnx", "--no-restore") -WorkingDirectory $repositoryRoot
Invoke-CheckedCommand -Executable "dotnet" -Arguments @("test", "Gainer.slnx", "--no-restore", "--no-build") -WorkingDirectory $repositoryRoot
Invoke-CheckedCommand -Executable "dotnet" -Arguments @("publish", "src/Gainer.Api/Gainer.Api.csproj", "--no-restore", "--configuration", "Release", "--output", "artifacts/api") -WorkingDirectory $repositoryRoot
Invoke-CheckedCommand -Executable $powerShellCommand.Source -Arguments @("./scripts/Test-ReleaseSafety.ps1", "-ArtifactPaths", "artifacts/api", "-CheckRepositoryPolicy") -WorkingDirectory $repositoryRoot
Invoke-CheckedCommand -Executable $powerShellCommand.Source -Arguments @("./scripts/Test-DeploymentTopology.ps1") -WorkingDirectory $repositoryRoot
