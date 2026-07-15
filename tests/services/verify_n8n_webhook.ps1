param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

docker compose --env-file $EnvFile -f $ComposeFile up -d n8n agent-service | Out-Null

$deadline = (Get-Date).AddSeconds(90)
do {
    try {
        $health = Invoke-WebRequest -Uri "http://localhost:5678/healthz" -UseBasicParsing -TimeoutSec 5
        if ($health.StatusCode -eq 200) {
            break
        }
    } catch {
        Start-Sleep -Seconds 2
    }
} while ((Get-Date) -lt $deadline)

if (!$health -or $health.StatusCode -ne 200) {
    throw "n8n did not become healthy"
}

$traceId = "trace-n8n-webhook-test"
$request = @{
    conversation_id = "n8n-webhook-test-conversation"
    platform = "simulated-ecommerce"
    customer_id = "n8n-webhook-test-customer"
    user_message = "Please check order ORD-DBTEST"
    role = "support_agent"
    trace_id = $traceId
    idempotency_key = "n8n-webhook-test-001"
} | ConvertTo-Json

$webhookDeadline = (Get-Date).AddSeconds(60)
$response = $null
$lastError = $null
do {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:5678/webhook/ai20/customer-support" -Method Post -Body $request -ContentType "application/json" -TimeoutSec 45
        break
    } catch {
        $lastError = $_
        Start-Sleep -Seconds 2
    }
} while ((Get-Date) -lt $webhookDeadline)

if (!$response) {
    throw "n8n production webhook was not ready: $($lastError.ErrorDetails.Message)"
}

if ($response.trace_id -ne $traceId) {
    throw "n8n did not return the agent-service trace id"
}
if ($response.content -notmatch "ORD-DBTEST") {
    throw "n8n webhook did not return the agent-service order response"
}
if (!$response.context_snapshot_id) {
    throw "n8n webhook did not return a context snapshot id"
}

"OK n8n webhook called agent-service and returned a customer-service reply"
