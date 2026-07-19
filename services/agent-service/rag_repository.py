# -*- coding: utf-8 -*-
"""Auditable PostgreSQL metadata persistence for local knowledge files."""

from __future__ import annotations

import json
from typing import Any

from repository import connection


class RagRepository:
    def start_sync_job(self) -> str:
        with connection() as conn:
            if conn is None:
                return "local-sync"
            with conn.cursor() as cur:
                cur.execute("insert into knowledge.sync_jobs(source, target, status, started_at) values ('knowledge', 'weaviate', 'running', now()) returning id::text")
                return cur.fetchone()[0]

    def complete_sync_job(self, job_id: str, result: dict[str, object]) -> None:
        with connection() as conn:
            if conn is not None:
                with conn.cursor() as cur:
                    cur.execute("update knowledge.sync_jobs set status = 'succeeded', result = %s::jsonb, finished_at = now() where id = %s::uuid", (json.dumps(result, ensure_ascii=False), job_id))

    def fail_sync_job(self, job_id: str, message: str) -> None:
        with connection() as conn:
            if conn is not None:
                with conn.cursor() as cur:
                    cur.execute("update knowledge.sync_jobs set status = 'failed', error_message = %s, finished_at = now() where id = %s::uuid", (message[:500], job_id))

    def upsert_document_version(self, source_uri: str, title: str, content_hash: str) -> dict[str, object]:
        with connection() as conn:
            if conn is None:
                return {"document_version_id": f"local-{content_hash[:12]}", "changed": True, "expired_version_ids": []}
            with conn.cursor() as cur:
                cur.execute("select id::text, current_version from knowledge.documents where source_uri = %s", (source_uri,))
                document = cur.fetchone()
                if document is None:
                    cur.execute("insert into knowledge.documents(source_uri, title, document_type, owner_domain, status) values (%s, %s, 'faq', 'customer_service', 'published') returning id::text", (source_uri, title))
                    document_id, version_no = cur.fetchone()[0], 1
                    cur.execute("insert into knowledge.document_versions(document_id, version_no, content_hash, status, published_at) values (%s::uuid, %s, %s, 'published', now()) returning id::text", (document_id, version_no, content_hash))
                    return {"document_version_id": cur.fetchone()[0], "changed": True, "expired_version_ids": []}
                document_id, current_version = document
                cur.execute("select id::text, content_hash from knowledge.document_versions where document_id = %s::uuid and version_no = %s", (document_id, current_version))
                current_id, current_hash = cur.fetchone()
                if current_hash == content_hash:
                    return {"document_version_id": current_id, "changed": False, "expired_version_ids": []}
                next_version = current_version + 1
                cur.execute("update knowledge.document_versions set status = 'archived' where id = %s::uuid", (current_id,))
                cur.execute("update knowledge.documents set current_version = %s, updated_at = now() where id = %s::uuid", (next_version, document_id))
                cur.execute("insert into knowledge.document_versions(document_id, version_no, content_hash, status, published_at) values (%s::uuid, %s, %s, 'published', now()) returning id::text", (document_id, next_version, content_hash))
                return {"document_version_id": cur.fetchone()[0], "changed": True, "expired_version_ids": [current_id]}

    def replace_chunks(self, document_version_id: str, chunks: list[Any]) -> None:
        with connection() as conn:
            if conn is None:
                return
            with conn.cursor() as cur:
                cur.execute("delete from knowledge.document_chunks where document_version_id = %s::uuid", (document_version_id,))
                for index, chunk in enumerate(chunks, start=1):
                    cur.execute("insert into knowledge.document_chunks(document_version_id, chunk_no, content, content_hash, embedding_ref, token_count) values (%s::uuid, %s, %s, %s, %s, %s)", (document_version_id, index, chunk.content, chunk.content_hash, chunk.object_id, len(chunk.content.split())))

    def latest_sync_status(self) -> dict[str, object] | None:
        with connection() as conn:
            if conn is None:
                return None
            with conn.cursor() as cur:
                cur.execute("select id::text, status, result, error_message, finished_at from knowledge.sync_jobs order by created_at desc limit 1")
                row = cur.fetchone()
                if row is None:
                    return None
                return {"id": row[0], "status": row[1], "result": row[2], "error_message": row[3], "finished_at": row[4].isoformat() if row[4] else None}

    def counts(self) -> dict[str, int]:
        with connection() as conn:
            if conn is None:
                return {"document_count": 0, "chunk_count": 0}
            with conn.cursor() as cur:
                cur.execute("select (select count(*) from knowledge.documents where status = 'published'), (select count(*) from knowledge.document_chunks)")
                row = cur.fetchone()
                return {"document_count": int(row[0]), "chunk_count": int(row[1])}
