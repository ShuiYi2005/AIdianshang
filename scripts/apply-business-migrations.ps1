param(
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$MigrationsDir = "deployment/business-db/migrations",
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

docker exec ai20-business-db-1 psql -U app_user -d app_business -v ON_ERROR_STOP=1 -c "create table if not exists ops.schema_migrations (version varchar(255) primary key, applied_at timestamptz not null default now());" | Out-Null

$files = Get-ChildItem -Path $MigrationsDir -Filter "*.sql" | Sort-Object Name
foreach ($file in $files) {
    $version = $file.BaseName
    $exists = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select 1 from ops.schema_migrations where version = '$version';"
    if ("$exists".Trim() -eq "1") {
        "SKIP migration $version"
        continue
    }

    Get-Content -Raw -Path $file.FullName | docker exec -i ai20-business-db-1 psql -U app_user -d app_business -v ON_ERROR_STOP=1 | Out-Null
    docker exec ai20-business-db-1 psql -U app_user -d app_business -v ON_ERROR_STOP=1 -c "insert into ops.schema_migrations(version) values ('$version') on conflict do nothing;" | Out-Null
    "OK migration $version"
}
