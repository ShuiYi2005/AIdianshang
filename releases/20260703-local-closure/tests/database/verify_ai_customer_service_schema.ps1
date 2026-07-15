param(
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

function Assert-Contains {
    param(
        [string[]]$Items,
        [string]$Expected,
        [string]$Kind = "item"
    )

    if ($Items -notcontains $Expected) {
        throw "Missing required ${Kind}: $Expected"
    }
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

$tableOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name from information_schema.tables where table_schema in ('support','ops','audit','knowledge','memory') and table_type='BASE TABLE' order by 1;"
$tables = $tableOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredTables = @(
    "support.customer_profiles",
    "support.conversation_summaries",
    "support.message_feedback",
    "support.handoff_queue",
    "ops.webhook_events",
    "ops.idempotency_keys",
    "ops.cache_invalidation_jobs",
    "knowledge.documents",
    "knowledge.document_versions",
    "knowledge.document_chunks",
    "knowledge.sync_jobs",
    "memory.long_term_memories",
    "memory.context_snapshots",
    "audit.data_change_events",
    "audit.security_events"
)

foreach ($table in $requiredTables) {
    Assert-Contains -Items $tables -Expected $table -Kind "table"
}

$indexOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select schemaname || '.' || indexname from pg_indexes where schemaname in ('support','ops','audit','knowledge','memory') order by 1;"
$indexes = $indexOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredIndexes = @(
    "support.uq_customer_profiles_customer_id",
    "support.uq_conversation_summaries_conversation_id",
    "support.uq_messages_platform_message_id",
    "ops.uq_webhook_events_provider_event_id",
    "ops.uq_idempotency_keys_scope_key",
    "knowledge.uq_documents_source_uri",
    "knowledge.uq_document_versions_document_version",
    "knowledge.idx_document_chunks_embedding_ref",
    "memory.uq_long_term_memories_scope_key"
)

foreach ($index in $requiredIndexes) {
    Assert-Contains -Items $indexes -Expected $index -Kind "index"
}

$columnOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name || '.' || column_name from information_schema.columns where table_schema in ('support','ops','knowledge','memory','audit') order by 1;"
$columns = $columnOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredColumns = @(
    "support.messages.platform_message_id",
    "support.messages.context_snapshot_id",
    "support.conversations.last_context_snapshot_id",
    "memory.context_snapshots.prompt_context"
)

foreach ($column in $requiredColumns) {
    Assert-Contains -Items $columns -Expected $column -Kind "column"
}

"OK AI customer service schema verified"
