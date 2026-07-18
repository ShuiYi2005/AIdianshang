"""Routes for safely managing local AI customer-service training topics."""

from __future__ import annotations

import os
import re
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter, File, Header, HTTPException, UploadFile
from pydantic import BaseModel, Field, field_validator

from console_repository import (
    archive_training_topic,
    create_training_asset,
    create_training_topic,
    get_training_actions,
    get_training_topic,
    list_training_assets,
    list_training_topics,
    list_training_versions,
    publish_training_topic,
    rollback_training_topic,
    update_training_topic,
)
from training_service import asset_type_for_filename, preview_training, validate_asset


router = APIRouter(prefix="/api/training", tags=["training-center"])
TRAINING_ASSET_ROOT = Path(os.getenv("TRAINING_ASSET_ROOT", "/app/training-assets"))


class TrainingTopicCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    trigger_phrases: list[str] = Field(min_length=1, max_length=30)
    reply_text: str = Field(min_length=1, max_length=8000)
    store_scope: str = Field(default="simulated-store", min_length=1, max_length=128)
    product_scope: str = Field(default="all-products", min_length=1, max_length=128)
    channel: str = Field(default="simulated-ecommerce", min_length=1, max_length=64)

    @field_validator("trigger_phrases")
    @classmethod
    def normalize_trigger_phrases(cls, values: list[str]) -> list[str]:
        normalized = [value.strip() for value in values if value.strip()]
        if not normalized:
            raise ValueError("trigger_phrases_must_not_be_empty")
        return normalized


class TrainingTopicUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    trigger_phrases: list[str] | None = Field(default=None, min_length=1, max_length=30)
    reply_text: str | None = Field(default=None, min_length=1, max_length=8000)
    store_scope: str | None = Field(default=None, min_length=1, max_length=128)
    product_scope: str | None = Field(default=None, min_length=1, max_length=128)
    channel: str | None = Field(default=None, min_length=1, max_length=64)

    @field_validator("trigger_phrases")
    @classmethod
    def normalize_optional_trigger_phrases(cls, values: list[str] | None) -> list[str] | None:
        if values is None:
            return None
        normalized = [value.strip() for value in values if value.strip()]
        if not normalized:
            raise ValueError("trigger_phrases_must_not_be_empty")
        return normalized


class PreviewRequest(BaseModel):
    query: str = Field(min_length=1, max_length=4000)


class RollbackRequest(BaseModel):
    version: int = Field(ge=1)


def _trace_from_header(trace_id: str | None) -> str:
    return trace_id or f"trace-{uuid.uuid4()}"


def _topic_id_or_404(topic_id: str) -> str:
    try:
        return str(uuid.UUID(topic_id))
    except ValueError as error:
        raise HTTPException(status_code=404, detail="training_topic_not_found") from error


def _topic_or_404(topic_id: str) -> dict[str, Any]:
    topic = get_training_topic(_topic_id_or_404(topic_id))
    if topic is None:
        raise HTTPException(status_code=404, detail="training_topic_not_found")
    return topic


def _safe_asset_filename(filename: str) -> str:
    if not filename or Path(filename).name != filename:
        raise HTTPException(status_code=400, detail="invalid_asset_filename")
    normalized = re.sub(r"[^A-Za-z0-9._-]", "_", filename)
    if not normalized or normalized in {".", ".."}:
        raise HTTPException(status_code=400, detail="invalid_asset_filename")
    return normalized


def store_training_asset(topic_id: str, filename: str, body: bytes) -> str:
    """Persist an already validated asset beneath the dedicated local volume."""
    safe_filename = _safe_asset_filename(filename)
    root = TRAINING_ASSET_ROOT.resolve()
    relative_path = Path(topic_id) / f"{uuid.uuid4().hex}_{safe_filename}"
    destination = (root / relative_path).resolve()
    try:
        destination.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid_asset_path") from error
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(body)
    return relative_path.as_posix()


@router.get("/topics")
def training_topics() -> dict[str, Any]:
    return {"items": list_training_topics()}


@router.post("/topics")
def create_topic(
    payload: TrainingTopicCreate,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    topic = create_training_topic(payload.model_dump(), _trace_from_header(x_trace_id))
    if topic is None:
        raise HTTPException(status_code=503, detail="training_store_unavailable")
    return topic


@router.get("/topics/{topic_id}")
def training_topic_detail(topic_id: str) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    topic = _topic_or_404(normalized_id)
    return {
        "topic": topic,
        "assets": list_training_assets(normalized_id),
        "versions": list_training_versions(normalized_id),
        "audit_actions": get_training_actions(normalized_id),
    }


@router.put("/topics/{topic_id}")
def update_topic(
    topic_id: str,
    payload: TrainingTopicUpdate,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    topic = update_training_topic(normalized_id, payload.model_dump(exclude_unset=True), _trace_from_header(x_trace_id))
    if topic is None:
        raise HTTPException(status_code=404, detail="training_topic_not_editable")
    return topic


@router.delete("/topics/{topic_id}")
def archive_topic(
    topic_id: str,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    archived = archive_training_topic(normalized_id, _trace_from_header(x_trace_id))
    if not archived:
        raise HTTPException(status_code=404, detail="training_topic_not_editable")
    return {"archived": True}


@router.post("/topics/{topic_id}/assets")
async def upload_training_asset(
    topic_id: str,
    file: UploadFile = File(...),
    description: str = "",
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    _topic_or_404(normalized_id)
    raw_filename = file.filename or ""
    body = await file.read(16 * 1024 * 1024 + 1)
    validation = validate_asset(raw_filename, file.content_type or "", len(body))
    if validation:
        raise HTTPException(status_code=400, detail=validation)
    stored_path = store_training_asset(normalized_id, raw_filename, body)
    asset = create_training_asset(
        normalized_id,
        asset_type_for_filename(raw_filename),
        _safe_asset_filename(raw_filename),
        file.content_type or "",
        len(body),
        stored_path,
        description.strip(),
        _trace_from_header(x_trace_id),
    )
    if asset is None:
        destination = (TRAINING_ASSET_ROOT.resolve() / stored_path).resolve()
        if destination.is_file():
            destination.unlink()
        raise HTTPException(status_code=404, detail="training_topic_not_editable")
    return asset


@router.post("/topics/{topic_id}/preview")
def preview_topic(topic_id: str, payload: PreviewRequest) -> dict[str, Any]:
    topic = _topic_or_404(topic_id)
    return preview_training(topic, payload.query)


@router.post("/topics/{topic_id}/publish")
def publish_topic(
    topic_id: str,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    topic = publish_training_topic(normalized_id, _trace_from_header(x_trace_id))
    if topic is None:
        raise HTTPException(status_code=404, detail="training_topic_not_publishable")
    return {"topic": topic}


@router.post("/topics/{topic_id}/rollback")
def rollback_topic(
    topic_id: str,
    payload: RollbackRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> dict[str, Any]:
    normalized_id = _topic_id_or_404(topic_id)
    topic = rollback_training_topic(normalized_id, payload.version, _trace_from_header(x_trace_id))
    if topic is None:
        raise HTTPException(status_code=404, detail="training_version_not_found")
    return {"topic": topic, "restored_from_version": payload.version}
