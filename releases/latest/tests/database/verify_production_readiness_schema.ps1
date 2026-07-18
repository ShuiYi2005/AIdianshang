param(
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$EnvFile = ""
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

$composeArgs = if ($EnvFile) { @("--env-file", $EnvFile) } else { @() }
docker compose @composeArgs -f $ComposeFile up -d business-db | Out-Null

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

$tableOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name from information_schema.tables where table_schema in ('core','support','ops','audit','knowledge','memory','recruitment','commerce') and table_type='BASE TABLE' order by 1;"
$tables = $tableOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredTables = @(
    "core.tenants",
    "core.roles",
    "core.permissions",
    "core.role_permissions",
    "core.user_roles",
    "core.data_access_policies",
    "core.data_masking_policies",
    "ops.data_retention_policies",
    "ops.retention_jobs",
    "ops.external_sync_jobs",
    "ops.external_sync_cursors",
    "ops.feature_flags",
    "ops.release_rollouts",
    "ops.tool_fallback_policies",
    "ops.tool_invocation_policies",
    "audit.metrics_events",
    "audit.cost_usage_events",
    "audit.alert_events",
    "knowledge.evaluation_sets",
    "knowledge.evaluation_cases",
    "knowledge.evaluation_runs",
    "knowledge.evaluation_results",
    "support.agent_workbench_sessions"
)

foreach ($table in $requiredTables) {
    Assert-Contains -Items $tables -Expected $table -Kind "table"
}

$columnOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name || '.' || column_name from information_schema.columns where table_schema in ('core','commerce','recruitment','support','ops','audit','knowledge','memory') order by 1;"
$columns = $columnOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredTenantColumns = @(
    "core.customers.tenant_id",
    "commerce.orders.tenant_id",
    "commerce.products.tenant_id",
    "commerce.logistics.tenant_id",
    "recruitment.resumes.tenant_id",
    "recruitment.jobs.tenant_id",
    "support.conversations.tenant_id",
    "support.messages.tenant_id",
    "support.tickets.tenant_id",
    "audit.audit_logs.tenant_id",
    "audit.tool_call_logs.trace_id",
    "audit.ai_response_logs.trace_id",
    "memory.context_snapshots.tenant_id",
    "knowledge.documents.tenant_id"
)

foreach ($column in $requiredTenantColumns) {
    Assert-Contains -Items $columns -Expected $column -Kind "column"
}

$indexOutput = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select schemaname || '.' || indexname from pg_indexes where schemaname in ('core','commerce','recruitment','support','ops','audit','knowledge','memory') order by 1;"
$indexes = $indexOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$requiredIndexes = @(
    "core.uq_tenants_slug",
    "core.uq_roles_tenant_name",
    "core.uq_permissions_code",
    "core.uq_user_roles_user_role_tenant",
    "ops.uq_feature_flags_key",
    "ops.uq_release_rollouts_target",
    "ops.uq_sync_cursors_provider_resource",
    "knowledge.idx_evaluation_cases_category",
    "audit.idx_metrics_events_name_created_at",
    "audit.idx_cost_usage_events_scope_created_at"
)

foreach ($index in $requiredIndexes) {
    Assert-Contains -Items $indexes -Expected $index -Kind "index"
}

"OK production readiness schema verified"
