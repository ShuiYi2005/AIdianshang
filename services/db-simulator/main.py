# -*- coding: utf-8 -*-
"""模拟数据库查询服务 - FastAPI 应用"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mock_data import ORDERS, PRODUCTS, LOGISTICS
from repository import fetch_logistics, fetch_order, fetch_order_by_logistics, fetch_product

app = FastAPI(
    title="模拟数据库查询服务",
    description="模拟抖店订单、商品、物流数据查询接口，供 Dify 工具调用",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/order/{order_id}")
async def get_order(order_id: str):
    """查询订单信息"""
    order = fetch_order(order_id) or ORDERS.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"订单 {order_id} 不存在")
    return {"code": 0, "data": order}


@app.get("/api/product/{sku_id}")
async def get_product(sku_id: str):
    """查询商品/SKU 信息"""
    product = fetch_product(sku_id) or PRODUCTS.get(sku_id)
    if not product:
        raise HTTPException(status_code=404, detail=f"商品 {sku_id} 不存在")
    return {"code": 0, "data": product}


@app.get("/api/logistics/{tracking_no}")
async def get_logistics(tracking_no: str):
    """查询物流信息"""
    logistics = fetch_logistics(tracking_no) or LOGISTICS.get(tracking_no)
    if not logistics:
        raise HTTPException(status_code=404, detail=f"物流单 {tracking_no} 不存在")
    return {"code": 0, "data": logistics}


@app.get("/api/order/by-logistics/{logistics_no}")
async def get_order_by_logistics(logistics_no: str):
    """通过物流单号查询订单"""
    order = fetch_order_by_logistics(logistics_no)
    if order:
        return {"code": 0, "data": order}
    for order_id, order in ORDERS.items():
        if order.get("logistics_no") == logistics_no:
            return {"code": 0, "data": order}
    raise HTTPException(status_code=404, detail=f"未找到物流单 {logistics_no} 对应的订单")
