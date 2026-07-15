param(
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

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

$sql = @'
do $$
declare
  v_customer_id uuid;
  v_conversation_id uuid;
  v_context_id uuid;
begin
  insert into core.customers(platform, platform_customer_id, nickname)
  values ('governance-test', 'customer-001', 'Governance Customer')
  on conflict (platform, platform_customer_id) do update set nickname = excluded.nickname
  returning id into v_customer_id;

  insert into support.conversations(platform, platform_conversation_id, customer_id, status)
  values ('governance-test', 'conversation-001', v_customer_id, 'open')
  on conflict (platform, platform_conversation_id) do update set customer_id = excluded.customer_id
  returning id into v_conversation_id;

  insert into memory.context_snapshots(
    conversation_id,
    trace_id,
    user_message,
    recent_messages,
    long_term_memory,
    retrieval_context,
    tool_context,
    policy_context,
    prompt_context,
    token_budget
  )
  values (
    v_conversation_id,
    'trace-governance-001',
    'Where is my order?',
    '[]'::jsonb,
    '{"preference":"concise"}'::jsonb,
    '[]'::jsonb,
    '{"order_id":"ORD-DBTEST"}'::jsonb,
    '{"handoff_required":false}'::jsonb,
    '{"system":"customer-service"}'::jsonb,
    4000
  )
  returning id into v_context_id;

  update support.conversations
  set last_context_snapshot_id = v_context_id
  where id = v_conversation_id;

  insert into support.messages(conversation_id, sender_type, content, platform_message_id, context_snapshot_id, message_hash)
  values (v_conversation_id, 'customer', 'Where is my order?', 'msg-001', v_context_id, 'hash-msg-001')
  on conflict (conversation_id, platform_message_id) where platform_message_id is not null
  do update set context_snapshot_id = excluded.context_snapshot_id;

  begin
    insert into support.messages(conversation_id, sender_type, content, platform_message_id)
    values (v_conversation_id, 'customer', 'duplicate', 'msg-001');
    raise exception 'duplicate platform_message_id was accepted';
  exception when unique_violation then
    null;
  end;

  insert into ops.webhook_events(provider, event_id, event_type, payload)
  values ('governance-test', 'event-001', 'message.created', '{}'::jsonb)
  on conflict (provider, event_id) do update set processing_status = 'ignored';

  begin
    insert into ops.webhook_events(provider, event_id, event_type, payload)
    values ('governance-test', 'event-001', 'message.created', '{}'::jsonb);
    raise exception 'duplicate webhook event was accepted';
  exception when unique_violation then
    null;
  end;

  insert into ops.idempotency_keys(scope, idempotency_key, request_hash, expires_at)
  values ('reply-generation', 'idem-001', 'hash-request-001', now() + interval '1 day')
  on conflict (scope, idempotency_key) do update set updated_at = now();

  begin
    insert into ops.idempotency_keys(scope, idempotency_key, expires_at)
    values ('reply-generation', 'idem-001', now() + interval '1 day');
    raise exception 'duplicate idempotency key was accepted';
  exception when unique_violation then
    null;
  end;

  insert into memory.long_term_memories(memory_scope, scope_id, memory_key, memory_value, source_type)
  values ('customer', v_customer_id::text, 'tone_preference', '{"value":"concise"}'::jsonb, 'human')
  on conflict (memory_scope, scope_id, memory_key)
  do update set memory_value = excluded.memory_value, updated_at = now();
end $$;
'@

$sql | docker exec -i ai20-business-db-1 psql -U app_user -d app_business -v ON_ERROR_STOP=1 | Out-Null

"OK data governance rules verified"
