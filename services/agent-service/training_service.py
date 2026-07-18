from __future__ import annotations

from pathlib import Path
from typing import Any

SENSITIVE_TERMS = (
    "退款",
    "退钱",
    "赔偿",
    "投诉",
    "身份核验",
    "refund",
    "compensation",
    "complaint",
    "identity verification",
)
ALLOWED_EXTENSIONS = {".txt", ".md", ".png", ".jpg", ".jpeg", ".webp", ".mp4"}
MAX_ASSET_BYTES = 16 * 1024 * 1024

_ALLOWED_MIME_TYPES = {
    ".txt": {"text/plain"},
    ".md": {"text/markdown", "text/plain"},
    ".png": {"image/png"},
    ".jpg": {"image/jpeg"},
    ".jpeg": {"image/jpeg"},
    ".webp": {"image/webp"},
    ".mp4": {"video/mp4"},
}


def validate_asset(filename: str, content_type: str, content_length: int) -> str | None:
    """Return a stable validation code for an upload, or None when it is allowed."""
    extension = Path(filename).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        return "unsupported_file_type"
    if content_length < 0:
        return "invalid_file_size"
    if content_length > MAX_ASSET_BYTES:
        return "asset_too_large"
    if content_type.lower() not in _ALLOWED_MIME_TYPES[extension]:
        return "unsupported_content_type"
    return None


def asset_type_for_filename(filename: str) -> str:
    """Map a validated asset extension to the durable training asset category."""
    extension = Path(filename).suffix.lower()
    if extension in {".txt", ".md"}:
        return "text"
    if extension in {".png", ".jpg", ".jpeg", ".webp"}:
        return "image"
    if extension == ".mp4":
        return "video"
    raise ValueError("unsupported_file_type")


def preview_training(topic: dict[str, object], query: str) -> dict[str, object]:
    """Preview a topic without bypassing the global handoff safety policy."""
    normalized_query = query.casefold()
    if any(term in normalized_query for term in SENSITIVE_TERMS):
        return {
            "matched": False,
            "handoff_required": True,
            "reply": "该请求需要人工客服核验后处理。",
        }

    phrases = topic.get("trigger_phrases", [])
    normalized_phrases = (
        [str(item).casefold() for item in phrases]
        if isinstance(phrases, list)
        else []
    )
    matched = any(phrase and phrase in normalized_query for phrase in normalized_phrases)
    return {
        "matched": matched,
        "handoff_required": False,
        "reply": str(topic.get("reply_text", "")) if matched else "未命中训练主题。",
    }


def next_publish_state(status: str) -> str:
    """Return the version state created when a topic is published or restored."""
    transitions = {
        "draft": "published",
        "published": "superseded",
        "rolled_back": "published",
    }
    try:
        return transitions[status]
    except KeyError as error:
        raise ValueError(f"unsupported_publish_state:{status}") from error
