# 当前项目状态

> 本页以 `main` 分支上的业务代码、Compose 配置和可执行验证脚本为事实源。设计稿、实施计划和发布快照仅用于追溯，不能替代本页。

## 已实现并可在本地验证

- Docker Compose 启动 Dify、n8n、Business PostgreSQL、Redis、Weaviate、`db-simulator`、`agent-service` 和 React 客服运营台。
- 运营台提供模拟渠道的人工接管、人工回复、工单、训练主题、素材、预览、发布和回滚。
- 本地 RAG 使用 `BAAI/bge-small-zh-v1.5` 生成 512 维向量；`knowledge/` 内的 `.md` / `.txt` 可由 `POST /api/rag/reindex` 手动同步到 Business PostgreSQL 与 Weaviate。
- 默认 `DIFY_APP_ENABLED=false`。未发布 Dify Chatflow、未配置模型供应商或 App Key 时，`agent-service` 走本地策略、训练主题、RAG 与转人工降级链路。
- 真实电商后台尚未接入；订单查询和人工发送均为可审计的模拟渠道闭环。

## 当前限制（代码现状）

- `RAG_AUTO_INDEX` 已进入环境配置，但当前服务启动时不会自动发起索引；需要在训练中心点击“立即同步”或调用重建接口。
- `/api/rag/status` 当前固定返回 `weaviate_status=unknown`，尚未实际探测 Weaviate 连通性。
- `/api/rag/reindex` 尚未接入真实身份认证或运营权限校验；本地演示环境不应将 `agent-service:8010` 暴露给不受信任网络。
- RAG 同步的并发锁、风险/订单查询与 RAG 的执行顺序是已识别但尚未修复的工程缺口；在修复合并前，不应将该实现表述为生产级权限与索引调度。

## 运行与验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

`scripts/verify.ps1` 是当前完整本地验收入口；它不等同于真实电商、真实模型提供商或生产环境验收。

## 文档边界

- [README](../README.md)：启动入口与用户可见能力。
- [配置说明](CONFIGURATION.md)：环境变量、Dify 与 RAG 的实际运行边界。
- [架构说明](ARCHITECTURE.md)：当前实现与行业目标架构的分界。
- `docs/superpowers/specs/` 与 `docs/superpowers/plans/`：历史设计、计划与验收证据。
- `releases/`：历史离线发布快照；目录名不代表当前 `main` 已重新打包。
