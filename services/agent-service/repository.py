# -*- coding: utf-8 -*-
"""Persistence helpers for the agent service."""

from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Any

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


DATABASE_URL = os.getenv("BUSINESS_DATABASE_URL")

pool: ConnectionPool | None = None
if DATABASE_URL:
    pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=5, open=False)


@contextmanager
def connection():
    if pool is None:
        yield None
        return
    pool.open(wait=True)
    with pool.connection() as conn:
        yield conn


def ensure_customer(platform: str, customer_id: str) -> str | None:
    query = """
        insert into core.customers(platform, platform_customer_id, nickname)
        values (%s, %s, %s)
        on conflict (platform, platform_customer_id)
        do update set updated_at = now()
        returning id::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor() as cur:
            cur.execute(query, (platform, customer_id, customer_id))
            return cur.fetchone()[0]


def ensure_conversation(platform: str, conversation_id: str, customer_uuid: str | None) -> str | None:
    query = """
        insert into support.conversations(platform, platform_conversation_id, customer_id, status)
        values (%s, %s, %s::uuid, 'ai_handling')
        on conflict (platform, platform_conversation_id)
        do update set updated_at = now(), customer_id = coalesce(excluded.customer_id, support.conversations.customer_id)
        returning id::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor() as cur:
            cur.execute(query, (platform, conversation_id, customer_uuid))
            return cur.fetchone()[0]


def save_context_snapshot(
    conversation_uuid: str | None,
    trace_id: str,
    user_message: str,
    tool_context: dict[str, Any],
    policy_context: dict[str, Any],
    prompt_context: dict[str, Any],
    retrieval_context: list[dict[str, Any]] | None = None,
) -> str | None:
    query = """
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
        values (%s::uuid, %s, %s, '[]'::jsonb, '{}'::jsonb, %s::jsonb, %s::jsonb, %s::jsonb, %s::jsonb, 4000)
        returning id::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor() as cur:
            import json

            cur.execute(
                query,
                (
                    conversation_uuid,
                    trace_id,
                    user_message,
                    json.dumps(retrieval_context or [], ensure_ascii=False),
                    json.dumps(tool_context, ensure_ascii=False),
                    json.dumps(policy_context, ensure_ascii=False),
                    json.dumps(prompt_context, ensure_ascii=False),
                ),
            )
            snapshot_id = cur.fetchone()[0]
            if conversation_uuid:
                cur.execute(
                    "update support.conversations set last_context_snapshot_id = %s::uuid where id = %s::uuid",
                    (snapshot_id, conversation_uuid),
                )
            return snapshot_id


def save_message(conversation_uuid: str | None, sender_type: str, content: str, context_snapshot_id: str | None) -> None:
    if not conversation_uuid:
        return
    query = """
        insert into support.messages(conversation_id, sender_type, content, context_snapshot_id)
        values (%s::uuid, %s, %s, %s::uuid)
    """
    with connection() as conn:
        if conn is None:
            return
        with conn.cursor() as cur:
            cur.execute(query, (conversation_uuid, sender_type, content, context_snapshot_id))


def save_tool_log(trace_id: str, tool_name: str, request_payload: dict[str, Any], response_payload: dict[str, Any], status: str, latency_ms: int) -> None:
    query = """
        insert into audit.tool_call_logs(tool_name, request_payload, response_payload, status, latency_ms, trace_id)
        values (%s, %s::jsonb, %s::jsonb, %s, %s, %s)
    """
    with connection() as conn:
        if conn is None:
            return
        with conn.cursor() as cur:
            import json

            cur.execute(
                query,
                (
                    tool_name,
                    json.dumps(request_payload, ensure_ascii=False),
                    json.dumps(response_payload, ensure_ascii=False),
                    status,
                    latency_ms,
                    trace_id,
                ),
            )


def save_ai_log(
    trace_id: str,
    conversation_uuid: str | None,
    tool_used: bool,
    rag_used: bool = False,
    model_provider: str = "local",
    model_name: str = "agent-service-template",
    metadata: dict[str, Any] | None = None,
) -> None:
    query = """
        insert into audit.ai_response_logs(conversation_id, model_provider, model_name, rag_used, tool_used, metadata, trace_id)
        values (%s::uuid, %s, %s, %s, %s, %s::jsonb, %s)
    """
    with connection() as conn:
        if conn is None:
            return
        with conn.cursor() as cur:
            import json

            log_metadata = {"trace_id": trace_id, **(metadata or {})}
            cur.execute(
                query,
                (conversation_uuid, model_provider, model_name, rag_used, tool_used, json.dumps(log_metadata), trace_id),
            )


def save_metric(metric_name: str, metric_value: float, dimensions: dict[str, Any], trace_id: str | None = None) -> None:
    query = """
        insert into audit.metrics_events(metric_name, metric_value, dimensions, trace_id)
        values (%s, %s, %s::jsonb, %s)
    """
    with connection() as conn:
        if conn is None:
            return
        with conn.cursor() as cur:
            import json

            cur.execute(query, (metric_name, metric_value, json.dumps(dimensions), trace_id))


def save_cost_event(
    trace_id: str,
    cost_scope: str,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    rag_tokens: int = 0,
    tool_calls: int = 0,
    provider: str = "local",
    model_name: str = "agent-service-template",
) -> None:
    query = """
        insert into audit.cost_usage_events(
            cost_scope,
            provider,
            model_name,
            prompt_tokens,
            completion_tokens,
            rag_tokens,
            tool_calls,
            estimated_cost,
            trace_id
        )
        values (%s, %s, %s, %s, %s, %s, %s, 0, %s)
    """
    with connection() as conn:
        if conn is None:
            return
        with conn.cursor() as cur:
            cur.execute(
                query,
                (cost_scope, provider, model_name, prompt_tokens, completion_tokens, rag_tokens, tool_calls, trace_id),
            )


def enqueue_handoff(
    conversation_uuid: str | None,
    customer_uuid: str | None,
    trigger_reason: str,
    priority: str,
    context_snapshot_id: str | None,
    payload: dict[str, Any],
) -> str | None:
    if not conversation_uuid:
        return None
    select_query = """
        select id::text
        from support.handoff_queue
        where conversation_id = %s::uuid and status in ('pending', 'assigned')
        order by created_at desc
        limit 1
    """
    insert_query = """
        insert into support.handoff_queue(
            conversation_id,
            customer_id,
            trigger_reason,
            priority,
            context_snapshot_id,
            payload
        )
        values (%s::uuid, %s::uuid, %s, %s, %s::uuid, %s::jsonb)
        returning id::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor() as cur:
            cur.execute(select_query, (conversation_uuid,))
            existing = cur.fetchone()
            if existing:
                return existing[0]

            import json

            cur.execute(
                insert_query,
                (
                    conversation_uuid,
                    customer_uuid,
                    trigger_reason,
                    priority,
                    context_snapshot_id,
                    json.dumps(payload, ensure_ascii=False),
                ),
            )
            return cur.fetchone()[0]


def list_handoffs(status: str = "pending", limit: int = 20) -> list[dict[str, Any]]:
    query = """
        select id::text,
               conversation_id::text,
               customer_id::text,
               trigger_reason,
               priority,
               status,
               created_at::text
        from support.handoff_queue
        where status = %s
        order by
            case priority
                when 'urgent' then 1
                when 'high' then 2
                when 'normal' then 3
                else 4
            end,
            created_at asc
        limit %s
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (status, limit))
            return list(cur.fetchall())


def resolve_handoff(handoff_id: str) -> bool:
    query = """
        update support.handoff_queue
        set status = 'resolved', resolved_at = now()
        where id = %s::uuid and status in ('pending', 'assigned')
    """
    with connection() as conn:
        if conn is None:
            return False
        with conn.cursor() as cur:
            cur.execute(query, (handoff_id,))
            return cur.rowcount > 0
