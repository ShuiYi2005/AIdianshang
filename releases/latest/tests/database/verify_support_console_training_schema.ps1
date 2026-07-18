param(
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

function Start-BusinessDatabase {
    if ($EnvFile) {
        & docker compose --env-file $EnvFile -f $ComposeFile up -d business-db 1>$null
    } else {
        & docker compose -f $ComposeFile up -d business-db 1>$null
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to start business-db with Docker Compose"
    }
}

Start-BusinessDatabase

$deadline = (Get-Date).AddSeconds(60)
do {
    $status = docker inspect -f "{{.State.Health.Status}}" ai20-business-db-1 2>$null
    if ($status -eq "healthy") {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($status -ne "healthy") {
    throw "business-db did not become healthy; status=$status"
}

$tableOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name from information_schema.tables where table_schema in ('knowledge', 'audit') and table_type = 'BASE TABLE' order by 1;"
$tables = $tableOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredTables = @(
    "knowledge.training_topics",
    "knowledge.training_assets",
    "knowledge.training_versions",
    "audit.console_action_logs"
)

foreach ($table in $requiredTables) {
    if ($tables -notcontains $table) {
        throw "Missing required table: $table"
    }
}

$indexOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select schemaname || '.' || indexname from pg_indexes where schemaname in ('knowledge', 'audit') order by 1;"
$indexes = $indexOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredIndexes = @(
    "knowledge.idx_training_topics_status_updated_at",
    "knowledge.idx_training_assets_topic_id",
    "knowledge.uq_training_versions_topic_version",
    "audit.idx_console_action_logs_target_created_at"
)

foreach ($index in $requiredIndexes) {
    if ($indexes -notcontains $index) {
        throw "Missing required index: $index"
    }
}

"OK support-console training schema verified"
