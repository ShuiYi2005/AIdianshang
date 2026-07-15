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

$secretFiles = @("deployment/env/local.env", "deployment/.env")
foreach ($file in $secretFiles) {
    if (Test-Path -LiteralPath (Join-Path $ReleaseDir $file)) {
        throw "Secret-bearing file must not be included: $file"
    }
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $ReleaseDir "manifest.json") | ConvertFrom-Json
if (!$manifest.version) {
    throw "manifest.json missing version"
}

foreach ($image in $manifest.images) {
    $archivePath = Join-Path $ReleaseDir $image.archive
    if (!(Test-Path -LiteralPath $archivePath)) {
        throw "Missing image archive: $($image.archive)"
    }
}

"OK release package verified: $ReleaseDir"
