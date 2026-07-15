CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS commerce;
CREATE SCHEMA IF NOT EXISTS recruitment;
CREATE SCHEMA IF NOT EXISTS support;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE core.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id varchar(128),
    username varchar(128),
    display_name varchar(128),
    email varchar(255),
    phone_masked varchar(64),
    role varchar(64) NOT NULL DEFAULT 'user',
    status varchar(32) NOT NULL DEFAULT 'active',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_status_check CHECK (status IN ('active', 'disabled', 'deleted'))
);

CREATE UNIQUE INDEX uq_users_external_id ON core.users(external_id) WHERE external_id IS NOT NULL;
CREATE UNIQUE INDEX uq_users_email ON core.users(email) WHERE email IS NOT NULL;

CREATE TABLE core.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    platform varchar(64) NOT NULL,
    platform_customer_id varchar(128) NOT NULL,
    nickname varchar(128),
    phone_masked varchar(64),
    email varchar(255),
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (platform, platform_customer_id)
);

CREATE TABLE commerce.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sku_id varchar(128) NOT NULL UNIQUE,
    name varchar(255) NOT NULL,
    category varchar(128),
    price numeric(12, 2) NOT NULL CHECK (price >= 0),
    stock integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
    status varchar(32) NOT NULL DEFAULT 'active',
    description text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT products_status_check CHECK (status IN ('active', 'inactive', 'sold_out', 'discontinued'))
);

CREATE TABLE commerce.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id varchar(128) NOT NULL UNIQUE,
    customer_id uuid REFERENCES core.customers(id),
    platform varchar(64) NOT NULL DEFAULT 'demo',
    status varchar(32) NOT NULL,
    total_amount numeric(12, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    recipient_name varchar(128),
    phone_masked varchar(64),
    shipping_address_masked text,
    logistics_company varchar(128),
    logistics_no varchar(128),
    refund_status varchar(64),
    cancel_reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    ordered_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT orders_status_check CHECK (status IN ('pending_payment', 'pending_ship', 'shipped', 'completed', 'cancelled', 'refunding', 'refunded'))
);

CREATE INDEX idx_orders_customer_id ON commerce.orders(customer_id);
CREATE INDEX idx_orders_status_created_at ON commerce.orders(status, created_at DESC);
CREATE INDEX idx_orders_logistics_no ON commerce.orders(logistics_no) WHERE logistics_no IS NOT NULL;

CREATE TABLE commerce.order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES commerce.orders(id) ON DELETE CASCADE,
    product_id uuid REFERENCES commerce.products(id),
    sku_id varchar(128) NOT NULL,
    product_name varchar(255) NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price numeric(12, 2) NOT NULL CHECK (unit_price >= 0),
    total_price numeric(12, 2) NOT NULL CHECK (total_price >= 0),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_items_order_id ON commerce.order_items(order_id);
CREATE INDEX idx_order_items_sku_id ON commerce.order_items(sku_id);

CREATE TABLE commerce.logistics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_no varchar(128) NOT NULL UNIQUE,
    order_id uuid REFERENCES commerce.orders(id),
    company varchar(128) NOT NULL,
    status varchar(64) NOT NULL,
    estimated_delivery date,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_logistics_order_id ON commerce.logistics(order_id);

CREATE TABLE commerce.logistics_traces (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    logistics_id uuid NOT NULL REFERENCES commerce.logistics(id) ON DELETE CASCADE,
    event_time timestamptz NOT NULL,
    location varchar(255),
    description text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_logistics_traces_logistics_time ON commerce.logistics_traces(logistics_id, event_time DESC);

CREATE TABLE recruitment.resumes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES core.users(id),
    candidate_name varchar(128),
    phone_masked varchar(64),
    email varchar(255),
    source varchar(64) NOT NULL DEFAULT 'upload',
    object_uri text,
    parsed_status varchar(32) NOT NULL DEFAULT 'pending',
    structured_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT resumes_parsed_status_check CHECK (parsed_status IN ('pending', 'processing', 'parsed', 'failed'))
);

CREATE INDEX idx_resumes_user_id ON recruitment.resumes(user_id);
CREATE INDEX idx_resumes_parsed_status ON recruitment.resumes(parsed_status);

CREATE TABLE recruitment.jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_code varchar(128) NOT NULL UNIQUE,
    title varchar(255) NOT NULL,
    department varchar(128),
    location varchar(128),
    status varchar(32) NOT NULL DEFAULT 'open',
    description text,
    requirements text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT jobs_status_check CHECK (status IN ('draft', 'open', 'paused', 'closed'))
);

CREATE INDEX idx_jobs_status_created_at ON recruitment.jobs(status, created_at DESC);

CREATE TABLE recruitment.applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resume_id uuid NOT NULL REFERENCES recruitment.resumes(id),
    job_id uuid NOT NULL REFERENCES recruitment.jobs(id),
    status varchar(32) NOT NULL DEFAULT 'submitted',
    score numeric(5, 2),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    submitted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (resume_id, job_id),
    CONSTRAINT applications_status_check CHECK (status IN ('submitted', 'screening', 'interview', 'offer', 'rejected', 'withdrawn'))
);

CREATE INDEX idx_applications_job_status ON recruitment.applications(job_id, status);

CREATE TABLE support.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    platform varchar(64) NOT NULL,
    platform_conversation_id varchar(128) NOT NULL,
    customer_id uuid REFERENCES core.customers(id),
    status varchar(32) NOT NULL DEFAULT 'open',
    assigned_user_id uuid REFERENCES core.users(id),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (platform, platform_conversation_id),
    CONSTRAINT conversations_status_check CHECK (status IN ('open', 'ai_handling', 'human_handling', 'closed'))
);

CREATE INDEX idx_conversations_customer_id ON support.conversations(customer_id);
CREATE INDEX idx_conversations_status_updated_at ON support.conversations(status, updated_at DESC);

CREATE TABLE support.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES support.conversations(id) ON DELETE CASCADE,
    sender_type varchar(32) NOT NULL,
    sender_id uuid,
    content text NOT NULL,
    ai_intent varchar(128),
    tool_called varchar(128),
    rag_used boolean NOT NULL DEFAULT false,
    handoff_required boolean NOT NULL DEFAULT false,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT messages_sender_type_check CHECK (sender_type IN ('customer', 'ai', 'human', 'system'))
);

CREATE INDEX idx_messages_conversation_id_created_at ON support.messages(conversation_id, created_at);
CREATE INDEX idx_messages_handoff_required ON support.messages(handoff_required) WHERE handoff_required = true;

CREATE TABLE support.tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid REFERENCES support.conversations(id),
    customer_id uuid REFERENCES core.customers(id),
    type varchar(64) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'open',
    priority varchar(32) NOT NULL DEFAULT 'normal',
    subject varchar(255),
    description text,
    assigned_user_id uuid REFERENCES core.users(id),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tickets_status_check CHECK (status IN ('open', 'pending', 'resolved', 'closed')),
    CONSTRAINT tickets_priority_check CHECK (priority IN ('low', 'normal', 'high', 'urgent'))
);

CREATE INDEX idx_tickets_status_priority ON support.tickets(status, priority);

CREATE TABLE ops.upload_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid REFERENCES core.users(id),
    object_uri text NOT NULL,
    file_name varchar(255),
    content_type varchar(128),
    status varchar(32) NOT NULL DEFAULT 'pending',
    error_message text,
    expires_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT upload_tasks_status_check CHECK (status IN ('pending', 'uploading', 'uploaded', 'processing', 'completed', 'failed', 'expired'))
);

CREATE INDEX idx_upload_tasks_status_expires_at ON ops.upload_tasks(status, expires_at);

CREATE TABLE ops.async_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_type varchar(128) NOT NULL,
    status varchar(32) NOT NULL DEFAULT 'queued',
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    result jsonb,
    error_message text,
    retry_count integer NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    scheduled_at timestamptz,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT async_tasks_status_check CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'))
);

CREATE INDEX idx_async_tasks_status_scheduled_at ON ops.async_tasks(status, scheduled_at);

CREATE TABLE ops.drafts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid REFERENCES core.users(id),
    draft_type varchar(128) NOT NULL,
    content jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(32) NOT NULL DEFAULT 'active',
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT drafts_status_check CHECK (status IN ('active', 'submitted', 'discarded', 'expired'))
);

CREATE INDEX idx_drafts_owner_type ON ops.drafts(owner_user_id, draft_type);

CREATE TABLE audit.audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id uuid,
    actor_type varchar(64) NOT NULL DEFAULT 'user',
    action varchar(128) NOT NULL,
    resource_type varchar(128) NOT NULL,
    resource_id varchar(128),
    before_data jsonb,
    after_data jsonb,
    ip_address inet,
    user_agent text,
    trace_id varchar(128),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_actor_created_at ON audit.audit_logs(actor_user_id, created_at DESC);
CREATE INDEX idx_audit_logs_resource_created_at ON audit.audit_logs(resource_type, resource_id, created_at DESC);

CREATE TABLE audit.approval_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_type varchar(128) NOT NULL,
    resource_type varchar(128) NOT NULL,
    resource_id varchar(128) NOT NULL,
    requester_user_id uuid,
    approver_user_id uuid,
    status varchar(32) NOT NULL DEFAULT 'pending',
    comment text,
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    CONSTRAINT approval_records_status_check CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'))
);

CREATE INDEX idx_approval_records_resource ON audit.approval_records(resource_type, resource_id);

CREATE TABLE audit.status_change_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type varchar(128) NOT NULL,
    resource_id varchar(128) NOT NULL,
    from_status varchar(64),
    to_status varchar(64) NOT NULL,
    changed_by_user_id uuid,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_status_change_logs_resource_created_at ON audit.status_change_logs(resource_type, resource_id, created_at DESC);

CREATE TABLE audit.tool_call_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid,
    message_id uuid,
    tool_name varchar(128) NOT NULL,
    request_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    response_payload jsonb,
    status varchar(32) NOT NULL,
    latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tool_call_logs_status_check CHECK (status IN ('success', 'failed', 'timeout'))
);

CREATE INDEX idx_tool_call_logs_conversation_created_at ON audit.tool_call_logs(conversation_id, created_at DESC);

CREATE TABLE audit.ai_response_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid,
    message_id uuid,
    model_provider varchar(128),
    model_name varchar(128),
    prompt_tokens integer CHECK (prompt_tokens IS NULL OR prompt_tokens >= 0),
    completion_tokens integer CHECK (completion_tokens IS NULL OR completion_tokens >= 0),
    rag_used boolean NOT NULL DEFAULT false,
    tool_used boolean NOT NULL DEFAULT false,
    latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_response_logs_conversation_created_at ON audit.ai_response_logs(conversation_id, created_at DESC);

CREATE TABLE audit.handoff_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid,
    trigger_reason varchar(128) NOT NULL,
    trigger_message text,
    status varchar(32) NOT NULL DEFAULT 'pending',
    assigned_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT handoff_records_status_check CHECK (status IN ('pending', 'assigned', 'resolved', 'cancelled'))
);

CREATE INDEX idx_handoff_records_conversation_created_at ON audit.handoff_records(conversation_id, created_at DESC);

CREATE TABLE audit.login_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid,
    login_type varchar(64) NOT NULL,
    status varchar(32) NOT NULL,
    ip_address inet,
    user_agent text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT login_logs_status_check CHECK (status IN ('success', 'failed'))
);

CREATE INDEX idx_login_logs_user_created_at ON audit.login_logs(user_id, created_at DESC);
