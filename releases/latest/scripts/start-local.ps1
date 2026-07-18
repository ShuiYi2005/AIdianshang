param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$TemplateFile = "deployment/env/local.env.example",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed"
    }
}

if (!(Test-Path -LiteralPath $EnvFile)) {
    Invoke-Checked "Local environment bootstrap" {
        powershell -ExecutionPolicy Bypass -File scripts/bootstrap-local.ps1 -EnvFile $EnvFile -TemplateFile $TemplateFile
    }
}

Invoke-Checked "Environment validation" {
    powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile
}

Invoke-Checked "Business database startup" {
    docker compose --env-file $EnvFile -f $ComposeFile up -d business-db
}

Invoke-Checked "Business database migrations" {
    powershell -ExecutionPolicy Bypass -File scripts/apply-business-migrations.ps1 -ComposeFile $ComposeFile -EnvFile $EnvFile
}

Invoke-Checked "Application stack startup" {
    docker compose --env-file $EnvFile -f $ComposeFile up -d --build
}

"OK local stack started. Run scripts/verify.ps1 for the full acceptance suite."
