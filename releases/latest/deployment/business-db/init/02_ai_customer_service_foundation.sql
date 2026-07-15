CREATE SCHEMA IF NOT EXISTS knowledge;
CREATE SCHEMA IF NOT EXISTS memory;

CREATE TABLE IF NOT EXISTS support.customer_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES core.customers(id) ON DELETE CASCADE,
    lifecycle_stage varchar(64) NOT NULL DEFAULT 'new',
    preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
    risk_flags text[] NOT NULL DEFAULT ARRAY[]::text[],
    memory_summary text,
    last_interaction_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_profiles_lifecycle_check CHECK (lifecycle_stage IN ('new', 'active', 'vip', 'risk', 'churned'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_profiles_customer_id ON support.customer_profiles(customer_id);

CREATE TABLE IF NOT EXISTS support.conversation_summaries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES support.conversations(id) ON DELETE CASCADE,
    summary text NOT NULL,
    facts jsonb NOT NULL DEFAULT '{}'::jsonb,
    preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
    risk_flags text[] NOT NULL DEFAULT ARRAY[]::text[],
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    last_message_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_summaries_conversation_id ON support.conversation_summaries(conversation_id);

CREATE TABLE IF NOT EXISTS memory.long_term_memories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_scope varchar(64) NOT NULL,
    scope_id varchar(128) NOT NULL,
    memory_key varchar(128) NOT NULL,
    memory_value jsonb NOT NULL,
    confidence numeric(4, 3) NOT NULL DEFAULT 1 CHECK (confidence >= 0 AND confidence <= 1),
    source_type varchar(64) NOT NULL DEFAULT 'summary',
    source_id varchar(128),
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT long_term_memories_scope_check CHECK (memory_scope IN ('customer', 'conversation', 'user', 'candidate')),
    CONSTRAINT long_term_memories_source_check CHECK (source_type IN ('summary', 'message', 'tool', 'human', 'import'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_long_term_memories_scope_key ON memory.long_term_memories(memory_scope, scope_id, memory_key);
CREATE INDEX IF NOT EXISTS idx_long_term_memories_scope ON memory.long_term_memories(memory_scope, scope_id);

CREATE TABLE IF NOT EXISTS memory.context_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid REFERENCES support.conversations(id) ON DELETE SET NULL,
    trace_id varchar(128),
    user_message text,
    recent_messages jsonb NOT NULL DEFAULT '[]'::jsonb,
    long_term_memory jsonb NOT NULL DEFAULT '{}'::jsonb,
    retrieval_context jsonb NOT NULL DEFAULT '[]'::jsonb,
    tool_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    policy_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    prompt_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    token_budget integer CHECK (token_budget IS NULL OR token_budget >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_context_snapshots_conversation_created_at ON memory.context_snapshots(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_context_snapshots_trace_id ON memory.context_snapshots(trace_id) WHERE trace_id IS NOT NULL;

ALTER TABLE support.conversations ADD COLUMN IF NOT EXISTS last_context_snapshot_id uuid REFERENCES memory.context_snapshots(id);
ALTER TABLE support.messages ADD COLUMN IF NOT EXISTS platform_message_id varchar(128);
ALTER TABLE support.messages ADD COLUMN IF NOT EXISTS context_snapshot_id uuid REFERENCES memory.context_snapshots(id);
ALTER TABLE support.messages ADD COLUMN IF NOT EXISTS message_hash varchar(128);

CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_platform_message_id ON support.messages(conversation_id, platform_message_id) WHERE platform_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_context_snapshot_id ON support.messages(context_snapshot_id) WHERE context_snapshot_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS support.message_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id uuid NOT NULL REFERENCES support.messages(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES core.customers(id),
    rating smallint CHECK (rating IS NULL OR (rating >= 1 AND rating <= 5)),
    feedback_type varchar(64) NOT NULL DEFAULT 'user_rating',
    comment text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT message_feedback_type_check CHECK (feedback_type IN ('user_rating', 'thumbs_up', 'thumbs_down', 'human_review', 'auto_eval'))
);

CREATE INDEX IF NOT EXISTS idx_message_feedback_message_id ON support.message_feedback(message_id);

CREATE TABLE IF NOT EXISTS support.handoff_queue (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES support.conversations(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES core.customers(id),
    trigger_reason varchar(128) NOT NULL,
    priority varchar(32) NOT NULL DEFAULT 'normal',
    status varchar(32) NOT NULL DEFAULT 'pending',
    assigned_user_id uuid REFERENCES core.users(id),
    context_snapshot_id uuid REFERENCES memory.context_snapshots(id),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    assigned_at timestamptz,
    resolved_at timestamptz,
    CONSTRAINT handoff_queue_priority_check CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    CONSTRAINT handoff_queue_status_check CHECK (status IN ('pending', 'assigned', 'resolved', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_handoff_queue_status_priority ON support.handoff_queue(status, priority, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_handoff_queue_pending_conversation ON support.handoff_queue(conversation_id) WHERE status IN ('pending', 'assigned');

CREATE TABLE IF NOT EXISTS ops.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider varchar(64) NOT NULL,
    event_id varchar(128) NOT NULL,
    event_type varchar(128) NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    processing_status varchar(32) NOT NULL DEFAULT 'received',
    error_message text,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    CONSTRAINT webhook_events_status_check CHECK (processing_status IN ('received', 'processing', 'processed', 'failed', 'ignored'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_events_provider_event_id ON ops.webhook_events(provider, event_id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_status_received_at ON ops.webhook_events(processing_status, received_at);

CREATE TABLE IF NOT EXISTS ops.idempotency_keys (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope varchar(128) NOT NULL,
    idempotency_key varchar(255) NOT NULL,
    request_hash varchar(128),
    status varchar(32) NOT NULL DEFAULT 'started',
    response_payload jsonb,
    locked_until timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT idempotency_keys_status_check CHECK (status IN ('started', 'succeeded', 'failed', 'expired'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_keys_scope_key ON ops.idempotency_keys(scope, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires_at ON ops.idempotency_keys(expires_at);

CREATE TABLE IF NOT EXISTS ops.cache_invalidation_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cache_namespace varchar(128) NOT NULL,
    cache_key_pattern varchar(255) NOT NULL,
    reason varchar(255),
    status varchar(32) NOT NULL DEFAULT 'queued',
    scheduled_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cache_invalidation_jobs_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_cache_invalidation_jobs_status_scheduled ON ops.cache_invalidation_jobs(status, scheduled_at);

CREATE TABLE IF NOT EXISTS knowledge.documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_uri text NOT NULL,
    title varchar(255) NOT NULL,
    document_type varchar(64) NOT NULL,
    owner_domain varchar(64) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'draft',
    current_version integer NOT NULL DEFAULT 1 CHECK (current_version > 0),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT documents_status_check CHECK (status IN ('draft', 'published', 'archived')),
    CONSTRAINT documents_type_check CHECK (document_type IN ('faq', 'policy', 'product_guide', 'job_description', 'resume', 'prompt', 'workflow'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_documents_source_uri ON knowledge.documents(source_uri);
CREATE INDEX IF NOT EXISTS idx_documents_owner_status ON knowledge.documents(owner_domain, status);

CREATE TABLE IF NOT EXISTS knowledge.document_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES knowledge.documents(id) ON DELETE CASCADE,
    version_no integer NOT NULL CHECK (version_no > 0),
    content_hash varchar(128) NOT NULL,
    object_uri text,
    change_summary text,
    status varchar(32) NOT NULL DEFAULT 'draft',
    created_by_user_id uuid REFERENCES core.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    CONSTRAINT document_versions_status_check CHECK (status IN ('draft', 'published', 'archived'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_document_versions_document_version ON knowledge.document_versions(document_id, version_no);
CREATE INDEX IF NOT EXISTS idx_document_versions_hash ON knowledge.document_versions(content_hash);

CREATE TABLE IF NOT EXISTS knowledge.document_chunks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_version_id uuid NOT NULL REFERENCES knowledge.document_versions(id) ON DELETE CASCADE,
    chunk_no integer NOT NULL CHECK (chunk_no > 0),
    content text NOT NULL,
    content_hash varchar(128) NOT NULL,
    embedding_ref varchar(255),
    token_count integer CHECK (token_count IS NULL OR token_count >= 0),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_document_chunks_version_chunk ON knowledge.document_chunks(document_version_id, chunk_no);
CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_ref ON knowledge.document_chunks(embedding_ref) WHERE embedding_ref IS NOT NULL;

CREATE TABLE IF NOT EXISTS knowledge.sync_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source varchar(128) NOT NULL,
    target varchar(128) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'queued',
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    result jsonb,
    error_message text,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sync_jobs_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_sync_jobs_status_created_at ON knowledge.sync_jobs(status, created_at);

CREATE TABLE IF NOT EXISTS audit.data_change_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type varchar(128) NOT NULL,
    resource_id varchar(128) NOT NULL,
    change_type varchar(64) NOT NULL,
    before_data jsonb,
    after_data jsonb,
    source varchar(128),
    trace_id varchar(128),
    changed_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT data_change_events_type_check CHECK (change_type IN ('create', 'update', 'delete', 'upsert', 'status_change'))
);

CREATE INDEX IF NOT EXISTS idx_data_change_events_resource_created_at ON audit.data_change_events(resource_type, resource_id, created_at DESC);

CREATE TABLE IF NOT EXISTS audit.security_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type varchar(128) NOT NULL,
    severity varchar(32) NOT NULL DEFAULT 'info',
    actor_user_id uuid,
    ip_address inet,
    user_agent text,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    trace_id varchar(128),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT security_events_severity_check CHECK (severity IN ('info', 'low', 'medium', 'high', 'critical'))
);

CREATE INDEX IF NOT EXISTS idx_security_events_type_created_at ON audit.security_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_severity_created_at ON audit.security_events(severity, created_at DESC);
