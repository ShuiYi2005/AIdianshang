# -*- coding: utf-8 -*-
"""Small adapter layer for CPU embeddings and a self-vectorized Weaviate class."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

import httpx

from rag_types import RagSettings


VECTOR_DIMENSION = 512
CLASS_NAME = "KnowledgeChunk"


def validate_vector_dimensions(vectors: list[list[float]]) -> None:
    if any(len(vector) != VECTOR_DIMENSION for vector in vectors):
        raise ValueError(f"expected {VECTOR_DIMENSION}-dimension vectors")


@dataclass(frozen=True)
class VectorChunk:
    object_id: str
    document_version_id: str
    chunk_id: str
    source_uri: str
    title: str
    content: str
    vector: list[float]


class FastEmbedder:
    def __init__(self, settings: RagSettings) -> None:
        from fastembed import TextEmbedding

        self._model = TextEmbedding(model_name=settings.model_name, cache_dir=settings.cache_path)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        vectors = [item.tolist() for item in self._model.passage_embed(texts)]
        validate_vector_dimensions(vectors)
        return vectors

    def embed_query(self, query: str) -> list[float]:
        vector = next(self._model.query_embed(query)).tolist()
        validate_vector_dimensions([vector])
        return vector


class LazyFastEmbedder:
    """Avoid model imports and downloads until indexing or retrieval is requested."""

    def __init__(self, settings: RagSettings) -> None:
        self._settings = settings
        self._delegate: FastEmbedder | None = None

    def _load(self) -> FastEmbedder:
        if self._delegate is None:
            self._delegate = FastEmbedder(self._settings)
        return self._delegate

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return self._load().embed_documents(texts)

    def embed_query(self, query: str) -> list[float]:
        return self._load().embed_query(query)


class WeaviateKnowledgeStore:
    def __init__(self, base_url: str, timeout_seconds: float = 10.0) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = httpx.Client(timeout=timeout_seconds)

    def ensure_schema(self) -> None:
        response = self._client.get(f"{self._base_url}/v1/schema/{CLASS_NAME}")
        if response.status_code == 200:
            return
        if response.status_code != 404:
            response.raise_for_status()
        response = self._client.post(
            f"{self._base_url}/v1/schema",
            json={
                "class": CLASS_NAME,
                "vectorizer": "none",
                "properties": [
                    {"name": "sourceUri", "dataType": ["text"]},
                    {"name": "title", "dataType": ["text"]},
                    {"name": "content", "dataType": ["text"]},
                    {"name": "documentVersionId", "dataType": ["text"]},
                    {"name": "chunkId", "dataType": ["text"]},
                ],
            },
        )
        response.raise_for_status()

    def health(self) -> str:
        try:
            response = self._client.get(f"{self._base_url}/v1/.well-known/ready")
            return "ready" if response.status_code == 200 else "unavailable"
        except httpx.HTTPError:
            return "unavailable"

    def upsert_chunks(self, chunks: list[VectorChunk]) -> None:
        validate_vector_dimensions([chunk.vector for chunk in chunks])
        if not chunks:
            return
        response = self._client.post(
            f"{self._base_url}/v1/batch/objects",
            json={
                "objects": [
                    {
                        "class": CLASS_NAME,
                        "id": chunk.object_id,
                        "vector": chunk.vector,
                        "properties": {
                            "sourceUri": chunk.source_uri,
                            "title": chunk.title,
                            "content": chunk.content,
                            "documentVersionId": chunk.document_version_id,
                            "chunkId": chunk.chunk_id,
                        },
                    }
                    for chunk in chunks
                ]
            },
        )
        response.raise_for_status()
        failed = [item for item in response.json() if item.get("result", {}).get("errors")]
        if failed:
            raise RuntimeError("weaviate batch write failed")

    def search(self, vector: list[float], limit: int) -> list[dict[str, Any]]:
        validate_vector_dimensions([vector])
        query = """{ Get { KnowledgeChunk(nearVector: { vector: %s }, limit: %d) { sourceUri title content documentVersionId chunkId _additional { distance } } } }""" % (vector, limit)
        response = self._client.post(f"{self._base_url}/v1/graphql", json={"query": query})
        response.raise_for_status()
        items = response.json().get("data", {}).get("Get", {}).get(CLASS_NAME, [])
        return [
            {
                "source_uri": item["sourceUri"],
                "title": item["title"],
                "content": item["content"],
                "document_version_id": item["documentVersionId"],
                "chunk_id": item["chunkId"],
                "distance": item.get("_additional", {}).get("distance"),
            }
            for item in items
        ]

    def delete_document_versions(self, version_ids: set[str]) -> None:
        for version_id in version_ids:
            response = self._client.post(
                f"{self._base_url}/v1/batch/objects/delete",
                json={"match": {"class": CLASS_NAME, "where": {"path": ["documentVersionId"], "operator": "Equal", "valueText": version_id}}},
            )
            response.raise_for_status()


def stable_object_id(document_version_id: str, chunk_id: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"ai20-rag:{document_version_id}:{chunk_id}"))
