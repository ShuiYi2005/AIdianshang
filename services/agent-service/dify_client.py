"""Small, typed boundary for Dify's Chat API."""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from typing import Any

import httpx


class DifyClientError(RuntimeError):
    """Base error raised by the Dify integration boundary."""


class DifyNotConfiguredError(DifyClientError):
    """Raised when a caller tries to use Dify without an app API key."""


class DifyTransportError(DifyClientError):
    """Raised for Dify timeouts and non-success HTTP responses."""


class DifyStructuredResponseError(DifyClientError):
    """Raised when Dify does not return the agreed final JSON object."""


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class DifyClientConfig:
    enabled: bool
    api_url: str
    api_key: str
    timeout_seconds: float = 15.0

    @property
    def configured(self) -> bool:
        return self.enabled and bool(self.api_url.strip()) and bool(self.api_key.strip())

    @classmethod
    def from_environment(cls) -> "DifyClientConfig":
        return cls(
            enabled=_as_bool(os.getenv("DIFY_APP_ENABLED")),
            api_url=os.getenv("DIFY_APP_API_URL", "http://dify-api:5001/v1/chat-messages"),
            api_key=os.getenv("DIFY_APP_API_KEY", ""),
            timeout_seconds=float(os.getenv("DIFY_APP_TIMEOUT_SECONDS", "15")),
        )


@dataclass(frozen=True)
class DifyChatResult:
    reply: str
    handoff_required: bool
    handoff_reason: str
    used_tool: bool
    used_knowledge: bool
    conversation_id: str | None
    message_id: str | None
    metadata: dict[str, Any]
    latency_ms: int


class DifyChatClient:
    """Calls Dify using a server-side application key and strict output parsing."""

    def __init__(self, config: DifyClientConfig, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self._config = config
        self._transport = transport

    async def chat(self, query: str, user: str, inputs: dict[str, Any]) -> DifyChatResult:
        if not self._config.configured:
            raise DifyNotConfiguredError("Dify application integration is not configured")

        started = time.perf_counter()
        body = {
            "inputs": inputs,
            "query": query,
            "response_mode": "blocking",
            "user": user,
            "files": [],
        }
        headers = {"Authorization": f"Bearer {self._config.api_key}", "Content-Type": "application/json"}

        try:
            async with httpx.AsyncClient(timeout=self._config.timeout_seconds, transport=self._transport) as client:
                response = await client.post(self._config.api_url, headers=headers, json=body)
                response.raise_for_status()
                payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise DifyTransportError("Dify Chat API request failed") from exc

        if not isinstance(payload, dict):
            raise DifyStructuredResponseError("Dify response must be an object")

        answer = payload.get("answer")
        structured = self._parse_answer(answer)
        latency_ms = int((time.perf_counter() - started) * 1000)
        metadata = payload.get("metadata")

        return DifyChatResult(
            reply=structured["reply"],
            handoff_required=structured["handoff_required"],
            handoff_reason=structured["handoff_reason"],
            used_tool=structured["used_tool"] or structured["used_knowledge"],
            used_knowledge=structured["used_knowledge"],
            conversation_id=payload.get("conversation_id") if isinstance(payload.get("conversation_id"), str) else None,
            message_id=payload.get("message_id") if isinstance(payload.get("message_id"), str) else None,
            metadata=metadata if isinstance(metadata, dict) else {},
            latency_ms=latency_ms,
        )

    @staticmethod
    def _parse_answer(answer: Any) -> dict[str, Any]:
        if not isinstance(answer, str):
            raise DifyStructuredResponseError("Dify answer must be a JSON string")

        normalized = answer.strip()
        if normalized.startswith("```") and normalized.endswith("```"):
            normalized = normalized.split("\n", 1)[1].rsplit("\n", 1)[0].strip()

        try:
            parsed = json.loads(normalized)
        except json.JSONDecodeError as exc:
            raise DifyStructuredResponseError("Dify answer is not valid JSON") from exc

        if not isinstance(parsed, dict):
            raise DifyStructuredResponseError("Dify answer JSON must be an object")

        reply = parsed.get("reply")
        if not isinstance(reply, str) or not reply.strip():
            raise DifyStructuredResponseError("Dify answer is missing a non-empty reply")

        required_bools = ("handoff_required", "used_tool", "used_knowledge")
        if any(not isinstance(parsed.get(field), bool) for field in required_bools):
            raise DifyStructuredResponseError("Dify answer has invalid boolean fields")

        handoff_reason = parsed.get("handoff_reason", "")
        if not isinstance(handoff_reason, str):
            raise DifyStructuredResponseError("Dify answer has an invalid handoff reason")

        return {
            "reply": reply.strip(),
            "handoff_required": parsed["handoff_required"],
            "handoff_reason": handoff_reason.strip(),
            "used_tool": parsed["used_tool"],
            "used_knowledge": parsed["used_knowledge"],
        }
