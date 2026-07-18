param(
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$EnvFile = "deployment/env/local.env.example"
)

$ErrorActionPreference = "Stop"

$configJson = docker compose --env-file $EnvFile -f $ComposeFile config --format json
if ($LASTEXITCODE -ne 0) { throw "Docker Compose configuration is invalid for the tracked local template" }
$config = $configJson | ConvertFrom-Json

foreach ($serviceName in @("dify-api", "dify-worker", "dify-web", "plugin-daemon")) {
    $service = $config.services.$serviceName
    if ($service.pull_policy -eq "never") {
        throw "$serviceName prevents a new online Docker host from pulling its public image"
    }
}

if ($config.services.n8n.image -ne "n8nio/n8n:2.22.5") {
    throw "n8n must use the verified pinned image n8nio/n8n:2.22.5"
}

foreach ($serviceName in @("db-simulator", "agent-service", "support-console")) {
    $service = $config.services.$serviceName
    if (!$service.build) {
        throw "$serviceName must declare a tracked repository build context"
    }
}

$startScript = Get-Content -LiteralPath "scripts/start-local.ps1" -Raw
if ($startScript -notmatch "up -d --build") {
    throw "the documented local startup path must build project services from source"
}
$databaseStartIndex = $startScript.IndexOf("up -d business-db")
$migrationIndex = $startScript.IndexOf("scripts/apply-business-migrations.ps1")
$fullStartupIndex = $startScript.IndexOf("up -d --build")
if ($databaseStartIndex -lt 0 -or $migrationIndex -lt $databaseStartIndex -or $fullStartupIndex -lt $migrationIndex) {
    throw "local startup must run business-db, migrations, and full stack in that order"
}

foreach ($serviceName in @("db-simulator", "agent-service")) {
    if ($config.services.$serviceName.build.args.BASE_IMAGE -ne "python:3.12.11-slim") {
        throw "$serviceName must use the pinned python:3.12.11-slim build image"
    }
}

$consoleDockerfile = Get-Content -LiteralPath "services/support-console/Dockerfile" -Raw
if ($consoleDockerfile -notmatch "FROM node:20.20.2-alpine AS build" -or $consoleDockerfile -notmatch "(?m)^FROM node:20.20.2-alpine$") {
    throw "support-console must use pinned node:20.20.2-alpine images"
}

$releaseCompose = Get-Content -LiteralPath "deployment/docker-compose.release.yml" -Raw
if ($releaseCompose -notmatch "(?ms)^  support-console:\r?\n") {
    throw "offline release override is missing support-console"
}
if ($releaseCompose -notmatch "(?ms)^  support-console:.*?^    build: null\r?$" -or $releaseCompose -notmatch "(?ms)^  support-console:.*?^    pull_policy: never\r?$") {
    throw "offline release must disable support-console source builds and image pulls"
}

$packageScript = Get-Content -LiteralPath "scripts/package-release.ps1" -Raw
if ($packageScript -notmatch 'ai20-support-console:\$Version' -or $packageScript -notmatch "SUPPORT_CONSOLE_IMAGE") {
    throw "offline package does not version and configure the support-console image"
}
if ($packageScript -notmatch '(?ms)docker compose .* build db-simulator agent-service support-console\r?\nif \(\$LASTEXITCODE -ne 0\)') {
    throw "release packaging must stop when a project image build fails"
}

$manifest = Get-Content -LiteralPath "deployment/release-manifest.example.json" -Raw | ConvertFrom-Json
if (!($manifest.images.name -contains "ai20-support-console:latest")) {
    throw "release manifest example does not declare ai20-support-console"
}

$releaseEnvTemplate = Get-Content -LiteralPath "deployment/env/release.env.example" -Raw
if ($releaseEnvTemplate -notmatch "(?m)^APP_ENV=prod$") {
    throw "release environment template must use APP_ENV=prod so placeholder secrets are rejected"
}

$installScript = Get-Content -LiteralPath "scripts/install-release.ps1" -Raw
$releaseDatabaseStartIndex = $installScript.IndexOf("up -d business-db")
$releaseMigrationIndex = $installScript.IndexOf("scripts/apply-business-migrations.ps1")
$releaseFullStartupIndex = $installScript.IndexOf("up -d`n")
if ($releaseDatabaseStartIndex -lt 0 -or $releaseMigrationIndex -lt $releaseDatabaseStartIndex -or $releaseFullStartupIndex -lt $releaseMigrationIndex) {
    throw "release installation must run business-db, migrations, and full stack in that order"
}

$readme = Get-Content -LiteralPath "README.md" -Raw
if ($readme -notmatch "scripts/start-local.ps1") {
    throw "README does not provide the one-command local clone startup path"
}

"OK GitHub clone readiness verified"
