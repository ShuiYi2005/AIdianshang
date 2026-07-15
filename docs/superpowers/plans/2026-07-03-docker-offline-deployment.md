# Docker Offline Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable release package so this AI customer-service project can be exported from one Windows machine and run on another machine with Docker Desktop, including image loading, environment setup, data initialization, verification, and rollback.

**Architecture:** Keep all platform source code untouched and place deployment logic under `deployment/`, `scripts/`, `docs/`, and `tests/`. Build local business images, collect required third-party images, save them into tar archives, generate a release manifest, and provide install/verify/backup/restore scripts that reuse the existing `deployment/docker-compose.yml` and `scripts/verify.ps1` validation chain.

**Tech Stack:** Docker Compose, PowerShell 5+, PostgreSQL containers, Redis, Weaviate, Dify images, n8n image, FastAPI service images, existing project verification scripts.

---

## Current Baseline

The project currently supports Docker Compose based local deployment through:

- `deployment/docker-compose.yml`
- `deployment/env/local.env`
- `scripts/verify.ps1`
- `services/db-simulator/Dockerfile`
- `services/agent-service/Dockerfile`

It does not yet support a complete cross-machine package because there is no release manifest, no image export/import script, no target-machine setup script, no volume backup/restore script, and no release-specific verification wrapper.

## Acceptance Criteria

- A source machine can run one command to build local images and create a release directory under `releases/`.
- The release directory contains Docker image archives, deployment compose files, environment examples, scripts, docs, and a machine-readable manifest.
- A target machine can run one command to load images, create local env files, start Docker Compose, and run verification.
- No secrets are baked into Docker images or release archives by default.
- Data directories and Docker volumes are not copied by default; database backup/restore is a separate explicit action.
- Rollback is possible by stopping the release compose stack and loading the previous package or restoring database backups.
- Existing validation remains the source of truth: `scripts/verify.ps1 -EnvFile <env> -ComposeFile <compose>`.

## File Structure

- Create: `deployment/docker-compose.release.yml`
  - Release-oriented Compose overlay. It pins image names/tags from the manifest and disables build contexts so target machines do not need source builds.
- Create: `deployment/env/release.env.example`
  - Safe environment template for the target machine. Contains placeholders only.
- Create: `deployment/release-manifest.example.json`
  - Example manifest schema documenting package version, image list, compose files, required ports, and verification commands.
- Create: `scripts/package-release.ps1`
  - Runs preflight checks, builds local service images, saves all required images to `releases/<version>/images/*.tar`, copies deploy assets, and writes `manifest.json`.
- Create: `scripts/install-release.ps1`
  - Loads images, creates an env file from template if missing, validates Docker, starts the stack, and runs verification.
- Create: `scripts/backup-release-data.ps1`
  - Explicitly backs up Dify DB, business DB, n8n data, and named volume metadata before upgrade or migration.
- Create: `scripts/restore-release-data.ps1`
  - Explicitly restores DB backups and documents what cannot be restored automatically.
- Create: `tests/deployment/verify_release_package.ps1`
  - Static verification for package completeness without starting services.
- Modify: `scripts/verify.ps1`
  - Keep current behavior, but ensure `-ComposeFile` and `-EnvFile` are passed to all nested scripts that support them.
- Modify: `docs/OPERATIONS.md`
  - Add release package runbook: package, transfer, install, verify, backup, restore, rollback.
- Modify: `docs/CONFIGURATION.md`
  - Add release environment rules and config priority for target machines.
- Do not modify: `platform/`
- Do not modify: Dify or n8n platform source.
- Do not put business logic in: `workflows/` or `deployment/`.

## Release Boundary

The release package should include:

- `deployment/docker-compose.yml`
- `deployment/docker-compose.release.yml`
- `deployment/business-db/init/*.sql`
- `deployment/env/release.env.example`
- `scripts/install-release.ps1`
- `scripts/verify.ps1`
- `scripts/check-env.ps1`
- `scripts/check-secrets.ps1`
- `scripts/apply-business-migrations.ps1`
- `tests/database/*.ps1`
- `tests/services/*.ps1`
- `tests/assets/*.ps1`
- `tests/evaluation/*.ps1`
- `evaluations/`
- `knowledge/`
- `prompts/`
- `workflows/`
- Docker image tar files
- `manifest.json`

The release package should not include:

- `deployment/env/local.env`
- `deployment/.env`
- database volume data
- user-uploaded Dify storage by default
- API keys, passwords, or generated secrets
- local backup archives unless explicitly requested by a backup command

## Image List

The package must include these images:

- `postgres:15-alpine`
- `postgres:16-alpine`
- `redis:7-alpine`
- `semitechnologies/weaviate:1.28.5`
- `langgenius/dify-api:1.14.2`
- `langgenius/dify-web:1.14.2`
- `langgenius/dify-plugin-daemon:0.6.1-local`
- `n8nio/n8n:latest` initially, then replace with a pinned version in a follow-up task.
- `ai20-db-simulator:<releaseVersion>`
- `ai20-agent-service:<releaseVersion>`

## Task 1: Add Release Compose Overlay

**Files:**
- Create: `deployment/docker-compose.release.yml`
- Test: `tests/deployment/verify_release_package.ps1`

- [ ] **Step 1: Write the static package test first**

Create `tests/deployment/verify_release_package.ps1`:

```powershell
param(
    [string]$ReleaseDir = "releases/latest"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release directory not found: $ReleaseDir"
}

$requiredFiles = @(
    "manifest.json",
    "deployment/docker-compose.yml",
    "deployment/docker-compose.release.yml",
    "deployment/env/release.env.example",
    "scripts/install-release.ps1",
    "scripts/verify.ps1",
    "scripts/check-env.ps1",
    "scripts/check-secrets.ps1",
    "scripts/apply-business-migrations.ps1"
)

foreach ($file in $requiredFiles) {
    $path = Join-Path $ReleaseDir $file
    if (!(Test-Path -LiteralPath $path)) {
        throw "Missing release file: $file"
    }
}

$manifestPath = Join-Path $ReleaseDir "manifest.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

if (!$manifest.version) {
    throw "manifest.json missing version"
}

if (!$manifest.images -or $manifest.images.Count -lt 1) {
    throw "manifest.json missing images"
}

foreach ($image in $manifest.images) {
    $archivePath = Join-Path $ReleaseDir $image.archive
    if (!(Test-Path -LiteralPath $archivePath)) {
        throw "Missing image archive: $($image.archive)"
    }
}

"OK release package verified: $ReleaseDir"
```

- [ ] **Step 2: Run the test and confirm it fails before implementation**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/deployment/verify_release_package.ps1 -ReleaseDir releases/latest
```

Expected:

```text
Release directory not found: releases/latest
```

- [ ] **Step 3: Create the release Compose overlay**

Create `deployment/docker-compose.release.yml`:

```yaml
name: ai20

services:
  dify-api:
    image: langgenius/dify-api:1.14.2
    pull_policy: never

  dify-worker:
    image: langgenius/dify-api:1.14.2
    pull_policy: never

  dify-web:
    image: langgenius/dify-web:1.14.2
    pull_policy: never

  plugin-daemon:
    image: langgenius/dify-plugin-daemon:0.6.1-local
    pull_policy: never

  n8n:
    image: n8nio/n8n:latest
    pull_policy: never

  db:
    image: postgres:15-alpine
    pull_policy: never

  business-db:
    image: postgres:16-alpine
    pull_policy: never

  redis:
    image: redis:7-alpine
    pull_policy: never

  weaviate:
    image: semitechnologies/weaviate:1.28.5
    pull_policy: never

  db-simulator:
    image: ${DB_SIMULATOR_IMAGE:-ai20-db-simulator:latest}
    pull_policy: never
    build: null

  agent-service:
    image: ${AGENT_SERVICE_IMAGE:-ai20-agent-service:latest}
    pull_policy: never
    build: null
```

- [ ] **Step 4: Validate Compose config**

Run:

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml -f deployment/docker-compose.release.yml config
```

Expected:

```text
The command exits with code 0 and shows no build sections for db-simulator or agent-service.
```

## Task 2: Add Release Environment Template

**Files:**
- Create: `deployment/env/release.env.example`
- Modify: `docs/CONFIGURATION.md`

- [ ] **Step 1: Create the release env template**

Create `deployment/env/release.env.example`:

```text
APP_ENV=local
POSTGRES_PASSWORD=replace-with-target-machine-secret
DIFY_SECRET_KEY=replace-with-target-machine-secret
DIFY_INIT_PASSWORD=replace-with-target-machine-secret
DIFY_INNER_API_KEY=replace-with-target-machine-secret
PLUGIN_SERVER_KEY=replace-with-target-machine-secret
N8N_ENCRYPTION_KEY=replace-with-target-machine-secret
REDIS_PASSWORD=
BUSINESS_DB_USER=app_user
BUSINESS_DB_PASSWORD=replace-with-target-machine-secret
BUSINESS_DB_NAME=app_business
DB_SIMULATOR_IMAGE=ai20-db-simulator:latest
AGENT_SERVICE_IMAGE=ai20-agent-service:latest
DB_SIMULATOR_BASE_IMAGE=python:3.12-slim
AGENT_SERVICE_BASE_IMAGE=python:3.12-slim
```

- [ ] **Step 2: Verify env validation catches missing or weak production secrets**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile deployment/env/release.env.example
```

Expected:

```text
OK env file verified: deployment/env/release.env.example
```

- [ ] **Step 3: Document release config priority**

Append to `docs/CONFIGURATION.md`:

```markdown
## Release Package Environment

For cross-machine Docker deployment, the target machine must create its own `deployment/env/release.env` from `deployment/env/release.env.example`.

Priority from high to low:

1. Target-machine secret manager or shell environment variables.
2. `deployment/env/release.env`.
3. `deployment/env/release.env.example` for documentation only.
4. Application defaults only for non-sensitive values.

Secrets must not be baked into Docker images, `manifest.json`, or release archives.
```

## Task 3: Add Release Manifest Template

**Files:**
- Create: `deployment/release-manifest.example.json`

- [ ] **Step 1: Create the manifest example**

Create `deployment/release-manifest.example.json`:

```json
{
  "version": "2026.07.03-local",
  "createdAt": "2026-07-03T00:00:00+08:00",
  "composeFiles": [
    "deployment/docker-compose.yml",
    "deployment/docker-compose.release.yml"
  ],
  "envExample": "deployment/env/release.env.example",
  "requiredPorts": [5001, 5003, 5004, 5678, 8001, 8010, 8080, 5433],
  "images": [
    {"name": "postgres:15-alpine", "archive": "images/postgres_15-alpine.tar"},
    {"name": "postgres:16-alpine", "archive": "images/postgres_16-alpine.tar"},
    {"name": "redis:7-alpine", "archive": "images/redis_7-alpine.tar"},
    {"name": "semitechnologies/weaviate:1.28.5", "archive": "images/semitechnologies_weaviate_1.28.5.tar"},
    {"name": "langgenius/dify-api:1.14.2", "archive": "images/langgenius_dify-api_1.14.2.tar"},
    {"name": "langgenius/dify-web:1.14.2", "archive": "images/langgenius_dify-web_1.14.2.tar"},
    {"name": "langgenius/dify-plugin-daemon:0.6.1-local", "archive": "images/langgenius_dify-plugin-daemon_0.6.1-local.tar"},
    {"name": "n8nio/n8n:latest", "archive": "images/n8nio_n8n_latest.tar"},
    {"name": "ai20-db-simulator:latest", "archive": "images/ai20-db-simulator_latest.tar"},
    {"name": "ai20-agent-service:latest", "archive": "images/ai20-agent-service_latest.tar"}
  ],
  "verifyCommand": "powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/release.env -ComposeFile deployment/docker-compose.yml"
}
```

- [ ] **Step 2: Validate JSON**

Run:

```powershell
Get-Content -Raw deployment/release-manifest.example.json | ConvertFrom-Json | Out-Null
```

Expected:

```text
The command exits with code 0.
```

## Task 4: Add Package Script

**Files:**
- Create: `scripts/package-release.ps1`
- Test: `tests/deployment/verify_release_package.ps1`

- [ ] **Step 1: Create `scripts/package-release.ps1`**

```powershell
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
    $archivePath = Join-Path $releaseDir $image.archive
    docker save $image.name -o $archivePath
}

$dirsToCopy = @("deployment", "scripts", "tests", "evaluations", "knowledge", "prompts", "workflows")
foreach ($dir in $dirsToCopy) {
    if (Test-Path -LiteralPath $dir) {
        Copy-Item -Recurse -Force -LiteralPath $dir -Destination (Join-Path $releaseDir $dir)
    }
}

$blockedSecretFiles = @(
    "deployment/env/local.env",
    "deployment/.env"
)

foreach ($blocked in $blockedSecretFiles) {
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
    verifyCommand = "powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/release.env -ComposeFile deployment/docker-compose.yml"
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $releaseDir "manifest.json")

if (Test-Path -LiteralPath "releases/latest") {
    Remove-Item -Force -Recurse -LiteralPath "releases/latest"
}
Copy-Item -Recurse -Force -LiteralPath $releaseDir -Destination "releases/latest"

powershell -ExecutionPolicy Bypass -File tests/deployment/verify_release_package.ps1 -ReleaseDir $releaseDir

"OK release package created: $releaseDir"
```

- [ ] **Step 2: Run package script**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-release.ps1 -Version 20260703-local -EnvFile deployment/env/local.env
```

Expected:

```text
OK release package verified: releases/20260703-local
OK release package created: releases/20260703-local
```

## Task 5: Add Target Install Script

**Files:**
- Create: `scripts/install-release.ps1`

- [ ] **Step 1: Create `scripts/install-release.ps1`**

```powershell
param(
    [string]$ReleaseDir = ".",
    [string]$EnvFile = "deployment/env/release.env",
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

$manifestPath = Join-Path $ReleaseDir "manifest.json"
if (!(Test-Path -LiteralPath $manifestPath)) {
    throw "manifest.json not found in release directory: $ReleaseDir"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

docker info | Out-Null

foreach ($image in $manifest.images) {
    $archivePath = Join-Path $ReleaseDir $image.archive
    if (!(Test-Path -LiteralPath $archivePath)) {
        throw "Image archive not found: $($image.archive)"
    }
    docker load -i $archivePath | Out-Null
}

$envPath = Join-Path $ReleaseDir $EnvFile
$envExamplePath = Join-Path $ReleaseDir "deployment/env/release.env.example"

if (!(Test-Path -LiteralPath $envPath)) {
    Copy-Item -Force -LiteralPath $envExamplePath -Destination $envPath
    throw "Created $EnvFile from template. Edit secrets, then run install again."
}

Push-Location $ReleaseDir
try {
    powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile
    docker compose --env-file $EnvFile -f deployment/docker-compose.yml -f deployment/docker-compose.release.yml up -d

    if (!$SkipVerify) {
        powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile $EnvFile -ComposeFile deployment/docker-compose.yml
    }
}
finally {
    Pop-Location
}

"OK release installed from $ReleaseDir"
```

- [ ] **Step 2: Test install script against package on the source machine**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File releases/20260703-local/scripts/install-release.ps1 -ReleaseDir releases/20260703-local -SkipVerify
```

Expected on first run:

```text
Created deployment/env/release.env from template. Edit secrets, then run install again.
```

- [ ] **Step 3: Copy local env for source-machine smoke test only**

Run:

```powershell
Copy-Item -Force deployment/env/local.env releases/20260703-local/deployment/env/release.env
powershell -ExecutionPolicy Bypass -File releases/20260703-local/scripts/install-release.ps1 -ReleaseDir releases/20260703-local -SkipVerify
```

Expected:

```text
OK release installed from releases/20260703-local
```

## Task 6: Fix Verification Compose Overlay Support

**Files:**
- Modify: `scripts/verify.ps1`

- [ ] **Step 1: Update verify script parameters**

Change `scripts/verify.ps1` so it accepts an optional release overlay:

```powershell
param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$ComposeOverlayFile = ""
)
```

- [ ] **Step 2: Add a compose argument helper**

Add after `$ErrorActionPreference = "Stop"`:

```powershell
$composeArgs = @("--env-file", $EnvFile, "-f", $ComposeFile)
if (![string]::IsNullOrWhiteSpace($ComposeOverlayFile)) {
    $composeArgs += @("-f", $ComposeOverlayFile)
}
```

- [ ] **Step 3: Replace direct compose calls**

Replace:

```powershell
docker compose --env-file $EnvFile -f $ComposeFile config | Out-Null
docker compose --env-file $EnvFile -f $ComposeFile up -d | Out-Null
```

With:

```powershell
docker compose @composeArgs config | Out-Null
docker compose @composeArgs up -d | Out-Null
```

- [ ] **Step 4: Run local verification without overlay**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

Expected:

```text
OK full verification completed
```

- [ ] **Step 5: Run release verification with overlay**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env -ComposeFile deployment/docker-compose.yml -ComposeOverlayFile deployment/docker-compose.release.yml
```

Expected:

```text
OK full verification completed
```

## Task 7: Add Backup Script

**Files:**
- Create: `scripts/backup-release-data.ps1`

- [ ] **Step 1: Create backup script**

```powershell
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
```

- [ ] **Step 2: Run backup script**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/backup-release-data.ps1 -EnvFile deployment/env/local.env
```

Expected:

```text
OK backup created: backups/release-<timestamp>
```

## Task 8: Add Restore Script

**Files:**
- Create: `scripts/restore-release-data.ps1`

- [ ] **Step 1: Create restore script**

```powershell
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
```

- [ ] **Step 2: Do not run restore on current data unless explicitly testing rollback**

Run only on a disposable stack:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/restore-release-data.ps1 -BackupDir backups/release-<timestamp> -EnvFile deployment/env/local.env
```

Expected:

```text
OK full verification completed
OK backup restored: backups/release-<timestamp>
```

## Task 9: Add Operations Runbook

**Files:**
- Modify: `docs/OPERATIONS.md`

- [ ] **Step 1: Add release packaging runbook**

Append:

```markdown
## Cross-Machine Docker Release

### Source Machine

1. Verify current stack:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

2. Create release package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-release.ps1 -Version 20260703-local -EnvFile deployment/env/local.env
```

3. Copy `releases/20260703-local` to the target machine.

### Target Machine

1. Install Docker Desktop.
2. Open PowerShell in the release directory.
3. Run install once to create env template:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-release.ps1 -ReleaseDir .
```

4. Edit `deployment/env/release.env`.
5. Run install again:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-release.ps1 -ReleaseDir .
```

### Rollback

1. Stop the current stack:

```powershell
docker compose --env-file deployment/env/release.env -f deployment/docker-compose.yml -f deployment/docker-compose.release.yml down
```

2. Install the previous release package.
3. Restore database backup only if the failed release changed database data or schema.
4. Run `scripts/verify.ps1`.
```

- [ ] **Step 2: Verify docs render as plain Markdown**

Run:

```powershell
Get-Content -Raw docs/OPERATIONS.md | Select-String "Cross-Machine Docker Release"
```

Expected:

```text
The section title is found.
```

## Task 10: End-to-End Release Smoke Test

**Files:**
- No new files.

- [ ] **Step 1: Build release**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-release.ps1 -Version 20260703-smoke -EnvFile deployment/env/local.env
```

Expected:

```text
OK release package created: releases/20260703-smoke
```

- [ ] **Step 2: Verify release package statically**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/deployment/verify_release_package.ps1 -ReleaseDir releases/20260703-smoke
```

Expected:

```text
OK release package verified: releases/20260703-smoke
```

- [ ] **Step 3: Install release locally using copied env**

Run:

```powershell
Copy-Item -Force deployment/env/local.env releases/20260703-smoke/deployment/env/release.env
powershell -ExecutionPolicy Bypass -File releases/20260703-smoke/scripts/install-release.ps1 -ReleaseDir releases/20260703-smoke -SkipVerify
```

Expected:

```text
OK release installed from releases/20260703-smoke
```

- [ ] **Step 4: Run full verification against release stack**

Run:

```powershell
Push-Location releases/20260703-smoke
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/release.env -ComposeFile deployment/docker-compose.yml -ComposeOverlayFile deployment/docker-compose.release.yml
Pop-Location
```

Expected:

```text
OK full verification completed
```

## Rollback Strategy

- If package creation fails, delete only the new `releases/<version>` directory.
- If image load fails on target machine, remove loaded images by exact tag from `manifest.json`.
- If installation fails before migrations, run:

```powershell
docker compose --env-file deployment/env/release.env -f deployment/docker-compose.yml -f deployment/docker-compose.release.yml down
```

- If installation fails after migrations or data writes, restore from `scripts/restore-release-data.ps1` using a backup created by `scripts/backup-release-data.ps1`.
- Because the current project is not a Git repository, file rollback should use release package backups or initialize Git before implementation.

## Design Notes

- Release packaging must be image-based, not source-build based, so the target machine does not need Python base image pulls or pip downloads.
- Secrets are target-machine responsibilities. The package ships examples, not secret-bearing env files.
- `n8nio/n8n:latest` should be pinned before a formal release. The first implementation keeps the current project behavior, then a small follow-up should replace it with a fixed version.
- Dify storage under `dify/storage` may contain runtime user files. It is not part of the default package and should be handled by explicit backup/restore.
- Full offline deployment means all images already exist in tar archives. It does not mean real external API calls will work without network access.

## Self-Review

- Spec coverage: The plan respects existing boundaries: business code remains in `services/`, deployment files remain in `deployment/`, workflow files remain orchestration-only, and `platform/` is untouched.
- Verification coverage: Static package verification, Compose config validation, install smoke test, existing full verification, backup, and restore are included.
- Rollback coverage: File-level package rollback, Compose rollback, image rollback, and database restore are explicitly separated.
- Known gap: n8n uses `latest` in the current Compose file. This plan preserves compatibility first, then calls out pinning as a follow-up hardening task.
