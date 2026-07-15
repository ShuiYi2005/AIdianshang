param(
    [string]$Version = (Get-Date -Format "yyyyMMdd-HHmmss"),
    [string]$EnvFile = "deployment/env/local.env",
    [string]$OutputRoot = "releases"
)

$ErrorActionPreference = "Stop"

$releaseDir = Join-Path $OutputRoot $Version
$imageDir = Join-Path $releaseDir "images"
New-Item -ItemType Directory -Force -Path $imageDir | Out-Null

powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile
docker compose --env-file $EnvFile -f deployment/docker-compose.yml build db-simulator agent-service

docker tag ai20-db-simulator:latest "ai20-db-simulator:$Version"
docker tag ai20-agent-service:latest "ai20-agent-service:$Version"

$images = @(
    @{ name = "postgres:15-alpine"; archive = "images/postgres_15-alpine.tar" },
    @{ name = "postgres:16-alpine"; archive = "images/postgres_16-alpine.tar" },
    @{ name = "redis:7-alpine"; archive = "images/redis_7-alpine.tar" },
    @{ name = "semitechnologies/weaviate:1.28.5"; archive = "images/semitechnologies_weaviate_1.28.5.tar" },
    @{ name = "langgenius/dify-api:1.14.2"; archive = "images/langgenius_dify-api_1.14.2.tar" },
    @{ name = "langgenius/dify-web:1.14.2"; archive = "images/langgenius_dify-web_1.14.2.tar" },
    @{ name = "langgenius/dify-plugin-daemon:0.6.1-local"; archive = "images/langgenius_dify-plugin-daemon_0.6.1-local.tar" },
    @{ name = "n8nio/n8n:latest"; archive = "images/n8nio_n8n_latest.tar" },
    @{ name = "ai20-db-simulator:$Version"; archive = "images/ai20-db-simulator_$Version.tar" },
    @{ name = "ai20-agent-service:$Version"; archive = "images/ai20-agent-service_$Version.tar" }
)

foreach ($image in $images) {
    docker image inspect $image.name | Out-Null
    docker save $image.name -o (Join-Path $releaseDir $image.archive)
}

foreach ($dir in @("deployment", "scripts", "tests", "evaluations", "knowledge", "prompts", "workflows")) {
    if (Test-Path -LiteralPath $dir) {
        Copy-Item -Recurse -Force -LiteralPath $dir -Destination (Join-Path $releaseDir $dir)
    }
}

foreach ($blocked in @("deployment/env/local.env", "deployment/.env")) {
    $blockedPath = Join-Path $releaseDir $blocked
    if (Test-Path -LiteralPath $blockedPath) {
        Remove-Item -Force -LiteralPath $blockedPath
    }
}

$manifest = [ordered]@{
    version = $Version
    createdAt = (Get-Date).ToString("o")
    composeFiles = @("deployment/docker-compose.yml", "deployment/docker-compose.release.yml")
    envExample = "deployment/env/release.env.example"
    requiredPorts = @(5001, 5003, 5004, 5678, 8001, 8010, 8080, 5433)
    images = $images
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $releaseDir "manifest.json")

if (Test-Path -LiteralPath "releases/latest") {
    Remove-Item -Recurse -Force -LiteralPath "releases/latest"
}
Copy-Item -Recurse -Force -LiteralPath $releaseDir -Destination "releases/latest"

powershell -ExecutionPolicy Bypass -File tests/deployment/verify_release_package.ps1 -ReleaseDir $releaseDir

"OK release package created: $releaseDir"
