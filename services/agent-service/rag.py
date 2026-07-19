# -*- coding: utf-8 -*-
"""Small local RAG helper used for offline verification."""

from __future__ import annotations

import re
from pathlib import Path


KNOWLEDGE_ROOT = Path(__file__).resolve().parent / "knowledge"
if not KNOWLEDGE_ROOT.exists():
    KNOWLEDGE_ROOT = Path("/app/knowledge")


PHONE_RE = re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")
ID_CARD_RE = re.compile(r"(?<!\d)\d{17}[\dXx](?![\dXx])")
ORDER_ID_RE = re.compile(r"\bORD-[A-Z0-9]+\b", flags=re.IGNORECASE)
ADDRESS_RE = re.compile(r"(?:省|市|自治区).{0,24}(?:区|县|路|街|号)")


def split_document(content: str, chunk_size: int = 800, overlap: int = 120) -> list[str]:
    """Split text deterministically while retaining useful boundary context."""
    if chunk_size <= 0 or overlap < 0 or overlap >= chunk_size:
        raise ValueError("chunk_size must be positive and overlap must be smaller than chunk_size")

    normalized = content.strip()
    if not normalized:
        return []
    if len(normalized) <= chunk_size:
        return [normalized]

    chunks: list[str] = []
    start = 0
    while start < len(normalized):
        chunk = normalized[start : start + chunk_size]
        chunks.append(chunk)
        if start + chunk_size >= len(normalized):
            break
        start += chunk_size - overlap
    return chunks


def contains_restricted_pii(content: str) -> bool:
    """Block obvious customer identifiers from the local vector corpus."""
    return bool(
        PHONE_RE.search(content)
        or ID_CARD_RE.search(content)
        or ORDER_ID_RE.search(content)
        or ADDRESS_RE.search(content)
    )


def _tokens(text: str) -> set[str]:
    normalized = "".join(ch.lower() if ch.isalnum() else " " for ch in text)
    return {part for part in normalized.split() if len(part) >= 2}


def _score(query: str, content: str) -> int:
    query_tokens = _tokens(query)
    content_tokens = _tokens(content)
    score = len(query_tokens.intersection(content_tokens))
    lowered_content = content.lower()
    for token in query_tokens:
        if token in lowered_content:
            score += 2
    return score


def search_knowledge(query: str, limit: int = 3) -> list[dict]:
    query_tokens = _tokens(query)
    if not query_tokens:
        return []

    results: list[dict] = []
    if not KNOWLEDGE_ROOT.exists():
        return results

    for path in KNOWLEDGE_ROOT.rglob("*"):
        if path.suffix.lower() not in {".md", ".txt"} or not path.is_file():
            continue
        content = path.read_text(encoding="utf-8", errors="ignore")
        score = _score(query, content)
        if score <= 0:
            continue
        excerpt = " ".join(content.replace("\r", " ").replace("\n", " ").split())[:240]
        results.append(
            {
                "source_uri": str(path.relative_to(KNOWLEDGE_ROOT)).replace("\\", "/"),
                "title": path.stem,
                "score": score,
                "excerpt": excerpt,
                "retrieval_mode": "keyword",
            }
        )

    return sorted(results, key=lambda item: item["score"], reverse=True)[:limit]
