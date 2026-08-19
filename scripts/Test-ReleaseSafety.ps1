[CmdletBinding()]
param(
    [string[]] $ArtifactPaths = @(),
    [switch] $CheckRepositoryPolicy
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$violations = [System.Collections.Generic.List[string]]::new()

function Get-RepositoryRelativePath([string] $Path) {
    return $Path.Substring($repositoryRoot.Length).TrimStart([char[]]@([char]92, [char]47))
}

function Add-Matches {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Pattern,
        [Parameter(Mandatory)] [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $violations.Add("Missing release artifact path: $Path")
        return
    }

    Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $_.Length -le 10MB -and $_.Extension -notin @(".dll", ".pdb", ".so", ".png", ".jpg", ".jpeg", ".webp", ".woff2")
    } | ForEach-Object {
        $match = Select-String -LiteralPath $_.FullName -Pattern $Pattern -AllMatches -ErrorAction SilentlyContinue
        if ($match) {
            $relative = Get-RepositoryRelativePath $_.FullName
            $violations.Add("$Label in $relative")
        }
    }
}

foreach ($artifactPath in ($ArtifactPaths | ForEach-Object { $_ -split ',' })) {
    $resolved = if ([System.IO.Path]::IsPathRooted($artifactPath)) {
        $artifactPath
    } else {
        Join-Path $repositoryRoot $artifactPath
    }
    Add-Matches -Path $resolved -Pattern 'sk-(?:proj-|svcacct-)?[A-Za-z0-9_]{32,}' -Label "Possible OpenAI secret"
    Add-Matches -Path $resolved -Pattern '(?i)(password|apikey|api_key|secret)\s*[=:]\s*["''][^"''$\r\n]{8,}["'']|Password=[A-Za-z0-9+/=_-]{16,};' -Label "Possible embedded credential"
    Add-Matches -Path $resolved -Pattern '(?i)(athlete|first-private|second-private)@?example\.test|Correct-horse|secret-test-key' -Label "Test identity or fixture"
    Add-Matches -Path $resolved -Pattern '(?i)Diagnostiziere meine|Wie entwickelt sich mein Gewicht|Iss 2200 kcal' -Label "Coach prompt or answer fixture"
}

if ($CheckRepositoryPolicy) {
    $policyFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/](node_modules|bin|obj|out|artifacts|\.git)[\\/]' -and
        $_.Extension -in @(".csproj", ".props", ".json", ".lock")
    }
    foreach ($file in $policyFiles) {
        if (Select-String -LiteralPath $file.FullName -Pattern '(?i)pgvector|ragflow|langchain' -Quiet) {
            $relative = Get-RepositoryRelativePath $file.FullName
            $violations.Add("Forbidden MVP RAG/vector dependency in $relative")
        }
    }

    $media = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/](node_modules|bin|obj|out|artifacts|\.git)[\\/]' -and
        $_.Extension -in @(".gif", ".jpg", ".jpeg", ".mp4", ".webm", ".mov")
    }
    foreach ($file in $media) {
        $relative = Get-RepositoryRelativePath $file.FullName
        $violations.Add("Unapproved exercise/media asset in $relative")
    }

    $productionSources = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "src") -Recurse -Filter "*.cs" -File
    foreach ($file in $productionSources) {
        $source = Get-Content -LiteralPath $file.FullName -Raw
        $loggingCalls = [regex]::Matches(
            $source,
            'logger\.Log(?:Trace|Debug|Information|Warning|Error|Critical)\s*\((?s:.*?)\);',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($call in $loggingCalls) {
            if ($call.Value -match '(?i)\b(question|prompt|facts?|email|password|apiKey|weightKg|caloriesKcal)\b') {
                $relative = Get-RepositoryRelativePath $file.FullName
                $violations.Add("Potential personal or secret value in production log call in $relative")
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    throw "Release safety verification failed with $($violations.Count) finding(s)."
}

Write-Host "Release safety verification passed."
