[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$userProfile = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($userProfile)) { $userProfile = $env:HOME }
if ([string]::IsNullOrWhiteSpace($userProfile)) { throw "A user profile directory is required." }
$packageRoot = Join-Path $userProfile ".nuget/packages"
$allowed = @(
    "Apache-2.0",
    "BSD-3-Clause",
    "MIT",
    "PostgreSQL",
    "license.txt",
    "https://github.com/dotnet/corefx/blob/master/LICENSE.TXT"
)
$packageSpecificLicenses = @{
    "SixLabors.ImageSharp" = "LICENSE"
}
$findings = [System.Collections.Generic.List[string]]::new()
$checked = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

Get-ChildItem -LiteralPath $repositoryRoot -Recurse -Filter "project.assets.json" -File | Where-Object {
    $_.FullName -notmatch '[\\/]node_modules[\\/]'
} | ForEach-Object {
    $assets = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    foreach ($library in $assets.libraries.PSObject.Properties) {
        if ($library.Value.type -eq "project") { continue }
        if (-not $checked.Add($library.Name)) { continue }
        $parts = $library.Name -split '/', 2
        if ($parts.Count -ne 2) { continue }
        $id = $parts[0].ToLowerInvariant()
        $nuspec = Join-Path $packageRoot (Join-Path $id (Join-Path $parts[1] "$id.nuspec"))
        if (-not (Test-Path -LiteralPath $nuspec)) {
            $findings.Add("$($library.Name): package metadata is unavailable")
            continue
        }
        [xml] $metadata = Get-Content -LiteralPath $nuspec
        $license = $metadata.package.metadata.license.'#text'
        if (-not $license) { $license = $metadata.package.metadata.licenseUrl }
        $packageSpecificLicense = $packageSpecificLicenses[$parts[0]]
        if (-not $license -or (($allowed -notcontains $license) -and $packageSpecificLicense -ne $license)) {
            $findings.Add("$($library.Name): unapproved or missing license '$license'")
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    throw "NuGet license policy failed."
}
Write-Host "NuGet license policy passed for $($checked.Count) locked packages."
