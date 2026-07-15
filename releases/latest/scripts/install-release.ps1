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
