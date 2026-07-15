param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$BackupRoot = "backups"
)

$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $BackupRoot "release-$timestamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile

docker compose --env-file $EnvFile -f $ComposeFile exec -T db pg_dump -U postgres -d dify | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupDir "dify.sql")

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
docker compose --env-file $EnvFile -f $ComposeFile exec -T business-db pg_dump -U $businessUser -d $businessDb | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupDir "business.sql")
docker volume ls --format "{{.Name}}" | Where-Object { $_ -like "ai20_*" } | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupDir "volumes.txt")

"OK backup created: $backupDir"
