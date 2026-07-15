# -*- coding: utf-8 -*-
"""Small local RAG helper used for offline verification."""

from __future__ import annotations

from pathlib import Path


KNOWLEDGE_ROOT = Path(__file__).resolve().parent / "knowledge"
if not KNOWLEDGE_ROOT.exists():
    KNOWLEDGE_ROOT = Path("/app/knowledge")


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
            }
        )

    return sorted(results, key=lambda item: item["score"], reverse=True)[:limit]
