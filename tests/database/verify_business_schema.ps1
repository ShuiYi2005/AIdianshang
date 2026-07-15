param(
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

function Assert-Contains {
    param(
        [string[]]$Items,
        [string]$Expected
    )

    if ($Items -notcontains $Expected) {
        throw "Missing required table: $Expected"
    }
}

docker compose -f $ComposeFile config --services | Select-String -SimpleMatch "business-db" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "business-db service is not defined in $ComposeFile"
}

docker compose -f $ComposeFile up -d business-db | Out-Null

$deadline = (Get-Date).AddSeconds(60)
do {
    $status = docker inspect -f "{{.State.Health.Status}}" ai20-business-db-1 2>$null
    if ($status -eq "healthy") {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($status -ne "healthy") {
    throw "business-db did not become healthy; status=$status"
}

$tableOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name from information_schema.tables where table_schema in ('core','commerce','recruitment','support','ops','audit') and table_type='BASE TABLE' order by 1;"
$tables = $tableOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredTables = @(
    "core.users",
    "core.customers",
    "commerce.products",
    "commerce.orders",
    "commerce.order_items",
    "commerce.logistics",
    "commerce.logistics_traces",
    "recruitment.resumes",
    "recruitment.jobs",
    "recruitment.applications",
    "support.conversations",
    "support.messages",
    "support.tickets",
    "ops.upload_tasks",
    "ops.async_tasks",
    "ops.drafts",
    "audit.audit_logs",
    "audit.approval_records",
    "audit.status_change_logs",
    "audit.tool_call_logs",
    "audit.ai_response_logs",
    "audit.handoff_records",
    "audit.login_logs"
)

foreach ($table in $requiredTables) {
    Assert-Contains -Items $tables -Expected $table
}

$indexOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select schemaname || '.' || indexname from pg_indexes where schemaname in ('core','commerce','recruitment','support','ops','audit') order by 1;"
$indexes = $indexOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

Assert-Contains -Items $indexes -Expected "commerce.idx_orders_customer_id"
Assert-Contains -Items $indexes -Expected "support.idx_messages_conversation_id_created_at"
Assert-Contains -Items $indexes -Expected "audit.idx_audit_logs_actor_created_at"

"OK business schema verified"
