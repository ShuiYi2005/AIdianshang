"""Durable operations for the local customer-support console."""

from __future__ import annotations

import json
from typing import Any

from psycopg.rows import dict_row

from repository import connection


def _handoff_select_clause() -> str:
    return """
        select h.id::text,
               h.conversation_id::text,
               h.customer_id::text,
               h.tenant_id::text,
               h.trigger_reason,
               h.priority,
               h.status,
               h.payload,
               h.created_at::text,
               h.assigned_at::text,
               h.resolved_at::text,
               c.platform,
               c.platform_conversation_id,
               c.status as conversation_status,
               customer.nickname as customer_nickname,
               customer.platform_customer_id
        from support.handoff_queue h
        join support.conversations c on c.id = h.conversation_id
        left join core.customers customer on customer.id = h.customer_id
    """


def list_console_handoffs(status: str, limit: int) -> list[dict[str, Any]]:
    query = _handoff_select_clause() + """
        where h.status = %s
        order by
            case h.priority
                when 'urgent' then 1
                when 'high' then 2
                when 'normal' then 3
                else 4
            end,
            h.created_at asc
        limit %s
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (status, limit))
            return list(cur.fetchall())


def get_console_handoff(handoff_id: str) -> dict[str, Any] | None:
    query = _handoff_select_clause() + "where h.id = %s::uuid"
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (handoff_id,))
            return cur.fetchone()


def get_handoff_messages(handoff_id: str) -> list[dict[str, Any]]:
    query = """
        select m.id::text, m.sender_type, m.content, m.created_at::text, m.metadata
        from support.messages m
        join support.handoff_queue h on h.conversation_id = m.conversation_id
        where h.id = %s::uuid
        order by m.created_at asc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (handoff_id,))
            return list(cur.fetchall())


def get_handoff_tickets(handoff_id: str) -> list[dict[str, Any]]:
    query = """
        select t.id::text, t.type, t.status, t.priority, t.subject, t.description, t.created_at::text, t.updated_at::text
        from support.tickets t
        join support.handoff_queue h on h.conversation_id = t.conversation_id
        where h.id = %s::uuid
        order by t.created_at desc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (handoff_id,))
            return list(cur.fetchall())


def get_console_actions(handoff_id: str) -> list[dict[str, Any]]:
    query = """
        select id::text, actor_role, action, target_type, target_id::text, trace_id, details, created_at::text
        from audit.console_action_logs
        where target_type = 'handoff' and target_id = %s::uuid
        order by created_at asc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (handoff_id,))
            return list(cur.fetchall())


def _audit_action(
    cur: Any,
    tenant_id: str | None,
    actor_role: str,
    action: str,
    target_type: str,
    target_id: str,
    trace_id: str,
    details: dict[str, Any],
) -> None:
    cur.execute(
        """
        insert into audit.console_action_logs(
            tenant_id, actor_role, action, target_type, target_id, trace_id, details
        )
        values (%s::uuid, %s, %s, %s, %s::uuid, %s, %s::jsonb)
        """,
        (tenant_id, actor_role, action, target_type, target_id, trace_id, json.dumps(details, ensure_ascii=False)),
    )


def claim_handoff(handoff_id: str, trace_id: str, actor_role: str = "support_agent") -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    update support.handoff_queue
                    set status = 'assigned', assigned_at = now()
                    where id = %s::uuid and status = 'pending'
                    returning id::text, conversation_id::text, tenant_id::text
                    """,
                    (handoff_id,),
                )
                handoff = cur.fetchone()
                if handoff is None:
                    return None
                cur.execute(
                    """
                    update support.conversations
                    set status = 'human_handling', updated_at = now()
                    where id = %s::uuid
                    """,
                    (handoff["conversation_id"],),
                )
                _audit_action(
                    cur,
                    handoff["tenant_id"],
                    actor_role,
                    "handoff_claimed",
                    "handoff",
                    handoff_id,
                    trace_id,
                    {"delivery_channel": "local_console"},
                )
    return get_console_handoff(handoff_id)


def add_human_reply(
    handoff_id: str,
    content: str,
    trace_id: str,
    actor_role: str,
) -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select id::text, conversation_id::text, tenant_id::text
                    from support.handoff_queue
                    where id = %s::uuid and status = 'assigned'
                    for update
                    """,
                    (handoff_id,),
                )
                handoff = cur.fetchone()
                if handoff is None:
                    return None
                cur.execute(
                    """
                    insert into support.messages(conversation_id, sender_type, content, metadata)
                    values (%s::uuid, 'human', %s, %s::jsonb)
                    returning id::text, sender_type, content, created_at::text, metadata
                    """,
                    (
                        handoff["conversation_id"],
                        content,
                        json.dumps({"delivery_channel": "simulated", "actor_role": actor_role}, ensure_ascii=False),
                    ),
                )
                message = cur.fetchone()
                cur.execute(
                    """
                    update support.conversations
                    set status = 'human_handling', updated_at = now()
                    where id = %s::uuid
                    """,
                    (handoff["conversation_id"],),
                )
                _audit_action(
                    cur,
                    handoff["tenant_id"],
                    actor_role,
                    "simulated_reply_sent",
                    "handoff",
                    handoff_id,
                    trace_id,
                    {"delivery_status": "simulated_sent", "content_length": len(content)},
                )
                return message


def create_handoff_ticket(
    handoff_id: str,
    subject: str,
    description: str,
    trace_id: str,
    actor_role: str,
) -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select id::text, conversation_id::text, customer_id::text, tenant_id::text, priority
                    from support.handoff_queue
                    where id = %s::uuid and status in ('pending', 'assigned')
                    for update
                    """,
                    (handoff_id,),
                )
                handoff = cur.fetchone()
                if handoff is None:
                    return None
                cur.execute(
                    """
                    insert into support.tickets(conversation_id, customer_id, type, priority, subject, description, metadata)
                    values (%s::uuid, %s::uuid, 'after_sales', %s, %s, %s, %s::jsonb)
                    returning id::text, type, status, priority, subject, description, created_at::text, updated_at::text
                    """,
                    (
                        handoff["conversation_id"],
                        handoff["customer_id"],
                        handoff["priority"],
                        subject,
                        description,
                        json.dumps({"source": "support_console", "handoff_id": handoff_id}, ensure_ascii=False),
                    ),
                )
                ticket = cur.fetchone()
                _audit_action(
                    cur,
                    handoff["tenant_id"],
                    actor_role,
                    "ticket_created",
                    "handoff",
                    handoff_id,
                    trace_id,
                    {"ticket_id": ticket["id"], "subject": subject},
                )
                return ticket


def resolve_console_handoff(handoff_id: str, trace_id: str, actor_role: str = "support_agent") -> bool:
    with connection() as conn:
        if conn is None:
            return False
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    update support.handoff_queue
                    set status = 'resolved', resolved_at = now()
                    where id = %s::uuid and status = 'assigned'
                    returning conversation_id::text, tenant_id::text
                    """,
                    (handoff_id,),
                )
                handoff = cur.fetchone()
                if handoff is None:
                    return False
                cur.execute(
                    """
                    update support.conversations
                    set status = 'closed', updated_at = now()
                    where id = %s::uuid
                    """,
                    (handoff["conversation_id"],),
                )
                _audit_action(
                    cur,
                    handoff["tenant_id"],
                    actor_role,
                    "handoff_resolved",
                    "handoff",
                    handoff_id,
                    trace_id,
                    {"resolution_channel": "local_console"},
                )
                return True
