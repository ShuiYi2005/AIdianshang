param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$WorkflowPath = "workflows/n8n-customer-support-local.json"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $WorkflowPath)) {
    throw "n8n workflow json not found: $WorkflowPath"
}

$workflow = Get-Content -Raw -LiteralPath $WorkflowPath | ConvertFrom-Json
if (!$workflow.id) {
    throw "n8n workflow must declare a stable id"
}
if ($workflow.active -ne $true) {
    throw "n8n workflow must be active before import"
}

$containerId = (docker compose --env-file $EnvFile -f $ComposeFile ps -q n8n).Trim()
if (!$containerId) {
    throw "n8n container is not running"
}

$remotePath = "/tmp/ai20-customer-support-workflow.json"
docker cp $WorkflowPath "$($containerId):$remotePath"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy workflow into n8n container"
}

# n8n imports by stable workflow ID as an upsert. Publishing activates its version.
docker compose --env-file $EnvFile -f $ComposeFile exec -T n8n n8n import:workflow --input=$remotePath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to import n8n workflow"
}

docker compose --env-file $EnvFile -f $ComposeFile exec -T n8n n8n publish:workflow --id=$($workflow.id)
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish n8n workflow"
}

# The n8n CLI publishes the version in its database. Restart to load its Webhook.
docker compose --env-file $EnvFile -f $ComposeFile restart n8n | Out-Null
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
    throw "n8n did not become healthy after publishing the workflow"
}

$published = docker compose --env-file $EnvFile -f $ComposeFile exec -T n8n sh -lc "rm -f /tmp/ai20-published-workflow.json; n8n export:workflow --id=$($workflow.id) --published --output=/tmp/ai20-published-workflow.json >/dev/null 2>&1; cat /tmp/ai20-published-workflow.json"
$publishedText = @($published) -join [Environment]::NewLine
if ($publishedText -notmatch [regex]::Escape($workflow.id)) {
    throw "n8n workflow was not published"
}

"OK n8n workflow imported and published: $($workflow.id)"
