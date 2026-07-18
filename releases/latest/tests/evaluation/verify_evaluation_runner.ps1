param(
    [string]$EvalFile = "evaluations/customer-service-smoke.json",
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

$result = powershell -ExecutionPolicy Bypass -File scripts/run-evaluations.ps1 -EvalFile $EvalFile -ComposeFile $ComposeFile -EnvFile $EnvFile
if ($result -notmatch "OK evaluations completed") {
    throw "evaluation runner did not complete"
}

$runCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from knowledge.evaluation_runs where target_version = 'local-current';"
if ([int]$runCount.Trim() -lt 1) {
    throw "evaluation run was not persisted"
}

$caseCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from knowledge.evaluation_cases where category in ('order_query','handoff','pii_masking','no_fabrication');"
if ([int]$caseCount.Trim() -lt 4) {
    throw "evaluation cases were not persisted"
}

"OK evaluation runner verified"
