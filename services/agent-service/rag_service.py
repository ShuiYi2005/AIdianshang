# -*- coding: utf-8 -*-
"""Orchestration of local knowledge indexing and retrieval modes."""

from __future__ import annotations

import hashlib
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from rag import KNOWLEDGE_ROOT, contains_restricted_pii, search_knowledge, split_document
from rag_types import RagSettings
from rag_vector import VectorChunk, stable_object_id


class RagDependencyError(RuntimeError):
    pass


@dataclass(frozen=True)
class IndexedChunk:
    object_id: str
    document_version_id: str
    chunk_id: str
    source_uri: str
    title: str
    content: str
    content_hash: str
    vector: list[float]


@dataclass(frozen=True)
class RagIndexStatus:
    status: str
    sync_job_id: str
    document_count: int
    chunk_count: int


@dataclass(frozen=True)
class RagSearchResponse:
    results: list[dict[str, object]]
    retrieval_mode: str
    fallback_reason: str | None = None
    index_status: str = "ready"

    def as_dict(self) -> dict[str, object]:
        return {"results": self.results, "retrieval_mode": self.retrieval_mode, "fallback_reason": self.fallback_reason, "index_status": self.index_status}


class RagService:
    def __init__(self, settings: RagSettings, embedder: Any, store: Any, repository: Any, knowledge_root: Path | None = None, keyword_search: Callable[[str, int], list[dict[str, object]]] = search_knowledge) -> None:
        self.settings, self.embedder, self.store, self.repository = settings, embedder, store, repository
        self.knowledge_root = knowledge_root or KNOWLEDGE_ROOT
        self.keyword_search = keyword_search
        self._lock = threading.Lock()
        self._running_job_id: str | None = None

    def reindex(self) -> RagIndexStatus:
        if not self._lock.acquire(blocking=False):
            return RagIndexStatus("running", self._running_job_id or "unknown", 0, 0)
        job_id: str | None = None
        try:
            job_id = self.repository.start_sync_job()
            self._running_job_id = job_id
            self.store.ensure_schema()
            indexed: list[IndexedChunk] = []
            expired_ids: set[str] = set()
            documents = 0
            for path in sorted(self.knowledge_root.rglob("*")):
                if not path.is_file() or path.suffix.lower() not in {".md", ".txt"}:
                    continue
                content = path.read_text(encoding="utf-8", errors="ignore").strip()
                if not content:
                    continue
                if contains_restricted_pii(content):
                    raise ValueError(f"restricted_pii:{path.name}")
                source_uri = str(path.relative_to(self.knowledge_root)).replace("\\", "/")
                version = self.repository.upsert_document_version(source_uri, path.stem, hashlib.sha256(content.encode("utf-8")).hexdigest())
                expired_ids.update(version["expired_version_ids"])
                if not version["changed"]:
                    documents += 1
                    continue
                chunks = split_document(content)
                vectors = self.embedder.embed_documents(chunks)
                if len(chunks) != len(vectors):
                    raise RagDependencyError("embedding_count_mismatch")
                file_chunks: list[IndexedChunk] = []
                for index, (chunk, vector) in enumerate(zip(chunks, vectors), start=1):
                    chunk_hash = hashlib.sha256(chunk.encode("utf-8")).hexdigest()
                    chunk_id = f"{version['document_version_id']}:{index}:{chunk_hash[:12]}"
                    file_chunks.append(IndexedChunk(stable_object_id(str(version["document_version_id"]), chunk_id), str(version["document_version_id"]), chunk_id, source_uri, path.stem, chunk, chunk_hash, vector))
                self.store.upsert_chunks([VectorChunk(chunk.object_id, chunk.document_version_id, chunk.chunk_id, chunk.source_uri, chunk.title, chunk.content, chunk.vector) for chunk in file_chunks])
                self.repository.replace_chunks(str(version["document_version_id"]), file_chunks)
                indexed.extend(file_chunks)
                documents += 1
            self.store.delete_document_versions(expired_ids)
            result = {"document_count": documents, "chunk_count": len(indexed)}
            self.repository.complete_sync_job(job_id, result)
            return RagIndexStatus("succeeded", job_id, documents, len(indexed))
        except Exception as exc:
            if job_id is not None:
                self.repository.fail_sync_job(job_id, str(exc))
            raise
        finally:
            self._running_job_id = None
            self._lock.release()

    def search(self, query: str, limit: int) -> RagSearchResponse:
        if not query.strip():
            return RagSearchResponse([], "keyword" if self.settings.mode == "keyword" else "vector")
        if limit < 1 or limit > 10:
            raise ValueError("limit must be between 1 and 10")
        if self.settings.mode == "keyword":
            return RagSearchResponse(self.keyword_search(query, limit), "keyword")
        try:
            vector = self.embedder.embed_query(query)
            items = self.store.search(vector, limit)
            return RagSearchResponse([{**item, "excerpt": str(item.get("content", ""))[:240], "retrieval_mode": "vector"} for item in items], "vector")
        except Exception as exc:
            if self.settings.mode == "vector":
                raise RagDependencyError(str(exc)) from exc
            reason = str(exc) or "vector_unavailable"
            return RagSearchResponse(self.keyword_search(query, limit), "keyword_fallback", reason, "degraded")

    def start_reindex(self) -> dict[str, object]:
        if self._running_job_id:
            return {"sync_job_id": self._running_job_id, "status": "running", "accepted": False}
        self._running_job_id = "starting"

        def run() -> None:
            try:
                self.reindex()
            finally:
                if self._running_job_id == "starting":
                    self._running_job_id = None

        threading.Thread(target=run, daemon=True, name="rag-reindex").start()
        return {"sync_job_id": "starting", "status": "running", "accepted": True}

    def status(self) -> dict[str, object]:
        counts = self.repository.counts()
        latest = self.repository.latest_sync_status()
        cache_path = Path(self.settings.cache_path)
        try:
            weaviate_status = self.store.health()
        except Exception:
            weaviate_status = "unavailable"
        return {"mode": self.settings.mode, "model_name": self.settings.model_name, "model_cache_status": "ready" if cache_path.exists() and any(cache_path.iterdir()) else "missing", "weaviate_status": weaviate_status, "index_status": "running" if self._running_job_id else (latest or {}).get("status", "idle"), "last_sync": latest, **counts}
