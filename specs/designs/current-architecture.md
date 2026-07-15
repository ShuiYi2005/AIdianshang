# Current Architecture

## 目标

保持当前 AI 智能客服系统可运行，并按开发体系隔离平台、业务、部署和规格。

## 组件

- Dify Web/API/Worker: AI 应用平台，当前镜像版本为 `1.14.2`。
- PostgreSQL: Dify 元数据存储。
- Redis: 缓存与 Celery broker。
- Weaviate: 向量库。
- n8n: 后续工作流编排预留。
- db-simulator: 订单、商品、物流模拟数据服务。

## 运行入口

```powershell
docker compose -f deployment/docker-compose.yml up -d
```

## 约束

- 不修改 Dify、n8n 平台源码。
- 当前业务代码只在 `services/db-simulator/`。
- 部署配置只在 `deployment/`。
