$ErrorActionPreference = "Stop"

$workflowPath = "workflows/n8n-customer-support-local.json"
if (!(Test-Path -LiteralPath $workflowPath)) {
    throw "n8n workflow json not found: $workflowPath"
}

$workflow = Get-Content -Raw -LiteralPath $workflowPath | ConvertFrom-Json
$requiredProperties = @("id", "name", "active", "versionId")
foreach ($property in $requiredProperties) {
    if (!$workflow.PSObject.Properties.Name.Contains($property)) {
        throw "n8n workflow missing required property: $property"
    }
}
if ($workflow.active -ne $true) {
    throw "n8n workflow must be active for the production closure"
}
$webhookNodes = @($workflow.nodes | Where-Object { $_.type -eq "n8n-nodes-base.webhook" })
if ($webhookNodes.Count -ne 1 -or [string]::IsNullOrWhiteSpace($webhookNodes[0].webhookId)) {
    throw "n8n webhook node must have one stable webhookId"
}
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
if ($raw -notmatch "http://agent-service:8010/api/agent/reply") {
    throw "n8n workflow must call the in-network agent-service endpoint"
}
if ($raw -notmatch 'jsonBody": "=\{\{ \{ conversation_id:') {
    throw "n8n workflow must use an object expression for the agent-service request body"
}
if ($raw -notmatch "\$json.body.trace_id" -or $raw -notmatch "\$json.body.conversation_id") {
    throw 'n8n workflow must map Webhook request fields from $json.body'
}

"OK n8n workflow verified"
