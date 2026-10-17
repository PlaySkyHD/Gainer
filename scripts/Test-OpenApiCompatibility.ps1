[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $BaseRef,

    [string] $ContractPath = "contracts/openapi/Gainer.Api.json",

    # Git path of the contract at the base revision. Separate from ContractPath so a
    # copy of the current contract outside the repository can still be compared.
    [string] $BaselineContractPath = "contracts/openapi/Gainer.Api.json",

    [string] $AcceptedChangesPath = "contracts/openapi/accepted-breaking-changes.json"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot

if ($BaseRef -notmatch '^[0-9a-fA-F]{7,40}$' -or $BaseRef -match '^0+$') {
    Write-Host "No usable base revision; compatibility comparison is skipped."
    return
}

Push-Location $repositoryRoot

try {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $baselineJson = & git show "${BaseRef}:${BaselineContractPath}" 2>$null
    $gitExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference

    if ($gitExitCode -ne 0) {
        Write-Host "No OpenAPI contract exists at the base revision; compatibility comparison is skipped."
        return
    }

    $baseline = ($baselineJson -join "`n") | ConvertFrom-Json -AsHashtable
    $current = Get-Content -Raw $ContractPath | ConvertFrom-Json -AsHashtable
    $errors = [System.Collections.Generic.List[string]]::new()
    $httpMethods = @("get", "put", "post", "delete", "options", "head", "patch", "trace")

    function ConvertTo-CanonicalJsonValue {
        param([AllowNull()] $Value)

        if ($null -eq $Value) {
            return "null"
        }

        return ConvertTo-Json -InputObject $Value -Compress -Depth 20
    }

    foreach ($path in $baseline.paths.Keys) {
        if (-not $current.paths.ContainsKey($path)) {
            $errors.Add("Removed path: $path")
            continue
        }

        foreach ($method in $httpMethods) {
            if (-not $baseline.paths[$path].ContainsKey($method)) {
                continue
            }

            if (-not $current.paths[$path].ContainsKey($method)) {
                $errors.Add("Removed operation: $($method.ToUpperInvariant()) $path")
                continue
            }

            $oldResponses = $baseline.paths[$path][$method].responses
            $newResponses = $current.paths[$path][$method].responses
            foreach ($status in $oldResponses.Keys) {
                if (-not $newResponses.ContainsKey($status)) {
                    $errors.Add("Removed response $status from $($method.ToUpperInvariant()) $path")
                    continue
                }

                $oldContent = $oldResponses[$status].content
                $newContent = $newResponses[$status].content
                if ($null -eq $oldContent) {
                    continue
                }

                foreach ($mediaType in $oldContent.Keys) {
                    if ($null -eq $newContent -or -not $newContent.ContainsKey($mediaType)) {
                        $errors.Add("Removed media type $mediaType from response $status of $($method.ToUpperInvariant()) $path")
                    }
                }
            }
        }
    }

    $oldSchemas = $baseline.components.schemas
    $newSchemas = $current.components.schemas
    foreach ($schemaName in $oldSchemas.Keys) {
        if (-not $newSchemas.ContainsKey($schemaName)) {
            $errors.Add("Removed schema: $schemaName")
            continue
        }

        $oldProperties = $oldSchemas[$schemaName].properties
        $newProperties = $newSchemas[$schemaName].properties
        if ($null -ne $oldProperties) {
            foreach ($propertyName in $oldProperties.Keys) {
                if ($null -eq $newProperties -or -not $newProperties.ContainsKey($propertyName)) {
                    $errors.Add("Removed property: $schemaName.$propertyName")
                    continue
                }

                foreach ($shapeKey in @("type", "format", '$ref')) {
                    $oldShape = ConvertTo-CanonicalJsonValue $oldProperties[$propertyName][$shapeKey]
                    $newShape = ConvertTo-CanonicalJsonValue $newProperties[$propertyName][$shapeKey]
                    if ($oldShape -cne $newShape) {
                        $errors.Add("Changed $shapeKey of property: $schemaName.$propertyName")
                    }
                }
            }
        }

        $oldRequired = @($oldSchemas[$schemaName].required)
        $newRequired = @($newSchemas[$schemaName].required)
        foreach ($requiredProperty in $newRequired) {
            if ($requiredProperty -notin $oldRequired) {
                $errors.Add("Added required property: $schemaName.$requiredProperty")
            }
        }
    }

    $acceptedMessages = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $AcceptedChangesPath) {
        $acceptedChanges = Get-Content -Raw -LiteralPath $AcceptedChangesPath | ConvertFrom-Json -AsHashtable
        $pinnedBaseRef = $acceptedChanges["baseRef"]
        $accepted = @($acceptedChanges["accepted"])

        if ($accepted.Count -gt 0) {
            if ([string]::IsNullOrWhiteSpace($acceptedChanges["reason"])) {
                throw "$AcceptedChangesPath lists accepted breaking changes without a reason."
            }

            if ($pinnedBaseRef -and -not ($BaseRef.StartsWith($pinnedBaseRef, [StringComparison]::OrdinalIgnoreCase) -or $pinnedBaseRef.StartsWith($BaseRef, [StringComparison]::OrdinalIgnoreCase))) {
                Write-Warning "Accepted breaking changes are pinned to base $pinnedBaseRef and are ignored for base $BaseRef."
            }
            else {
                foreach ($acceptedMessage in $accepted) {
                    if ($acceptedMessage -isnot [string] -or [string]::IsNullOrWhiteSpace($acceptedMessage)) {
                        throw "$AcceptedChangesPath contains an empty or non-string entry in accepted."
                    }

                    [void]$acceptedMessages.Add($acceptedMessage)
                }

                Write-Host "Accepted breaking changes from ${AcceptedChangesPath}: $($acceptedChanges["reason"])"
            }
        }
    }

    $matchedMessages = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $unacceptedErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($errorMessage in $errors) {
        if ($acceptedMessages.Contains($errorMessage)) {
            [void]$matchedMessages.Add($errorMessage)
            Write-Host "Accepted breaking change: $errorMessage"
        }
        else {
            $unacceptedErrors.Add($errorMessage)
        }
    }

    foreach ($acceptedMessage in $acceptedMessages) {
        if (-not $matchedMessages.Contains($acceptedMessage)) {
            Write-Warning "Accepted breaking change is no longer detected and can be removed from ${AcceptedChangesPath}: $acceptedMessage"
        }
    }

    if ($unacceptedErrors.Count -gt 0) {
        throw "Incompatible OpenAPI changes detected:`n - $($unacceptedErrors -join "`n - ")"
    }

    Write-Host "OpenAPI compatibility check passed."
}
finally {
    Pop-Location
}
