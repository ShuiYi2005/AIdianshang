# 当前项目状态

> 本页以 `main` 分支上的业务代码、Compose 配置和可执行验证脚本为事实源。设计稿、实施计划和发布快照仅用于追溯，不能替代本页。

## 已实现并可在本地验证

- Docker Compose 启动 Dify、n8n、Business PostgreSQL、Redis、Weaviate、`db-simulator`、`agent-service` 和 React 客服运营台。
- 运营台提供模拟渠道的人工接管、人工回复、工单、训练主题、素材、预览、发布和回滚。
- 本地 RAG 使用 `BAAI/bge-small-zh-v1.5` 生成 512 维向量；`RAG_AUTO_INDEX=true` 时会在服务启动后异步同步 `knowledge/` 内的 `.md` / `.txt` 到 Business PostgreSQL 与 Weaviate，训练中心或 `POST /api/rag/reindex` 可手动触发增量同步。
- 受版本控制的默认配置为 `DIFY_APP_ENABLED=false`。未发布 Dify Chatflow、未配置模型供应商或 App Key 时，`agent-service` 走本地策略、训练主题、RAG 与转人工降级链路；被 Git 忽略的本机环境文件可以按需覆盖该默认值。
- 真实电商后台尚未接入；订单查询和人工发送均为可审计的模拟渠道闭环。

## 当前限制（代码现状）

- `/api/rag/reindex` 尚未接入真实身份认证或运营权限校验；本地演示环境不应将 `agent-service:8010` 暴露给不受信任网络。
- 启动自动索引依赖 Weaviate Docker 健康检查；若索引运行后依赖短暂不可用，任务会记录失败状态，训练中心仍可手动重试。
- `tests/deployment/verify_github_clone_readiness.ps1` 当前对前端 Dockerfile 的静态断言存在待排查失败；该脚本未修改前，不应把“GitHub 新克隆验收全绿”表述为当前事实。

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
