# -*- coding: utf-8 -*-
"""Local RBAC and masking policy helpers."""

from __future__ import annotations


ROLE_PERMISSIONS: dict[str, set[str]] = {
    "customer": set(),
    "support_agent": {"orders.read"},
    "support_lead": {"orders.read", "audit.read"},
    "recruiter": {"resumes.read"},
    "refund_specialist": {"orders.read", "refunds.handle"},
    "admin": {"orders.read", "resumes.read", "refunds.handle", "audit.read", "pii.read_full"},
}

RESOURCE_FIELDS = {
    "order": ["order_id", "status", "logistics_no", "phone", "shipping_address"],
    "resume": ["candidate_name", "phone", "email", "content"],
    "message": ["sender_type", "content"],
    "audit": ["event_type", "trace_id", "details"],
}

MASKED_FIELDS = {
    "order": ["phone", "shipping_address"],
    "resume": ["phone", "email", "content"],
    "message": ["content"],
    "api_response": ["payload"],
}


def permissions_for(role: str, explicit_permissions: list[str] | None = None) -> set[str]:
    permissions = set(ROLE_PERMISSIONS.get(role, set()))
    if explicit_permissions:
        permissions.update(explicit_permissions)
    return permissions


def can_read(resource: str, permissions: set[str]) -> bool:
    if resource == "order":
        return "orders.read" in permissions or "pii.read_full" in permissions
    if resource == "resume":
        return "resumes.read" in permissions
    if resource == "audit":
        return "audit.read" in permissions
    if resource == "message":
        return True
    return False


def access_preview(role: str, resource: str, explicit_permissions: list[str] | None = None) -> dict:
    permissions = permissions_for(role, explicit_permissions)
    visible_fields = RESOURCE_FIELDS.get(resource, [])
    masked_fields = [] if "pii.read_full" in permissions else MASKED_FIELDS.get(resource, [])
    return {
        "role": role,
        "resource": resource,
        "permissions": sorted(permissions),
        "can_read": can_read(resource, permissions),
        "visible_fields": visible_fields,
        "masked_fields": masked_fields,
        "full_pii_allowed": "pii.read_full" in permissions,
    }
