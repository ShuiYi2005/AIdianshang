param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath "knowledge/manifest.json")) {
    throw "knowledge manifest not found"
}

$manifest = Get-Content -Raw -LiteralPath "knowledge/manifest.json" | ConvertFrom-Json
foreach ($document in $manifest.documents) {
    $path = Join-Path "knowledge" $document.source_uri
    if (!(Test-Path -LiteralPath $path)) {
        throw "knowledge document not found: $($document.source_uri)"
    }
}

docker compose --env-file $EnvFile -f $ComposeFile up -d business-db weaviate agent-service | Out-Null

$status = Invoke-RestMethod -Uri "http://localhost:8010/api/rag/status" -Method Get -TimeoutSec 20
if (!$status.mode) {
    throw "rag status did not return a retrieval mode"
}

Invoke-RestMethod -Uri "http://localhost:8010/api/rag/reindex" -Method Post -TimeoutSec 20 | Out-Null
$deadline = (Get-Date).AddSeconds(180)
do {
    Start-Sleep -Seconds 2
    $status = Invoke-RestMethod -Uri "http://localhost:8010/api/rag/status" -Method Get -TimeoutSec 20
    if ($status.index_status -in @("failed", "degraded")) {
        throw "rag index did not become ready: $($status.index_status)"
    }
} while ($status.index_status -notin @("ready", "succeeded") -and (Get-Date) -lt $deadline)

if ($status.index_status -notin @("ready", "succeeded")) {
    throw "rag index timed out"
}

$body = @{ query = "FAQ policy"; limit = 3 } | ConvertTo-Json
$rag = Invoke-RestMethod `
    -Uri "http://localhost:8010/api/rag/search" `
    -Method Post `
    -Body $body `
    -ContentType "application/json" `
    -Headers @{"X-Trace-Id" = "trace-rag-verify"} `
    -TimeoutSec 20

if (!$rag.results -or $rag.results.Count -lt 1) {
    throw "rag search returned no results"
}
if ($rag.retrieval_mode -ne "vector") {
    throw "expected vector retrieval, got $($rag.retrieval_mode)"
}
if (!$rag.results[0].source_uri -or !$rag.results[0].document_version_id) {
    throw "vector result did not include its source citation"
}

$costCount = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select count(*) from audit.cost_usage_events where trace_id = 'trace-rag-verify' and cost_scope = 'rag.search';"
if ([int]$costCount.Trim() -lt 1) {
    throw "rag cost event was not persisted"
}

"OK rag verified"
