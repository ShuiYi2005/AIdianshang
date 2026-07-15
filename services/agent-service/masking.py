# -*- coding: utf-8 -*-
"""Role-aware masking helpers for agent responses."""

from __future__ import annotations


def mask_phone(value: str | None) -> str:
    if not value:
        return ""
    digits = "".join(ch for ch in value if ch.isdigit())
    if len(digits) < 7:
        return "***"
    return f"{digits[:3]}****{digits[-4:]}"


def mask_address(value: str | None) -> str:
    if not value:
        return ""
    text = value.strip()
    if len(text) <= 8:
        return "***"
    return f"{text[:6]}***{text[-3:]}"


def mask_order(order: dict) -> dict:
    masked = dict(order)
    masked["phone"] = mask_phone(masked.get("phone"))
    masked["shipping_address"] = mask_address(masked.get("shipping_address"))
    return masked
