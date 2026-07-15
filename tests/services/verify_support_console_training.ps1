param(
    [ValidateSet("Console", "All")]
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
