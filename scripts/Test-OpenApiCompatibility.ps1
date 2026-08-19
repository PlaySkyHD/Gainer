[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $BaseRef,

    [string] $ContractPath = "contracts/openapi/Gainer.Api.json"
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
    $baselineJson = & git show "${BaseRef}:${ContractPath}" 2>$null
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
                    if ($oldProperties[$propertyName][$shapeKey] -ne $newProperties[$propertyName][$shapeKey]) {
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

    if ($errors.Count -gt 0) {
        throw "Incompatible OpenAPI changes detected:`n - $($errors -join "`n - ")"
    }

    Write-Host "OpenAPI compatibility check passed."
}
finally {
    Pop-Location
}
