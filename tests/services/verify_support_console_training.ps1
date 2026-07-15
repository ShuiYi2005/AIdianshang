param(
    [ValidateSet("Console", "Training", "All")]
    [string]$Phase = "All",
    [string]$AgentBaseUrl = "http://localhost:8010"
)

$ErrorActionPreference = "Stop"

function Invoke-JsonApi {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body = $null,
        [hashtable]$Headers = @{}
    )

    $parameters = @{ Method = $Method; Uri = $Uri; Headers = $Headers }
    if ($null -ne $Body) {
        $parameters.ContentType = "application/json"
        $parameters.Body = $Body | ConvertTo-Json -Depth 8 -Compress
    }
    Invoke-RestMethod @parameters
}

if ($Phase -in @("Console", "All")) {
    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
    $traceId = "console-test-$suffix"
    $agentReply = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/agent/reply" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        conversation_id = "console-$suffix"
        customer_id = "customer-$suffix"
        platform = "simulated-ecommerce"
        user_message = "I need a refund and human support"
    }
    if (-not $agentReply.handoff_id) {
        throw "agent reply did not create a handoff"
    }
    $handoffId = [string]$agentReply.handoff_id

    $queue = Invoke-JsonApi -Method "GET" -Uri "$AgentBaseUrl/api/console/queue?status=pending"
    if ($null -eq $queue.items) {
        throw "console queue response is missing items"
    }
    if (-not (@($queue.items | Where-Object { $_.id -eq $handoffId }))) {
        throw "created handoff is absent from the pending console queue"
    }

    $detail = Invoke-JsonApi -Method "GET" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId"
    if ($detail.handoff.id -ne $handoffId) {
        throw "console detail does not identify the requested handoff"
    }

    $claimed = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId/claim" -Headers @{ "X-Trace-Id" = $traceId }
    if ($claimed.handoff.status -ne "assigned") {
        throw "console claim did not assign the handoff"
    }

    $replyText = "This reply was sent through the local simulated channel."
    $reply = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId/reply" -Headers @{ "X-Trace-Id" = $traceId } -Body @{ content = $replyText; role = "support_agent" }
    if ($reply.delivery_status -ne "simulated_sent") {
        throw "console reply did not enter the simulated channel"
    }

    $ticket = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId/ticket" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        subject = "Refund human review"
        description = "Simulated ticket created by the end-to-end verification."
    }
    if (-not $ticket.ticket.id) {
        throw "console ticket was not persisted"
    }

    $resolved = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId/resolve" -Headers @{ "X-Trace-Id" = $traceId }
    if ($resolved.resolved -ne $true) {
        throw "console handoff was not resolved"
    }

    $finalDetail = Invoke-JsonApi -Method "GET" -Uri "$AgentBaseUrl/api/console/handoffs/$handoffId"
    if ($finalDetail.handoff.status -ne "resolved") {
        throw "resolved handoff state was not persisted"
    }
    if (-not (@($finalDetail.messages | Where-Object { $_.content -eq $replyText }))) {
        throw "simulated reply is absent from the conversation history"
    }
    if (-not (@($finalDetail.tickets | Where-Object { $_.id -eq $ticket.ticket.id }))) {
        throw "created ticket is absent from console detail"
    }
    if (-not (@($finalDetail.audit_actions | Where-Object { $_.trace_id -eq $traceId }))) {
        throw "console actions are absent from audit history"
    }

    "OK support console API flow verified"
}

if ($Phase -in @("Training", "All")) {
    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
    $traceId = "training-test-$suffix"
    $topic = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        name = "After-sales guide $suffix"
        trigger_phrases = @("how do I return an item")
        reply_text = "Please submit an after-sales request first."
        store_scope = "simulated-store"
        product_scope = "all-products"
        channel = "simulated-ecommerce"
    }
    if (-not $topic.id) {
        throw "training topic was not created"
    }

    $topicId = [string]$topic.id
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "support-console-training-$suffix"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $unsupported = Join-Path $tempRoot "invoice.exe"
        $supported = Join-Path $tempRoot "guide.txt"
        [IO.File]::WriteAllBytes($unsupported, [byte[]](1, 2, 3))
        [IO.File]::WriteAllBytes($supported, [Text.Encoding]::UTF8.GetBytes("after-sales material"))

        $rejectedStatus = & curl.exe -s -o NUL -w "%{http_code}" -X POST "$AgentBaseUrl/api/training/topics/$topicId/assets" -F "file=@$unsupported;type=application/octet-stream"
        if ($rejectedStatus.Trim() -ne "400") {
            throw "unsupported training asset was not rejected"
        }

        $assetJson = & curl.exe -s -X POST "$AgentBaseUrl/api/training/topics/$topicId/assets" -F "file=@$supported;type=text/plain" -F "description=after-sales material"
        $asset = $assetJson | ConvertFrom-Json
        if ($asset.asset_type -ne "text") {
            throw "supported training asset was not stored"
        }
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $preview = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics/$topicId/preview" -Body @{ query = "How do I return an item?" }
    if ($preview.matched -ne $true -or $preview.handoff_required -ne $false) {
        throw "training preview did not match a normal trigger phrase"
    }
    $sensitivePreview = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics/$topicId/preview" -Body @{ query = "I need a refund" }
    if ($sensitivePreview.handoff_required -ne $true -or $sensitivePreview.matched -ne $false) {
        throw "training preview did not protect a refund request"
    }

    $firstPublish = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics/$topicId/publish" -Headers @{ "X-Trace-Id" = $traceId }
    if ($firstPublish.topic.current_version -ne 1) {
        throw "first topic publish did not create version 1"
    }
    $trainedReply = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/agent/reply" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        conversation_id = "trained-$suffix"
        customer_id = "trained-customer-$suffix"
        platform = "simulated-ecommerce"
        user_message = "How do I return an item?"
    }
    if ($trainedReply.content -ne "Please submit an after-sales request first." -or $trainedReply.model_provider -ne "local-training") {
        throw "published training topic was not used by the local agent reply"
    }

    $updatedTopic = Invoke-JsonApi -Method "PUT" -Uri "$AgentBaseUrl/api/training/topics/$topicId" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        reply_text = "The updated after-sales response."
    }
    if ($updatedTopic.reply_text -ne "The updated after-sales response.") {
        throw "training topic update was not persisted"
    }
    $secondPublish = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics/$topicId/publish" -Headers @{ "X-Trace-Id" = $traceId }
    if ($secondPublish.topic.current_version -ne 2) {
        throw "second topic publish did not create version 2"
    }

    $rollback = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/training/topics/$topicId/rollback" -Headers @{ "X-Trace-Id" = $traceId } -Body @{ version = 1 }
    if ($rollback.topic.current_version -ne 3 -or $rollback.topic.reply_text -ne "Please submit an after-sales request first.") {
        throw "training rollback did not restore the immutable version 1 snapshot"
    }
    $restoredReply = Invoke-JsonApi -Method "POST" -Uri "$AgentBaseUrl/api/agent/reply" -Headers @{ "X-Trace-Id" = $traceId } -Body @{
        conversation_id = "restored-$suffix"
        customer_id = "restored-customer-$suffix"
        platform = "simulated-ecommerce"
        user_message = "How do I return an item?"
    }
    if ($restoredReply.content -ne "Please submit an after-sales request first." -or $restoredReply.model_provider -ne "local-training") {
        throw "rolled back topic version was not used by the local agent reply"
    }

    $detail = Invoke-JsonApi -Method "GET" -Uri "$AgentBaseUrl/api/training/topics/$topicId"
    if (@($detail.assets).Count -ne 1 -or @($detail.versions).Count -ne 3) {
        throw "training topic detail does not expose stored assets and versions"
    }
    if (-not (@($detail.audit_actions | Where-Object { $_.trace_id -eq $traceId }))) {
        throw "training lifecycle audit actions are missing"
    }

    "OK training center API flow verified"
}
