param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

function Invoke-CheckedScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    & powershell -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Verification script failed: $ScriptPath"
    }
}

Invoke-CheckedScript "scripts/check-env.ps1" @("-EnvFile", $EnvFile)
Invoke-CheckedScript "scripts/check-secrets.ps1"

docker compose --env-file $EnvFile -f $ComposeFile config | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker Compose configuration is invalid" }

docker compose --env-file $EnvFile -f $ComposeFile up -d | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker Compose startup failed" }

Invoke-CheckedScript "scripts/apply-business-migrations.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/database/verify_business_schema.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/database/verify_ai_customer_service_schema.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/database/verify_data_governance_rules.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/database/verify_production_readiness_schema.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/database/verify_support_console_training_schema.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)
Invoke-CheckedScript "tests/assets/verify_assets.ps1"
Invoke-CheckedScript "scripts/verify-n8n-workflow.ps1"
Invoke-CheckedScript "tests/services/verify_dify_integration.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "scripts/import-n8n-customer-support-workflow.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "tests/services/verify_db_simulator_business_db.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "tests/services/verify_agent_service.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "tests/services/verify_support_console_training.ps1" @("-Phase", "All")
& node tests/ui/verify_support_console_ui.mjs
if ($LASTEXITCODE -ne 0) { throw "Verification script failed: tests/ui/verify_support_console_ui.mjs" }
& node tests/ui/verify_fixed_shell_layout.mjs
if ($LASTEXITCODE -ne 0) { throw "Verification script failed: tests/ui/verify_fixed_shell_layout.mjs" }
Invoke-CheckedScript "tests/services/verify_n8n_webhook.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "scripts/verify-rag.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "scripts/verify-observability.ps1" @("-EnvFile", $EnvFile, "-ComposeFile", $ComposeFile)
Invoke-CheckedScript "tests/evaluation/verify_evaluation_runner.ps1" @("-ComposeFile", $ComposeFile, "-EnvFile", $EnvFile)

$checks = @(
    @{Name = "dify web"; Url = "http://localhost:8080"},
    @{Name = "dify api setup"; Url = "http://localhost:5001/console/api/setup"},
    @{Name = "db-simulator health"; Url = "http://localhost:8001/health"},
    @{Name = "agent-service health"; Url = "http://localhost:8010/health"},
    @{Name = "support console"; Url = "http://localhost:4173"},
    @{Name = "n8n"; Url = "http://localhost:5678"}
)

foreach ($check in $checks) {
    $response = $null
    $lastError = $null
    $deadline = (Get-Date).AddSeconds(45)
    do {
        try {
            $response = Invoke-WebRequest -Uri $check.Url -UseBasicParsing -TimeoutSec 10
            break
        } catch {
            $lastError = $_
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)
    if (!$response) {
        throw "$($check.Name) did not respond: $($lastError.Exception.Message)"
    }
    if ($response.StatusCode -ne 200) {
        throw "$($check.Name) returned $($response.StatusCode)"
    }
    "OK $($check.Name) $($response.StatusCode)"
}

$workerEnv = docker exec ai20-dify-worker-1 /bin/sh -lc "env | grep '^CELERY_BROKER_URL='"
if ($workerEnv -notmatch "redis://redis:6379/1") {
    throw "Dify worker is not using Redis broker"
}

$pluginUrl = docker exec ai20-dify-api-1 /bin/sh -lc "printf '%s' `"`$PLUGIN_DAEMON_URL`""
if ($pluginUrl -ne "http://plugin-daemon:5002") {
    throw "Dify API is not configured to use plugin daemon service URL"
}

$pluginConnectivity = ""
$pluginConnected = $false
$pluginDeadline = (Get-Date).AddSeconds(30)
do {
    $pluginConnectivity = docker exec ai20-dify-api-1 /app/api/.venv/bin/python -c "import os, httpx; url = os.environ['PLUGIN_DAEMON_URL'] + '/plugin/healthcheck/management/models'; key = os.environ['PLUGIN_DAEMON_KEY']; print(httpx.get(url, headers={'X-Api-Key': key}, timeout=5).status_code)"
    $pluginConnected = $LASTEXITCODE -eq 0 -and $pluginConnectivity.Trim() -match "^\d{3}$"
    if (-not $pluginConnected) { Start-Sleep -Seconds 2 }
} while (-not $pluginConnected -and (Get-Date) -lt $pluginDeadline)
if (-not $pluginConnected) {
    throw "Dify API could not request plugin daemon"
}

"OK full verification completed"
