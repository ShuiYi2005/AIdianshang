# -*- coding: utf-8 -*-
"""State transition rules for productization verification."""

from __future__ import annotations


TRANSITIONS: dict[str, dict[str, set[str]]] = {
    "conversation": {
        "new": {"ai_handling", "human_handling", "closed"},
        "ai_handling": {"human_handling", "closed"},
        "human_handling": {"closed", "ai_handling"},
        "closed": set(),
    },
    "handoff": {
        "pending": {"assigned", "cancelled"},
        "assigned": {"resolved", "cancelled"},
        "resolved": set(),
        "cancelled": set(),
    },
    "evaluation": {
        "queued": {"running", "cancelled"},
        "running": {"succeeded", "failed", "cancelled"},
        "succeeded": set(),
        "failed": {"queued"},
        "cancelled": set(),
    },
    "rollout": {
        "draft": {"active"},
        "active": {"paused", "completed", "rolled_back"},
        "paused": {"active", "rolled_back"},
        "completed": set(),
        "rolled_back": set(),
    },
}


def transition_preview(entity_type: str, from_status: str, to_status: str) -> dict:
    allowed_targets = TRANSITIONS.get(entity_type, {}).get(from_status, set())
    return {
        "entity_type": entity_type,
        "from_status": from_status,
        "to_status": to_status,
        "allowed": to_status in allowed_targets,
        "allowed_targets": sorted(allowed_targets),
    }
