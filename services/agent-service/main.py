# -*- coding: utf-8 -*-
"""Production-oriented agent boundary service."""

from __future__ import annotations

import os
import re
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from dify_client import DifyChatClient, DifyClientConfig, DifyClientError
from masking import mask_address, mask_order, mask_phone
from rag_repository import RagRepository
from rag_service import RagDependencyError, RagService
from rag_types import RagSettings
from rag_vector import LazyFastEmbedder, WeaviateKnowledgeStore
from repository import (
    enqueue_handoff,
    ensure_conversation,
    ensure_customer,
    list_handoffs,
    resolve_handoff,
    save_ai_log,
    save_context_snapshot,
    save_cost_event,
    save_message,
    save_metric,
    save_tool_log,
)
from console_repository import list_published_training_versions
from security import access_preview
from state_machine import transition_preview
from console_api import router as console_router
from training_api import router as training_router
from training_service import SENSITIVE_TERMS, preview_training


DB_SIMULATOR_URL = os.getenv("DB_SIMULATOR_URL", "http://db-simulator:8000")
rag_settings = RagSettings.from_environment()
rag_service = RagService(
    rag_settings,
    LazyFastEmbedder(rag_settings),
    WeaviateKnowledgeStore(rag_settings.weaviate_url),
    RagRepository(),
)

@asynccontextmanager
async def lifespan(_: FastAPI):
    if rag_settings.auto_index:
        rag_service.start_reindex()
    yield


app = FastAPI(title="agent-service", version="0.2.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:4173"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "X-Trace-Id", "X-Idempotency-Key"],
)
app.include_router(console_router)
app.include_router(training_router)


class MaskingPreviewRequest(BaseModel):
    phone: str | None = None
    address: str | None = None
    role: str = "support_agent"


class AgentReplyRequest(BaseModel):
    conversation_id: str
    platform: str = "demo"
    customer_id: str
    user_message: str
    role: str = "support_agent"


class RagSearchRequest(BaseModel):
    query: str
    limit: int = 3


class AccessPreviewRequest(BaseModel):
    role: str = "support_agent"
    resource: str = "order"
    permissions: list[str] | None = None


class TransitionPreviewRequest(BaseModel):
    entity_type: str
    from_status: str
    to_status: str


def extract_order_id(message: str) -> str | None:
    match = re.search(r"\bORD-[A-Z0-9]+\b", message, flags=re.IGNORECASE)
    return match.group(0).upper() if match else None


def trace_from_header(trace_id: str | None) -> str:
    return trace_id or f"trace-{uuid.uuid4()}"


def should_handoff(message: str) -> bool:
    lowered = message.casefold()
    keywords = [*SENSITIVE_TERMS, "转人工", "human agent"]
    return any(keyword in lowered for keyword in keywords)


def published_training_match(message: str) -> dict[str, Any] | None:
    """Find the first active immutable training version matching a safe message."""
    for published_version in list_published_training_versions():
        snapshot = published_version.get("snapshot")
        topic = snapshot.get("topic") if isinstance(snapshot, dict) else None
        if not isinstance(topic, dict):
            continue
        preview = preview_training(topic, message)
        if preview["matched"]:
            return {
                "reply": str(preview["reply"]),
                "topic_id": published_version["topic_id"],
                "version": published_version["version"],
            }
    return None


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "agent-service"}


@app.get("/metrics")
async def metrics() -> dict[str, Any]:
    return {
        "service": "agent-service",
        "status": "ok",
        "metrics": [
            "agent.reply.count",
            "tool.latency_ms",
            "rag.search.count",
            "dify.latency_ms",
            "handoff.created.count",
            "cost.usage.events",
        ],
    }


@app.post("/api/masking/preview")
async def masking_preview(
    payload: MaskingPreviewRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    trace_id = trace_from_header(x_trace_id)
    return {
        "trace_id": trace_id,
        "data": {
            "phone": mask_phone(payload.phone),
            "address": mask_address(payload.address),
            "role": payload.role,
        },
    }


@app.post("/api/security/access-preview")
async def security_access_preview(payload: AccessPreviewRequest) -> dict[str, Any]:
    return {"data": access_preview(payload.role, payload.resource, payload.permissions)}


@app.post("/api/state/transition-preview")
async def state_transition_preview(payload: TransitionPreviewRequest) -> dict[str, Any]:
    return {"data": transition_preview(payload.entity_type, payload.from_status, payload.to_status)}


@app.post("/api/rag/search")
async def rag_search(
    payload: RagSearchRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    trace_id = trace_from_header(x_trace_id)
    try:
        result = rag_service.search(payload.query, payload.limit)
    except (RagDependencyError, ValueError) as exc:
        raise HTTPException(status_code=503, detail="向量检索暂不可用") from exc
    response = result.as_dict()
    results = response["results"]
    rag_tokens = sum(len(item.get("excerpt", "").split()) for item in results)
    save_metric("rag.search.count", 1, {"result_count": len(results)}, trace_id)
    save_cost_event(trace_id, "rag.search", rag_tokens=rag_tokens)
    return {"trace_id": trace_id, **response}


@app.get("/api/rag/status")
async def rag_status() -> dict[str, Any]:
    return rag_service.status()


@app.post("/api/rag/reindex", status_code=202)
async def rag_reindex() -> dict[str, Any]:
    return rag_service.start_reindex()


async def call_order_tool(order_id: str, trace_id: str) -> tuple[dict[str, Any], int, str]:
    started = time.perf_counter()
    status = "success"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{DB_SIMULATOR_URL}/api/order/{order_id}", headers={"X-Trace-Id": trace_id})
            response.raise_for_status()
            payload = response.json()
    except Exception as exc:
        status = "failed"
        payload = {"code": 1, "error": str(exc), "data": None}
    latency_ms = int((time.perf_counter() - started) * 1000)
    return payload, latency_ms, status


@app.post("/api/agent/reply")
async def agent_reply(
    payload: AgentReplyRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
    x_idempotency_key: str | None = Header(default=None, alias="X-Idempotency-Key"),
) -> dict[str, Any]:
    trace_id = trace_from_header(x_trace_id)
    customer_uuid = ensure_customer(payload.platform, payload.customer_id)
    conversation_uuid = ensure_conversation(payload.platform, payload.conversation_id, customer_uuid)
    order_id = extract_order_id(payload.user_message)
    message_requires_handoff = should_handoff(payload.user_message)
    dify_config = DifyClientConfig.from_environment()
    use_dify = dify_config.configured

    tool_context: dict[str, Any] = {}
    tool_calls: list[dict[str, Any]] = []
    retrieval_context: list[dict[str, Any]] = []
    content = "我已经收到你的问题，会继续为你处理。"
    handoff_required = False
    handoff_reason = ""
    model_provider = "dify" if use_dify else "local"
    model_name = "dify-chatflow" if use_dify else "agent-service-template"
    dify_conversation_id = None
    training_match = None if message_requires_handoff else published_training_match(payload.user_message)

    if not message_requires_handoff and order_id:
        tool_payload, latency_ms, status = await call_order_tool(order_id, trace_id)
        save_metric("tool.latency_ms", latency_ms, {"tool_name": "get_order", "status": status}, trace_id)
        save_tool_log(trace_id, "get_order", {"order_id": order_id}, tool_payload, status, latency_ms)
        tool_calls.append({"tool_name": "get_order", "status": status, "latency_ms": latency_ms})
        model_provider = "tool-orchestrator"
        model_name = "order-lookup"
        raw_order = tool_payload.get("data") if isinstance(tool_payload, dict) else None
        if status == "success" and raw_order:
            masked_order = mask_order(raw_order)
            tool_context["order"] = masked_order
            content = f"订单 {masked_order.get('order_id')} 当前状态为 {masked_order.get('status')}。"
            if masked_order.get("logistics_no"):
                content += f" 物流单号为 {masked_order.get('logistics_no')}。"
        else:
            handoff_required = True
            handoff_reason = "tool_failure"
            content = "订单信息暂时查询失败，我会为你转人工继续处理。"
    elif use_dify:
        if message_requires_handoff:
            handoff_required = True
            handoff_reason = "sensitive_case"
            content = "\u8fd9\u4e2a\u95ee\u9898\u9700\u8981\u4eba\u5de5\u5ba2\u670d\u5904\u7406\uff0c\u6211\u5df2\u4fdd\u7559\u5f53\u524d\u4e0a\u4e0b\u6587\u3002"
        elif training_match:
            content = training_match["reply"]
            model_provider = "local-training"
            model_name = "published-training-topic"
            tool_context["training"] = {
                "topic_id": training_match["topic_id"],
                "version": training_match["version"],
                "delivery": "local_training_match",
            }
        else:
            try:
                dify_result = await DifyChatClient(dify_config).chat(
                    query=payload.user_message,
                    user=conversation_uuid or f"conversation-{payload.conversation_id}",
                    inputs={
                        "platform": payload.platform,
                        "role": payload.role,
                        "trace_id": trace_id,
                        "conversation_id": conversation_uuid or "",
                    },
                )
                dify_conversation_id = dify_result.conversation_id
                tool_context["dify"] = {
                    "conversation_id": dify_conversation_id,
                    "message_id": dify_result.message_id,
                    "used_tool": dify_result.used_tool,
                    "used_knowledge": dify_result.used_knowledge,
                }
                save_metric("dify.latency_ms", dify_result.latency_ms, {"status": "success"}, trace_id)
                save_tool_log(
                    trace_id,
                    "dify_chatflow",
                    {"query_length": len(payload.user_message), "conversation_id": conversation_uuid},
                    {"used_tool": dify_result.used_tool, "used_knowledge": dify_result.used_knowledge},
                    "success",
                    dify_result.latency_ms,
                )
                tool_calls.append(
                    {
                        "tool_name": "dify_chatflow",
                        "status": "success",
                        "latency_ms": dify_result.latency_ms,
                        "used_tool": dify_result.used_tool,
                    }
                )
                content = dify_result.reply
                handoff_required = dify_result.handoff_required
                handoff_reason = dify_result.handoff_reason
            except DifyClientError:
                handoff_required = True
                handoff_reason = "dify_unavailable"
                content = "\u667a\u80fd\u5ba2\u670d\u6682\u65f6\u65e0\u6cd5\u5b8c\u6210\u5904\u7406\uff0c\u6211\u5df2\u4e3a\u4f60\u8f6c\u4eba\u5de5\u5ba2\u670d\u7ee7\u7eed\u5904\u7406\u3002"
                save_metric("dify.latency_ms", 0, {"status": "failed"}, trace_id)
                save_tool_log(
                    trace_id,
                    "dify_chatflow",
                    {"query_length": len(payload.user_message), "conversation_id": conversation_uuid},
                    {"error_code": "dify_unavailable"},
                    "failed",
                    0,
                )
                tool_calls.append({"tool_name": "dify_chatflow", "status": "failed", "latency_ms": 0})
    elif message_requires_handoff:
        handoff_required = True
        handoff_reason = "sensitive_case"
        content = "这个问题涉及投诉、退款或赔付，我会为你转人工处理，并保留当前上下文。"
    elif training_match:
        content = training_match["reply"]
        model_provider = "local-training"
        model_name = "published-training-topic"
        tool_context["training"] = {
            "topic_id": training_match["topic_id"],
            "version": training_match["version"],
            "delivery": "local_training_match",
        }
    else:
        retrieval_context = rag_service.search(payload.user_message, limit=2).results
        if retrieval_context:
            top = retrieval_context[0]
            content = f"我查到一条相关知识：{top.get('excerpt')} 来源：{top.get('source_uri')}。"

    policy_context = {
        "handoff_required": handoff_required,
        "handoff_reason": handoff_reason,
        "idempotency_key_present": bool(x_idempotency_key),
        "data_masking": "default_support_agent",
        "access": access_preview(payload.role, "order"),
    }
    prompt_context = {
        "system": "customer-service",
        "rules": ["NO_FABRICATION", "REALTIME_FACTS_FROM_TOOL"],
        "model_provider": model_provider,
        "model_name": model_name,
    }
    snapshot_id = save_context_snapshot(
        conversation_uuid,
        trace_id,
        payload.user_message,
        tool_context,
        policy_context,
        prompt_context,
        retrieval_context,
    )
    save_message(conversation_uuid, "customer", payload.user_message, snapshot_id)
    save_message(conversation_uuid, "ai", content, snapshot_id)

    handoff_id = None
    if handoff_required:
        handoff_id = enqueue_handoff(
            conversation_uuid,
            customer_uuid,
            handoff_reason or "agent_policy",
            "high" if handoff_reason == "sensitive_case" else "normal",
            snapshot_id,
            {"user_message": payload.user_message, "tool_calls": tool_calls},
        )
        save_metric("handoff.created.count", 1, {"reason": handoff_reason or "agent_policy"}, trace_id)

    rag_tokens = sum(len(item.get("excerpt", "").split()) for item in retrieval_context)
    save_ai_log(
        trace_id,
        conversation_uuid,
        tool_used=bool(tool_calls),
        rag_used=bool(retrieval_context),
        model_provider=model_provider,
        model_name=model_name,
        metadata={"dify_conversation_id": dify_conversation_id} if dify_conversation_id else {},
    )
    save_metric("agent.reply.count", 1, {"platform": payload.platform, "provider": model_provider}, trace_id)
    save_cost_event(
        trace_id,
        "agent.reply",
        prompt_tokens=len(payload.user_message.split()),
        completion_tokens=len(content.split()),
        rag_tokens=rag_tokens,
        tool_calls=len(tool_calls),
        provider=model_provider,
        model_name=model_name,
    )

    return {
        "trace_id": trace_id,
        "reply_type": "handoff" if handoff_required else "ai_reply",
        "content": content,
        "handoff_required": handoff_required,
        "handoff_id": handoff_id,
        "context_snapshot_id": snapshot_id,
        "tool_calls": tool_calls,
        "retrieval_context": retrieval_context,
        "data_masked": True,
        "model_provider": model_provider,
        "model_name": model_name,
        "dify_conversation_id": dify_conversation_id,
    }


@app.get("/api/workbench/handoffs")
async def workbench_handoffs(status: str = "pending", limit: int = 20) -> dict[str, Any]:
    return {"items": list_handoffs(status, limit)}


@app.post("/api/workbench/handoffs/{handoff_id}/resolve")
async def workbench_resolve_handoff(handoff_id: str) -> dict[str, Any]:
    return {"handoff_id": handoff_id, "resolved": resolve_handoff(handoff_id)}
