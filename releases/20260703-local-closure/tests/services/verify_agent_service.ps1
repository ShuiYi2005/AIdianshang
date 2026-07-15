param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

docker compose --env-file $EnvFile -f $ComposeFile up -d business-db db-simulator agent-service | Out-Null

$deadline = (Get-Date).AddSeconds(90)
do {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:8010/health" -TimeoutSec 5
        if ($health.status -eq "ok") {
            break
        }
    } catch {
        Start-Sleep -Seconds 2
    }
} while ((Get-Date) -lt $deadline)

if (!$health -or $health.status -ne "ok") {
    throw "agent-service did not become healthy"
}

$traceId = "trace-agent-service-test"
$maskingBody = @{
    phone = "18812340000"
    address = "Test Province Test City Test Street 123"
    role = "support_agent"
} | ConvertTo-Json

$masking = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/masking/preview" `
    -Method Post `
    -Body $maskingBody `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = $traceId; "X-Api-Version" = "v1"} `
    -TimeoutSec 20

if ($masking.data.phone -eq "18812340000") {
    throw "phone was not masked"
}
if ($masking.data.address -eq "Test Province Test City Test Street 123") {
    throw "address was not masked"
}

$replyBody = @{
    conversation_id = "agent-service-test-conversation"
    platform = "test"
    customer_id = "agent-service-test-customer"
    user_message = "请帮我查询订单 ORD-DBTEST"
} | ConvertTo-Json

$reply = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/agent/reply" `
    -Method Post `
    -Body $replyBody `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = $traceId; "X-Idempotency-Key" = "agent-service-test-001"; "X-Api-Version" = "v1"} `
    -TimeoutSec 30

if ($reply.trace_id -ne $traceId) {
    throw "trace id was not propagated"
}
if (!$reply.context_snapshot_id) {
    throw "context snapshot id was not returned"
}
if ($reply.content -notmatch "ORD-DBTEST") {
    throw "reply does not reference queried order"
}
if ($reply.data_masked -ne $true) {
    throw "reply did not report masked data"
}

$contextCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from memory.context_snapshots where trace_id = '$traceId';"
if ([int]$contextCount.Trim() -lt 1) {
    throw "context snapshot was not persisted"
}

$toolLogCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from audit.tool_call_logs where trace_id = '$traceId';"
if ([int]$toolLogCount.Trim() -lt 1) {
    throw "tool call audit log was not persisted"
}

$metrics = Invoke-RestMethod -Uri "http://localhost:8010/metrics" -TimeoutSec 20
if ($metrics.service -ne "agent-service") {
    throw "metrics endpoint did not return service name"
}
if ($metrics.metrics -notcontains "cost.usage.events") {
    throw "metrics endpoint missing cost usage metric"
}

$accessBody = @{
    role = "support_agent"
    resource = "order"
} | ConvertTo-Json

$access = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/security/access-preview" `
    -Method Post `
    -Body $accessBody `
    -ContentType "application/json" `
    -TimeoutSec 20

if ($access.data.can_read -ne $true) {
    throw "support_agent should be able to read order resource"
}
if ($access.data.masked_fields -notcontains "phone") {
    throw "support_agent should see masked phone field"
}

$stateBody = @{
    entity_type = "handoff"
    from_status = "pending"
    to_status = "assigned"
} | ConvertTo-Json

$state = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/state/transition-preview" `
    -Method Post `
    -Body $stateBody `
    -ContentType "application/json" `
    -TimeoutSec 20

if ($state.data.allowed -ne $true) {
    throw "handoff pending -> assigned should be allowed"
}

$ragBody = @{
    query = "FAQ policy"
    limit = 3
} | ConvertTo-Json

$rag = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/rag/search" `
    -Method Post `
    -Body $ragBody `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = "trace-agent-rag-test"} `
    -TimeoutSec 20

if (!$rag.results -or $rag.results.Count -lt 1) {
    throw "rag search should return at least one local knowledge result"
}

$handoffTraceId = "trace-agent-handoff-test"
$handoffBody = @{
    conversation_id = "agent-service-handoff-conversation"
    platform = "test"
    customer_id = "agent-service-handoff-customer"
    user_message = "I want to complain and request compensation"
} | ConvertTo-Json

$handoffReply = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/agent/reply" `
    -Method Post `
    -Body $handoffBody `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = $handoffTraceId; "X-Idempotency-Key" = "agent-service-handoff-001"} `
    -TimeoutSec 30

if ($handoffReply.handoff_required -ne $true) {
    throw "sensitive case should require handoff"
}
if (!$handoffReply.handoff_id) {
    throw "handoff id was not returned"
}

$handoffs = Invoke-RestMethod -Uri "http://localhost:8010/api/workbench/handoffs?status=pending&limit=10" -TimeoutSec 20
$matchingHandoffs = @($handoffs.items | Where-Object { $_.id -eq $handoffReply.handoff_id })
if (!$handoffs.items -or $matchingHandoffs.Count -lt 1) {
    throw "handoff queue did not return created handoff"
}

$resolved = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/workbench/handoffs/$($handoffReply.handoff_id)/resolve" `
    -Method Post `
    -TimeoutSec 20
if ($resolved.resolved -ne $true) {
    throw "handoff was not resolved"
}

$costCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from audit.cost_usage_events where trace_id in ('$traceId', '$handoffTraceId', 'trace-agent-rag-test');"
if ([int]$costCount.Trim() -lt 2) {
    throw "cost usage events were not persisted"
}

"OK agent-service verified"
