param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $EnvFile
powershell -ExecutionPolicy Bypass -File scripts/check-secrets.ps1

docker compose --env-file $EnvFile -f $ComposeFile config | Out-Null

docker compose --env-file $EnvFile -f $ComposeFile up -d | Out-Null

powershell -ExecutionPolicy Bypass -File scripts/apply-business-migrations.ps1 -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/database/verify_business_schema.ps1 -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/database/verify_ai_customer_service_schema.ps1 -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/database/verify_data_governance_rules.ps1 -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/database/verify_production_readiness_schema.ps1 -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/assets/verify_assets.ps1
powershell -ExecutionPolicy Bypass -File scripts/verify-n8n-workflow.ps1
powershell -ExecutionPolicy Bypass -File tests/services/verify_db_simulator_business_db.ps1 -EnvFile $EnvFile -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/services/verify_agent_service.ps1 -EnvFile $EnvFile -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File scripts/verify-rag.ps1 -EnvFile $EnvFile -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File scripts/verify-observability.ps1 -EnvFile $EnvFile -ComposeFile $ComposeFile
powershell -ExecutionPolicy Bypass -File tests/evaluation/verify_evaluation_runner.ps1 -ComposeFile $ComposeFile

$checks = @(
    @{Name = "dify web"; Url = "http://localhost:8080"},
    @{Name = "dify api setup"; Url = "http://localhost:5001/console/api/setup"},
    @{Name = "db-simulator health"; Url = "http://localhost:8001/health"},
    @{Name = "agent-service health"; Url = "http://localhost:8010/health"},
    @{Name = "n8n"; Url = "http://localhost:5678"}
)

foreach ($check in $checks) {
    $response = Invoke-WebRequest -Uri $check.Url -UseBasicParsing -TimeoutSec 20
    if ($response.StatusCode -ne 200) {
        throw "$($check.Name) returned $($response.StatusCode)"
    }
    "OK $($check.Name) $($response.StatusCode)"
}

$workerEnv = docker exec ai20-dify-worker-1 /bin/sh -lc "env | grep '^CELERY_BROKER_URL='"
if ($workerEnv -notmatch "redis://redis:6379/1") {
    throw "Dify worker is not using Redis broker"
}

"OK full verification completed"
