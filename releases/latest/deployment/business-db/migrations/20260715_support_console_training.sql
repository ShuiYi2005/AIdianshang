CREATE TABLE IF NOT EXISTS knowledge.training_topics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
    name varchar(128) NOT NULL,
    trigger_phrases text[] NOT NULL DEFAULT ARRAY[]::text[],
    reply_text text NOT NULL,
    store_scope varchar(128) NOT NULL DEFAULT 'simulated-store',
    product_scope varchar(128) NOT NULL DEFAULT 'all-products',
    channel varchar(64) NOT NULL DEFAULT 'simulated-ecommerce',
    status varchar(32) NOT NULL DEFAULT 'draft',
    current_version integer NOT NULL DEFAULT 0 CHECK (current_version >= 0),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT training_topics_status_check CHECK (status IN ('draft', 'published', 'archived'))
);

CREATE INDEX IF NOT EXISTS idx_training_topics_status_updated_at
    ON knowledge.training_topics(status, updated_at DESC);

CREATE TABLE IF NOT EXISTS knowledge.training_assets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id uuid NOT NULL REFERENCES knowledge.training_topics(id) ON DELETE CASCADE,
    asset_type varchar(16) NOT NULL,
    filename varchar(255) NOT NULL,
    mime_type varchar(128) NOT NULL,
    byte_size integer NOT NULL CHECK (byte_size >= 0 AND byte_size <= 16777216),
    storage_path varchar(512) NOT NULL,
    description text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT training_assets_type_check CHECK (asset_type IN ('text', 'image', 'video')),
    CONSTRAINT training_assets_storage_path_check CHECK (
        storage_path NOT LIKE '/%' AND position('..' in storage_path) = 0
    )
);

CREATE INDEX IF NOT EXISTS idx_training_assets_topic_id
    ON knowledge.training_assets(topic_id, created_at DESC);

CREATE TABLE IF NOT EXISTS knowledge.training_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id uuid NOT NULL REFERENCES knowledge.training_topics(id) ON DELETE CASCADE,
    version integer NOT NULL CHECK (version > 0),
    status varchar(32) NOT NULL DEFAULT 'published',
    snapshot jsonb NOT NULL,
    published_at timestamptz NOT NULL DEFAULT now(),
    rolled_back_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT training_versions_status_check CHECK (status IN ('published', 'superseded', 'rolled_back'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_training_versions_topic_version
    ON knowledge.training_versions(topic_id, version);

CREATE INDEX IF NOT EXISTS idx_training_versions_topic_status
    ON knowledge.training_versions(topic_id, status, version DESC);

CREATE TABLE IF NOT EXISTS audit.console_action_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid REFERENCES core.tenants(id) ON DELETE SET NULL,
    actor_role varchar(64) NOT NULL,
    action varchar(128) NOT NULL,
    target_type varchar(64) NOT NULL,
    target_id uuid,
    trace_id varchar(128),
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_console_action_logs_target_created_at
    ON audit.console_action_logs(target_type, target_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_console_action_logs_tenant_created_at
    ON audit.console_action_logs(tenant_id, created_at DESC);
