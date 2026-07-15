# AI 智能客服系统

本项目已经按通用开发体系整理为可本地运行、可验证、可逐步回滚的 Demo/MVP 基础工程。

## 启动

推荐使用显式本地环境文件：

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d
```

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

## 目录

- `docs/`：项目文档、开发规范、数据与安全设计。
- `docs/SECURITY.md`：密钥和敏感配置设计。
- `docs/DATA_ARCHITECTURE.md`：数据分层与 RAG 边界。
- `docs/DATABASE_SCHEMA.md`：业务数据库表结构说明。
- `docs/AI_CUSTOMER_SERVICE_DATA_GOVERNANCE.md`：AI 客服数据治理、memory 和 context 设计。
- `docs/PRODUCTION_READINESS_DESIGN.md`：权限、脱敏、保留、多租户、评测、监控、成本、同步、灰度和客服台设计。
- `.spec/`：编码代理规格入口。
- `specs/`：Agent、Tool、Schema、设计和流程规格。
- `services/`：业务服务代码。
- `deployment/`：Docker 部署配置。
- `dify-assets/`：Dify 应用、工具、数据集等资产导出占位。
- `knowledge/`：知识库原始资料。
- `prompts/`：系统提示词和策略提示词。
- `workflows/`：n8n 等自动化流程规格。

## 当前服务

- Dify Web：`http://localhost:8080`
- Dify API：`http://localhost:5001`
- n8n：`http://localhost:5678`
- db-simulator：`http://localhost:8001`
- agent-service：`http://localhost:8010`
- Business PostgreSQL：`localhost:5433`

## 产品化验证

```powershell
powershell -ExecutionPolicy Bypass -File tests/services/verify_agent_service.ps1 -EnvFile deployment/env/local.env
powershell -ExecutionPolicy Bypass -File tests/evaluation/verify_evaluation_runner.ps1
```
