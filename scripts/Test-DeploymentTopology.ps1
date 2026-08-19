[CmdletBinding()]
param(
    [string]$ComposeFile = "deploy/compose.yaml"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composePath = Join-Path $repositoryRoot $ComposeFile
$temporaryEnvironment = @{
    GAINER_PUBLIC_ORIGIN = "https://gainer.markfort.xyz"
    GAINER_EDGE_PORT = "8081"
    GAINER_SITE_ADDRESS = ":80"
    GAINER_SECRETS_DIR = (Join-Path $repositoryRoot "deploy")
    AZURE_STORAGE_ACCOUNT_NAME = "topology-validation"
    RESTIC_REPOSITORY = "azure:topology-validation:/gainer"
}
$previousEnvironment = @{}

try {
    foreach ($entry in $temporaryEnvironment.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }

    $rendered = & docker compose -f $composePath config --format json
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose config failed with exit code $LASTEXITCODE."
    }

    $configuration = $rendered | ConvertFrom-Json
    $edgePorts = @($configuration.services.edge.ports)
    if ($edgePorts.Count -ne 1) {
        throw "Edge must publish exactly one port, but publishes $($edgePorts.Count)."
    }

    $edgePort = $edgePorts[0]
    if ($edgePort.host_ip -ne "127.0.0.1" -or
        [string]$edgePort.published -ne "8081" -or
        [string]$edgePort.target -ne "80") {
        throw "Edge must bind 127.0.0.1:8081 to container port 80."
    }

    foreach ($serviceName in @("api", "migrator", "postgres")) {
        $publishedPorts = $configuration.services.$serviceName.PSObject.Properties["ports"]
        if ($null -ne $publishedPorts -and @($publishedPorts.Value).Count -ne 0) {
            throw "Service '$serviceName' must not publish a host port."
        }
    }

    if ($configuration.services.edge.environment.GAINER_SITE_ADDRESS -ne ":80") {
        throw "The internal edge must serve plain HTTP on port 80."
    }

    $postgresDataVolume = @(
        @($configuration.services.postgres.volumes) |
            Where-Object { $_.target -eq "/var/lib/postgresql" }
    )
    if ($postgresDataVolume.Count -ne 1) {
        throw "PostgreSQL 18 data must be mounted at /var/lib/postgresql."
    }

    Write-Host "Deployment topology passed: only 127.0.0.1:8081 is published."
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
}
