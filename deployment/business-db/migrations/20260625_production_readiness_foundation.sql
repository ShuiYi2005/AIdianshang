CREATE TABLE IF NOT EXISTS core.tenants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug varchar(128) NOT NULL,
    name varchar(255) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'active',
    plan_code varchar(64),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tenants_status_check CHECK (status IN ('active', 'suspended', 'disabled', 'deleted'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tenants_slug ON core.tenants(slug);

CREATE TABLE IF NOT EXISTS core.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    name varchar(128) NOT NULL,
    description text,
    is_system boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_roles_tenant_name ON core.roles(coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), name);

CREATE TABLE IF NOT EXISTS core.permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(128) NOT NULL,
    resource varchar(128) NOT NULL,
    action varchar(64) NOT NULL,
    description text,
    risk_level varchar(32) NOT NULL DEFAULT 'normal',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_risk_level_check CHECK (risk_level IN ('low', 'normal', 'high', 'critical'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_permissions_code ON core.permissions(code);

CREATE TABLE IF NOT EXISTS core.role_permissions (
    role_id uuid NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES core.permissions(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS core.user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_roles_user_role_tenant ON core.user_roles(user_id, role_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE TABLE IF NOT EXISTS core.data_access_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_name varchar(128) NOT NULL,
    resource varchar(128) NOT NULL,
    permission_code varchar(128) NOT NULL,
    tenant_scope varchar(32) NOT NULL DEFAULT 'tenant',
    row_filter jsonb NOT NULL DEFAULT '{}'::jsonb,
    field_allowlist text[] NOT NULL DEFAULT ARRAY[]::text[],
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT data_access_policies_scope_check CHECK (tenant_scope IN ('global', 'tenant', 'own'))
);

CREATE INDEX IF NOT EXISTS idx_data_access_policies_resource ON core.data_access_policies(resource, permission_code);

CREATE TABLE IF NOT EXISTS core.data_masking_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_name varchar(128) NOT NULL,
    resource varchar(128) NOT NULL,
    field_name varchar(128) NOT NULL,
    masking_strategy varchar(64) NOT NULL,
    allowed_permission_code varchar(128),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT data_masking_strategy_check CHECK (masking_strategy IN ('none', 'partial', 'hash', 'redact', 'tokenize'))
);

CREATE INDEX IF NOT EXISTS idx_data_masking_policies_resource_field ON core.data_masking_policies(resource, field_name);

ALTER TABLE core.users ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE core.customers ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE commerce.products ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE commerce.orders ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE commerce.logistics ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE recruitment.resumes ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE recruitment.jobs ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE support.conversations ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE support.messages ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE support.tickets ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE support.customer_profiles ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE support.handoff_queue ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE ops.webhook_events ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE ops.idempotency_keys ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE audit.audit_logs ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE audit.tool_call_logs ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE audit.ai_response_logs ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE memory.context_snapshots ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE memory.long_term_memories ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);
ALTER TABLE knowledge.documents ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES core.tenants(id);

CREATE INDEX IF NOT EXISTS idx_customers_tenant ON core.customers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_tenant_status ON commerce.orders(tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_tenant_status ON support.conversations(tenant_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_tenant_created_at ON support.messages(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_created_at ON audit.audit_logs(tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ops.data_retention_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    data_domain varchar(128) NOT NULL,
    retention_days integer NOT NULL CHECK (retention_days > 0),
    action varchar(32) NOT NULL DEFAULT 'archive',
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT retention_action_check CHECK (action IN ('archive', 'delete', 'anonymize'))
);

CREATE INDEX IF NOT EXISTS idx_retention_policies_domain ON ops.data_retention_policies(data_domain, enabled);

CREATE TABLE IF NOT EXISTS ops.retention_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id uuid REFERENCES ops.data_retention_policies(id) ON DELETE SET NULL,
    status varchar(32) NOT NULL DEFAULT 'queued',
    target_before timestamptz NOT NULL,
    affected_rows integer NOT NULL DEFAULT 0 CHECK (affected_rows >= 0),
    error_message text,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT retention_jobs_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_retention_jobs_status_created_at ON ops.retention_jobs(status, created_at);

CREATE TABLE IF NOT EXISTS ops.external_sync_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    provider varchar(64) NOT NULL,
    resource_type varchar(128) NOT NULL,
    sync_mode varchar(32) NOT NULL DEFAULT 'incremental',
    status varchar(32) NOT NULL DEFAULT 'queued',
    cursor_before varchar(255),
    cursor_after varchar(255),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    result jsonb,
    retry_count integer NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    error_message text,
    scheduled_at timestamptz,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT external_sync_jobs_mode_check CHECK (sync_mode IN ('full', 'incremental', 'webhook_reconcile')),
    CONSTRAINT external_sync_jobs_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_external_sync_jobs_status_scheduled ON ops.external_sync_jobs(status, scheduled_at);

CREATE TABLE IF NOT EXISTS ops.external_sync_cursors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    provider varchar(64) NOT NULL,
    resource_type varchar(128) NOT NULL,
    cursor_value varchar(255),
    last_synced_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_cursors_provider_resource ON ops.external_sync_cursors(coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), provider, resource_type);

CREATE TABLE IF NOT EXISTS ops.feature_flags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_key varchar(128) NOT NULL,
    description text,
    enabled boolean NOT NULL DEFAULT false,
    default_variant varchar(64),
    rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_feature_flags_key ON ops.feature_flags(flag_key);

CREATE TABLE IF NOT EXISTS ops.release_rollouts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type varchar(64) NOT NULL,
    target_key varchar(128) NOT NULL,
    version varchar(128) NOT NULL,
    rollout_percent numeric(5, 2) NOT NULL DEFAULT 0 CHECK (rollout_percent >= 0 AND rollout_percent <= 100),
    status varchar(32) NOT NULL DEFAULT 'draft',
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT release_rollouts_target_type_check CHECK (target_type IN ('prompt', 'knowledge', 'workflow', 'tool', 'model')),
    CONSTRAINT release_rollouts_status_check CHECK (status IN ('draft', 'active', 'paused', 'completed', 'rolled_back'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_release_rollouts_target ON ops.release_rollouts(target_type, target_key, version);

CREATE TABLE IF NOT EXISTS ops.tool_fallback_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_name varchar(128) NOT NULL,
    timeout_ms integer NOT NULL DEFAULT 5000 CHECK (timeout_ms > 0),
    retry_count integer NOT NULL DEFAULT 1 CHECK (retry_count >= 0),
    fallback_action varchar(64) NOT NULL DEFAULT 'handoff',
    cache_ttl_seconds integer CHECK (cache_ttl_seconds IS NULL OR cache_ttl_seconds >= 0),
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tool_fallback_action_check CHECK (fallback_action IN ('use_cache', 'handoff', 'apology', 'retry_later'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_fallback_policies_tool_name ON ops.tool_fallback_policies(tool_name);

CREATE TABLE IF NOT EXISTS ops.tool_invocation_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_name varchar(128) NOT NULL,
    tool_category varchar(64) NOT NULL,
    permission_code varchar(128),
    requires_human_approval boolean NOT NULL DEFAULT false,
    idempotency_required boolean NOT NULL DEFAULT true,
    audit_required boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tool_invocation_category_check CHECK (tool_category IN ('query', 'create', 'update', 'high_risk'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_invocation_policies_tool_name ON ops.tool_invocation_policies(tool_name);

CREATE TABLE IF NOT EXISTS audit.metrics_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    metric_name varchar(128) NOT NULL,
    metric_value numeric(18, 6) NOT NULL,
    dimensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    trace_id varchar(128),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_metrics_events_name_created_at ON audit.metrics_events(metric_name, created_at DESC);

CREATE TABLE IF NOT EXISTS audit.cost_usage_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    cost_scope varchar(128) NOT NULL,
    provider varchar(128),
    model_name varchar(128),
    prompt_tokens integer CHECK (prompt_tokens IS NULL OR prompt_tokens >= 0),
    completion_tokens integer CHECK (completion_tokens IS NULL OR completion_tokens >= 0),
    rag_tokens integer CHECK (rag_tokens IS NULL OR rag_tokens >= 0),
    tool_calls integer NOT NULL DEFAULT 0 CHECK (tool_calls >= 0),
    estimated_cost numeric(18, 6),
    trace_id varchar(128),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cost_usage_events_scope_created_at ON audit.cost_usage_events(cost_scope, created_at DESC);

CREATE TABLE IF NOT EXISTS audit.alert_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    alert_name varchar(128) NOT NULL,
    severity varchar(32) NOT NULL DEFAULT 'info',
    status varchar(32) NOT NULL DEFAULT 'open',
    source varchar(128),
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT alert_events_severity_check CHECK (severity IN ('info', 'low', 'medium', 'high', 'critical')),
    CONSTRAINT alert_events_status_check CHECK (status IN ('open', 'acknowledged', 'resolved', 'ignored'))
);

CREATE INDEX IF NOT EXISTS idx_alert_events_status_severity ON audit.alert_events(status, severity, created_at DESC);

CREATE TABLE IF NOT EXISTS knowledge.evaluation_sets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    name varchar(128) NOT NULL,
    description text,
    target_type varchar(64) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT evaluation_sets_target_type_check CHECK (target_type IN ('prompt', 'knowledge', 'workflow', 'tool', 'model')),
    CONSTRAINT evaluation_sets_status_check CHECK (status IN ('active', 'archived'))
);

CREATE TABLE IF NOT EXISTS knowledge.evaluation_cases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_set_id uuid NOT NULL REFERENCES knowledge.evaluation_sets(id) ON DELETE CASCADE,
    category varchar(128) NOT NULL,
    input_payload jsonb NOT NULL,
    expected_behavior jsonb NOT NULL,
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_evaluation_cases_category ON knowledge.evaluation_cases(category);

CREATE TABLE IF NOT EXISTS knowledge.evaluation_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_set_id uuid REFERENCES knowledge.evaluation_sets(id) ON DELETE SET NULL,
    target_type varchar(64) NOT NULL,
    target_version varchar(128) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'queued',
    summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT evaluation_runs_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS knowledge.evaluation_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_run_id uuid NOT NULL REFERENCES knowledge.evaluation_runs(id) ON DELETE CASCADE,
    evaluation_case_id uuid REFERENCES knowledge.evaluation_cases(id) ON DELETE SET NULL,
    passed boolean NOT NULL,
    score numeric(5, 2),
    result_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_evaluation_results_run_passed ON knowledge.evaluation_results(evaluation_run_id, passed);

CREATE TABLE IF NOT EXISTS support.agent_workbench_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    user_id uuid REFERENCES core.users(id) ON DELETE SET NULL,
    conversation_id uuid REFERENCES support.conversations(id) ON DELETE CASCADE,
    handoff_queue_id uuid REFERENCES support.handoff_queue(id) ON DELETE SET NULL,
    status varchar(32) NOT NULL DEFAULT 'active',
    opened_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT agent_workbench_sessions_status_check CHECK (status IN ('active', 'paused', 'closed'))
);

CREATE INDEX IF NOT EXISTS idx_agent_workbench_sessions_user_status ON support.agent_workbench_sessions(user_id, status, opened_at DESC);

INSERT INTO core.permissions(code, resource, action, description, risk_level) VALUES
('orders.read', 'orders', 'read', 'Read order data', 'normal'),
('resumes.read', 'resumes', 'read', 'Read resume data', 'high'),
('refunds.handle', 'refunds', 'update', 'Handle refund workflow', 'critical'),
('audit.read', 'audit', 'read', 'Read audit logs', 'critical'),
('pii.read_full', 'pii', 'read_full', 'Read full sensitive personal data', 'critical')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.data_masking_policies(policy_name, resource, field_name, masking_strategy, allowed_permission_code) VALUES
('phone default masking', 'customer', 'phone', 'partial', 'pii.read_full'),
('address default masking', 'order', 'shipping_address', 'partial', 'pii.read_full'),
('resume default masking', 'resume', 'content', 'redact', 'resumes.read'),
('chat default masking', 'message', 'content', 'partial', 'audit.read'),
('api response default masking', 'api_response', 'payload', 'redact', 'pii.read_full')
ON CONFLICT DO NOTHING;

INSERT INTO ops.tool_fallback_policies(tool_name, timeout_ms, retry_count, fallback_action, cache_ttl_seconds) VALUES
('get_order', 5000, 1, 'use_cache', 300),
('get_product', 5000, 1, 'use_cache', 300),
('get_logistics', 7000, 1, 'handoff', 300),
('create_ticket', 5000, 1, 'retry_later', null)
ON CONFLICT (tool_name) DO NOTHING;

INSERT INTO ops.tool_invocation_policies(tool_name, tool_category, permission_code, requires_human_approval, idempotency_required, audit_required) VALUES
('get_order', 'query', 'orders.read', false, false, true),
('get_product', 'query', null, false, false, true),
('get_logistics', 'query', 'orders.read', false, false, true),
('create_ticket', 'create', null, false, true, true),
('refund_order', 'high_risk', 'refunds.handle', true, true, true)
ON CONFLICT (tool_name) DO NOTHING;
