"""FastAPI routes for the locally simulated customer-support workbench."""

from __future__ import annotations

import uuid
from typing import Any, Literal

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, Field

from console_repository import (
    add_human_reply,
    claim_handoff,
    create_handoff_ticket,
    get_console_actions,
    get_console_handoff,
    get_handoff_messages,
    get_handoff_tickets,
    list_console_handoffs,
    resolve_console_handoff,
)


router = APIRouter(prefix="/api/console", tags=["support-console"])


class ConsoleReplyRequest(BaseModel):
    content: str = Field(min_length=1, max_length=4000)
    role: Literal["support_agent", "support_lead"] = "support_agent"


class CreateTicketRequest(BaseModel):
    subject: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=4000)
    role: Literal["support_agent", "support_lead"] = "support_agent"


def _trace_from_header(trace_id: str | None) -> str:
    return trace_id or f"trace-{uuid.uuid4()}"


def _valid_handoff_id(handoff_id: str) -> str:
    try:
        return str(uuid.UUID(handoff_id))
    except ValueError as error:
        raise HTTPException(status_code=404, detail="handoff_not_found") from error


def _handoff_or_404(handoff_id: str) -> dict[str, Any]:
    handoff = get_console_handoff(_valid_handoff_id(handoff_id))
    if handoff is None:
        raise HTTPException(status_code=404, detail="handoff_not_found")
    return handoff


@router.get("/queue")
def console_queue(
    status: Literal["pending", "assigned", "resolved"] = "pending",
    limit: int = Query(default=30, ge=1, le=100),
) -> dict[str, Any]:
    return {"items": list_console_handoffs(status, limit)}


@router.get("/handoffs/{handoff_id}")
def console_handoff_detail(handoff_id: str) -> dict[str, Any]:
    normalized_id = _valid_handoff_id(handoff_id)
    handoff = _handoff_or_404(normalized_id)
    return {
        "handoff": handoff,
        "messages": get_handoff_messages(normalized_id),
        "tickets": get_handoff_tickets(normalized_id),
        "audit_actions": get_console_actions(normalized_id),
    }


@router.post("/handoffs/{handoff_id}/claim")
def console_claim_handoff(
    handoff_id: str,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _valid_handoff_id(handoff_id)
    handoff = claim_handoff(normalized_id, _trace_from_header(x_trace_id))
    if handoff is None:
        raise HTTPException(status_code=409, detail="handoff_not_pending")
    return {"handoff": handoff}


@router.post("/handoffs/{handoff_id}/reply")
def console_reply_to_handoff(
    handoff_id: str,
    payload: ConsoleReplyRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _valid_handoff_id(handoff_id)
    message = add_human_reply(
        normalized_id,
        payload.content.strip(),
        _trace_from_header(x_trace_id),
        payload.role,
    )
    if message is None:
        raise HTTPException(status_code=409, detail="handoff_not_assigned")
    return {"message": message, "delivery_status": "simulated_sent"}


@router.post("/handoffs/{handoff_id}/ticket")
def console_create_ticket(
    handoff_id: str,
    payload: CreateTicketRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _valid_handoff_id(handoff_id)
    ticket = create_handoff_ticket(
        normalized_id,
        payload.subject.strip(),
        payload.description.strip(),
        _trace_from_header(x_trace_id),
        payload.role,
    )
    if ticket is None:
        raise HTTPException(status_code=409, detail="handoff_not_active")
    return {"ticket": ticket}


@router.post("/handoffs/{handoff_id}/resolve")
def console_resolve_handoff(
    handoff_id: str,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _valid_handoff_id(handoff_id)
    resolved = resolve_console_handoff(normalized_id, _trace_from_header(x_trace_id))
    if not resolved:
        raise HTTPException(status_code=409, detail="handoff_not_assigned")
    return {"handoff_id": normalized_id, "resolved": True}
