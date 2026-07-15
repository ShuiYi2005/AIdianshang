param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

docker compose --env-file $EnvFile -f $ComposeFile up -d business-db db-simulator agent-service | Out-Null

$metrics = Invoke-RestMethod -Uri "http://localhost:8010/metrics" -TimeoutSec 20
foreach ($metricName in @("agent.reply.count", "tool.latency_ms", "cost.usage.events")) {
    if ($metrics.metrics -notcontains $metricName) {
        throw "metrics endpoint missing $metricName"
    }
}

$traceId = "trace-observability-verify"
$body = @{
    conversation_id = "observability-test-conversation"
    platform = "test"
    customer_id = "observability-test-customer"
    user_message = "please check order ORD-DBTEST"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "http://localhost:8010/api/agent/reply" `
    -Method Post `
    -Body $body `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = $traceId; "X-Idempotency-Key" = "observability-test-001"} `
    -TimeoutSec 30 | Out-Null

$metricCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from audit.metrics_events where trace_id = '$traceId';"
if ([int]$metricCount.Trim() -lt 1) {
    throw "metrics events were not persisted"
}

$costCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from audit.cost_usage_events where trace_id = '$traceId';"
if ([int]$costCount.Trim() -lt 1) {
    throw "cost usage events were not persisted"
}

"OK observability verified"
