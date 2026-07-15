param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

$difyBackup = Join-Path $BackupDir "dify.sql"
$businessBackup = Join-Path $BackupDir "business.sql"
if (!(Test-Path -LiteralPath $difyBackup)) {
    throw "Missing backup file: $difyBackup"
}
if (!(Test-Path -LiteralPath $businessBackup)) {
    throw "Missing backup file: $businessBackup"
}

powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile

$envValues = @{}
Get-Content -LiteralPath $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and !$line.StartsWith("#")) {
        $parts = $line.Split("=", 2)
        if ($parts.Count -eq 2) {
            $envValues[$parts[0]] = $parts[1]
        }
    }
}

$businessUser = $envValues["BUSINESS_DB_USER"]
$businessDb = $envValues["BUSINESS_DB_NAME"]

Get-Content -Raw -LiteralPath $difyBackup | docker compose --env-file $EnvFile -f $ComposeFile exec -T db psql -U postgres -d dify
Get-Content -Raw -LiteralPath $businessBackup | docker compose --env-file $EnvFile -f $ComposeFile exec -T business-db psql -U $businessUser -d $businessDb

powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile $EnvFile -ComposeFile $ComposeFile

"OK backup restored: $BackupDir"
