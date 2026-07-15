$ErrorActionPreference = "Stop"

$workflowPath = "workflows/n8n-customer-support-local.json"
if (!(Test-Path -LiteralPath $workflowPath)) {
    throw "n8n workflow json not found: $workflowPath"
}

$workflow = Get-Content -Raw -LiteralPath $workflowPath | ConvertFrom-Json
$nodeTypes = @($workflow.nodes | ForEach-Object { $_.type })

foreach ($requiredType in @("n8n-nodes-base.webhook", "n8n-nodes-base.httpRequest", "n8n-nodes-base.respondToWebhook")) {
    if ($nodeTypes -notcontains $requiredType) {
        throw "n8n workflow missing node type: $requiredType"
    }
}

$raw = Get-Content -Raw -LiteralPath $workflowPath
if ($raw -match "SECRET|PASSWORD|API_KEY|TOKEN") {
    throw "n8n workflow appears to contain secret-like text"
}

"OK n8n workflow verified"
