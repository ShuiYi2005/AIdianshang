# -*- coding: utf-8 -*-
"""Shared contracts for the local knowledge-retrieval boundary."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Literal, Mapping


RagMode = Literal["hybrid", "vector", "keyword"]
SUPPORTED_MODEL = "BAAI/bge-small-zh-v1.5"


def _as_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError("RAG_AUTO_INDEX must be a boolean value")


@dataclass(frozen=True)
class RagSettings:
    mode: RagMode = "hybrid"
    model_name: str = SUPPORTED_MODEL
    cache_path: str = "/models"
    weaviate_url: str = "http://weaviate:8080"
    auto_index: bool = True

    @classmethod
    def from_environment(cls, env: Mapping[str, str] | None = None) -> "RagSettings":
        values = os.environ if env is None else env
        mode = values.get("RAG_MODE", "hybrid").strip().lower()
        if mode not in {"hybrid", "vector", "keyword"}:
            raise ValueError("RAG_MODE must be hybrid, vector, or keyword")

        model_name = values.get("RAG_EMBEDDING_MODEL", SUPPORTED_MODEL).strip()
        if model_name != SUPPORTED_MODEL:
            raise ValueError(f"RAG_EMBEDDING_MODEL must be {SUPPORTED_MODEL}")

        return cls(
            mode=mode,  # type: ignore[arg-type]
            model_name=model_name,
            cache_path=values.get("RAG_MODEL_CACHE_PATH", "/models").strip() or "/models",
            weaviate_url=values.get("WEAVIATE_URL", "http://weaviate:8080").rstrip("/"),
            auto_index=_as_bool(values.get("RAG_AUTO_INDEX", "true")),
        )


@dataclass(frozen=True)
class RagSearchResult:
    source_uri: str
    title: str
    excerpt: str
    retrieval_mode: str
    score: float | int | None = None
    document_version_id: str | None = None
    chunk_id: str | None = None
    distance: float | None = None
    fallback_reason: str | None = None

    def as_dict(self) -> dict[str, object]:
        value: dict[str, object] = {
            "source_uri": self.source_uri,
            "title": self.title,
            "excerpt": self.excerpt,
            "retrieval_mode": self.retrieval_mode,
        }
        for key, item in {
            "score": self.score,
            "document_version_id": self.document_version_id,
            "chunk_id": self.chunk_id,
            "distance": self.distance,
            "fallback_reason": self.fallback_reason,
        }.items():
            if item is not None:
                value[key] = item
        return value
