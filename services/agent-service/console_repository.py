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


def list_training_topics(include_archived: bool = False) -> list[dict[str, Any]]:
    query = """
        select id::text, tenant_id::text, name, trigger_phrases, reply_text, store_scope, product_scope,
               channel, status, current_version, metadata, created_at::text, updated_at::text
        from knowledge.training_topics
    """
    if not include_archived:
        query += " where status <> 'archived'"
    query += " order by updated_at desc"
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query)
            return list(cur.fetchall())


def get_training_topic(topic_id: str) -> dict[str, Any] | None:
    query = """
        select id::text, tenant_id::text, name, trigger_phrases, reply_text, store_scope, product_scope,
               channel, status, current_version, metadata, created_at::text, updated_at::text
        from knowledge.training_topics
        where id = %s::uuid
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (topic_id,))
            return cur.fetchone()


def create_training_topic(payload: dict[str, Any], trace_id: str) -> dict[str, Any] | None:
    query = """
        insert into knowledge.training_topics(
            name, trigger_phrases, reply_text, store_scope, product_scope, channel
        )
        values (%s, %s, %s, %s, %s, %s)
        returning id::text, tenant_id::text, name, trigger_phrases, reply_text, store_scope, product_scope,
                  channel, status, current_version, metadata, created_at::text, updated_at::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    query,
                    (
                        payload["name"],
                        payload["trigger_phrases"],
                        payload["reply_text"],
                        payload["store_scope"],
                        payload["product_scope"],
                        payload["channel"],
                    ),
                )
                topic = cur.fetchone()
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_topic_created",
                    "training_topic",
                    topic["id"],
                    trace_id,
                    {"name": topic["name"]},
                )
                return topic


def update_training_topic(topic_id: str, payload: dict[str, Any], trace_id: str) -> dict[str, Any] | None:
    allowed_columns = {"name", "trigger_phrases", "reply_text", "store_scope", "product_scope", "channel"}
    updates = {key: value for key, value in payload.items() if key in allowed_columns}
    if not updates:
        return get_training_topic(topic_id)
    assignments = [f"{column} = %s" for column in updates]
    assignments.extend(["status = 'draft'", "updated_at = now()"])
    query = f"""
        update knowledge.training_topics
        set {', '.join(assignments)}
        where id = %s::uuid and status <> 'archived'
        returning id::text, tenant_id::text, name, trigger_phrases, reply_text, store_scope, product_scope,
                  channel, status, current_version, metadata, created_at::text, updated_at::text
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(query, (*updates.values(), topic_id))
                topic = cur.fetchone()
                if topic is None:
                    return None
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_topic_updated",
                    "training_topic",
                    topic_id,
                    trace_id,
                    {"fields": sorted(updates)},
                )
                return topic


def archive_training_topic(topic_id: str, trace_id: str) -> bool:
    with connection() as conn:
        if conn is None:
            return False
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    update knowledge.training_topics
                    set status = 'archived', updated_at = now()
                    where id = %s::uuid and status <> 'archived'
                    returning tenant_id::text
                    """,
                    (topic_id,),
                )
                topic = cur.fetchone()
                if topic is None:
                    return False
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_topic_archived",
                    "training_topic",
                    topic_id,
                    trace_id,
                    {},
                )
                return True


def list_training_assets(topic_id: str) -> list[dict[str, Any]]:
    query = """
        select id::text, topic_id::text, asset_type, filename, mime_type, byte_size, storage_path, description,
               created_at::text
        from knowledge.training_assets
        where topic_id = %s::uuid
        order by created_at asc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (topic_id,))
            return list(cur.fetchall())


def create_training_asset(
    topic_id: str,
    asset_type: str,
    filename: str,
    mime_type: str,
    byte_size: int,
    storage_path: str,
    description: str,
    trace_id: str,
) -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select tenant_id::text
                    from knowledge.training_topics
                    where id = %s::uuid and status <> 'archived'
                    for update
                    """,
                    (topic_id,),
                )
                topic = cur.fetchone()
                if topic is None:
                    return None
                cur.execute(
                    """
                    insert into knowledge.training_assets(
                        topic_id, asset_type, filename, mime_type, byte_size, storage_path, description
                    )
                    values (%s::uuid, %s, %s, %s, %s, %s, %s)
                    returning id::text, topic_id::text, asset_type, filename, mime_type, byte_size, storage_path,
                              description, created_at::text
                    """,
                    (topic_id, asset_type, filename, mime_type, byte_size, storage_path, description),
                )
                asset = cur.fetchone()
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_asset_uploaded",
                    "training_topic",
                    topic_id,
                    trace_id,
                    {"asset_id": asset["id"], "asset_type": asset_type, "byte_size": byte_size},
                )
                return asset


def list_training_versions(topic_id: str) -> list[dict[str, Any]]:
    query = """
        select id::text, topic_id::text, version, status, snapshot, published_at::text, rolled_back_at::text,
               created_at::text
        from knowledge.training_versions
        where topic_id = %s::uuid
        order by version asc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (topic_id,))
            return list(cur.fetchall())


def list_published_training_versions() -> list[dict[str, Any]]:
    """Return active immutable training snapshots for local reply matching."""
    query = """
        select t.id::text as topic_id, v.version, v.snapshot
        from knowledge.training_topics t
        join knowledge.training_versions v on v.topic_id = t.id
        where t.status <> 'archived' and v.status = 'published'
        order by v.published_at desc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query)
            return list(cur.fetchall())


def get_training_actions(topic_id: str) -> list[dict[str, Any]]:
    query = """
        select id::text, actor_role, action, target_type, target_id::text, trace_id, details, created_at::text
        from audit.console_action_logs
        where target_type = 'training_topic' and target_id = %s::uuid
        order by created_at asc
    """
    with connection() as conn:
        if conn is None:
            return []
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (topic_id,))
            return list(cur.fetchall())


def _training_snapshot(cur: Any, topic: dict[str, Any]) -> dict[str, Any]:
    cur.execute(
        """
        select id::text, asset_type, filename, mime_type, byte_size, storage_path, description, created_at::text
        from knowledge.training_assets
        where topic_id = %s::uuid
        order by created_at asc
        """,
        (topic["id"],),
    )
    assets = list(cur.fetchall())
    return {
        "topic": {
            "name": topic["name"],
            "trigger_phrases": topic["trigger_phrases"],
            "reply_text": topic["reply_text"],
            "store_scope": topic["store_scope"],
            "product_scope": topic["product_scope"],
            "channel": topic["channel"],
        },
        "assets": assets,
    }


def publish_training_topic(topic_id: str, trace_id: str) -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select id::text, tenant_id::text, name, trigger_phrases, reply_text, store_scope, product_scope,
                           channel, status, current_version
                    from knowledge.training_topics
                    where id = %s::uuid and status <> 'archived'
                    for update
                    """,
                    (topic_id,),
                )
                topic = cur.fetchone()
                if topic is None:
                    return None
                next_version = topic["current_version"] + 1
                if topic["current_version"] > 0:
                    cur.execute(
                        """
                        update knowledge.training_versions
                        set status = 'superseded'
                        where topic_id = %s::uuid and version = %s and status = 'published'
                        """,
                        (topic_id, topic["current_version"]),
                    )
                snapshot = _training_snapshot(cur, topic)
                cur.execute(
                    """
                    insert into knowledge.training_versions(topic_id, version, status, snapshot)
                    values (%s::uuid, %s, 'published', %s::jsonb)
                    """,
                    (topic_id, next_version, json.dumps(snapshot, ensure_ascii=False)),
                )
                cur.execute(
                    """
                    update knowledge.training_topics
                    set status = 'published', current_version = %s, updated_at = now()
                    where id = %s::uuid
                    """,
                    (next_version, topic_id),
                )
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_topic_published",
                    "training_topic",
                    topic_id,
                    trace_id,
                    {"version": next_version},
                )
    return get_training_topic(topic_id)


def rollback_training_topic(topic_id: str, version: int, trace_id: str) -> dict[str, Any] | None:
    with connection() as conn:
        if conn is None:
            return None
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select id::text, tenant_id::text, current_version
                    from knowledge.training_topics
                    where id = %s::uuid and status <> 'archived'
                    for update
                    """,
                    (topic_id,),
                )
                topic = cur.fetchone()
                if topic is None:
                    return None
                cur.execute(
                    """
                    select snapshot
                    from knowledge.training_versions
                    where topic_id = %s::uuid and version = %s
                    """,
                    (topic_id, version),
                )
                source = cur.fetchone()
                if source is None:
                    return None
                snapshot = source["snapshot"]
                if not isinstance(snapshot, dict) or not isinstance(snapshot.get("topic"), dict):
                    raise ValueError("invalid_training_version_snapshot")
                source_topic = snapshot["topic"]
                next_version = topic["current_version"] + 1
                if topic["current_version"] > 0:
                    cur.execute(
                        """
                        update knowledge.training_versions
                        set status = 'rolled_back', rolled_back_at = now()
                        where topic_id = %s::uuid and version = %s and status = 'published'
                        """,
                        (topic_id, topic["current_version"]),
                    )
                restored_snapshot = {**snapshot, "restored_from_version": version}
                cur.execute(
                    """
                    insert into knowledge.training_versions(topic_id, version, status, snapshot)
                    values (%s::uuid, %s, 'published', %s::jsonb)
                    """,
                    (topic_id, next_version, json.dumps(restored_snapshot, ensure_ascii=False)),
                )
                cur.execute(
                    """
                    update knowledge.training_topics
                    set name = %s,
                        trigger_phrases = %s,
                        reply_text = %s,
                        store_scope = %s,
                        product_scope = %s,
                        channel = %s,
                        status = 'published',
                        current_version = %s,
                        updated_at = now()
                    where id = %s::uuid
                    """,
                    (
                        source_topic["name"],
                        source_topic["trigger_phrases"],
                        source_topic["reply_text"],
                        source_topic["store_scope"],
                        source_topic["product_scope"],
                        source_topic["channel"],
                        next_version,
                        topic_id,
                    ),
                )
                _audit_action(
                    cur,
                    topic["tenant_id"],
                    "support_agent",
                    "training_topic_rolled_back",
                    "training_topic",
                    topic_id,
                    trace_id,
                    {"restored_from_version": version, "new_version": next_version},
                )
    return get_training_topic(topic_id)
