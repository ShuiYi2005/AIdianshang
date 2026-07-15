# -*- coding: utf-8 -*-
"""Business data access for the simulator service."""

from __future__ import annotations

import os
from contextlib import contextmanager
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


DATABASE_URL = os.getenv("BUSINESS_DATABASE_URL")

pool: ConnectionPool | None = None
if DATABASE_URL:
    pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=5, open=False)


@contextmanager
def connection():
    if pool is None:
        yield None
        return

    pool.open(wait=True)
    with pool.connection() as conn:
        yield conn


def normalize(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    return value


def fetch_product(sku_id: str) -> dict[str, Any] | None:
    query = """
        select sku_id, name, category, price, stock, status, description
        from commerce.products
        where sku_id = %s
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (sku_id,))
            row = cur.fetchone()
        return normalize(row) if row else None


def fetch_order(order_id: str) -> dict[str, Any] | None:
    query = """
        select
            o.order_id,
            o.status,
            o.total_amount,
            coalesce(i.product_name, '') as product_name,
            coalesce(i.quantity, 0) as quantity,
            o.ordered_at as created_at,
            o.shipping_address_masked as shipping_address,
            o.recipient_name as recipient,
            o.phone_masked as phone,
            coalesce(o.logistics_company, '') as logistics_company,
            coalesce(o.logistics_no, '') as logistics_no,
            o.refund_status,
            o.cancel_reason
        from commerce.orders o
        left join lateral (
            select product_name, quantity
            from commerce.order_items
            where order_id = o.id
            order by created_at asc
            limit 1
        ) i on true
        where o.order_id = %s
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (order_id,))
            row = cur.fetchone()
        return normalize(row) if row else None


def fetch_logistics(tracking_no: str) -> dict[str, Any] | None:
    query = """
        select
            l.id,
            l.company,
            l.tracking_no,
            o.order_id,
            l.status,
            l.estimated_delivery
        from commerce.logistics l
        left join commerce.orders o on o.id = l.order_id
        where l.tracking_no = %s
    """
    trace_query = """
        select event_time as time, location, description
        from commerce.logistics_traces
        where logistics_id = %s
        order by event_time asc
    """
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (tracking_no,))
            row = cur.fetchone()
        if not row:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(trace_query, (row["id"],))
            traces = cur.fetchall()
        data = dict(row)
        data.pop("id", None)
        data["trace"] = traces
        return normalize(data)


def fetch_order_by_logistics(logistics_no: str) -> dict[str, Any] | None:
    query = "select order_id from commerce.orders where logistics_no = %s"
    with connection() as conn:
        if conn is None:
            return None
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(query, (logistics_no,))
            row = cur.fetchone()
        if not row:
            return None
    return fetch_order(row["order_id"])
