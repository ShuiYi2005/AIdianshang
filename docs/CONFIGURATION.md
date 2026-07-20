# CONFIGURATION

## 环境分层

项目按以下环境分层设计：

| 环境 | 用途 | 数据 | 密钥 |
|---|---|---|---|
| `local` | 本机开发和 Demo | 本地 Docker volume | `deployment/env/local.env` |
| `dev` | 团队联调 | 非真实数据 | CI/CD Secret 或 dev secret |
| `staging` | 上线前验收 | 脱敏或仿真数据 | Secret Manager |
| `prod` | 正式生产 | 真实数据 | Secret Manager / KMS |

## 配置来源优先级

从高到低：

1. 云 Secret / CI Secret / Docker Secret / Kubernetes Secret。
2. Shell 环境变量。
3. `deployment/env/<env>.env`。
4. `config/app.<env>.yaml`。
5. `config/app.example.yaml`。
6. 代码默认值。

原则：

- 密码、API Key、Secret 只允许来自 1-3 层。
- 业务规则优先来自 `config/` 或数据库。
- Compose 中只保留服务拓扑、端口、volume、健康检查等非敏感配置。

## 当前本地运行

本地运行使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

该命令是 GitHub 新克隆仓库的唯一推荐入口：当 `deployment/env/local.env` 不存在时会从模板生成随机本地密钥；已有环境文件绝不会被覆盖。它会在启动 API 与前端前完成业务数据库迁移。

仅用于已初始化环境的排障方式：

```powershell
docker compose -f deployment/docker-compose.yml up -d
```

直接 Compose 启动不会自动执行增量迁移；请优先使用 `scripts/start-local.ps1`。

## 环境变量分类

### 平台密钥

- `DIFY_SECRET_KEY`
- `DIFY_INIT_PASSWORD`
- `DIFY_INNER_API_KEY`
- `PLUGIN_SERVER_KEY`
- `N8N_ENCRYPTION_KEY`

### 数据库

- `POSTGRES_PASSWORD`
- `BUSINESS_DB_USER`
- `BUSINESS_DB_PASSWORD`
- `BUSINESS_DB_NAME`

### 缓存

- `REDIS_PASSWORD`

### 应用环境

- `APP_ENV`

## 校验

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile deployment/env/local.env
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```
# 本地向量 RAG

默认 `RAG_MODE=hybrid` 使用 `BAAI/bge-small-zh-v1.5` 的 ONNX CPU 嵌入模型；首次同步会下载约 90 MB 模型文件到 Docker 卷 `embedding_model_cache`，后续重启复用缓存。可通过 `GET /api/rag/status` 查看缓存与索引状态，通过 `POST /api/rag/reindex` 同步 `knowledge/` 下的文本资料。

- `RAG_MODE=hybrid`：优先向量检索，依赖不可用时返回明确的 `keyword_fallback`。
- `RAG_MODE=vector`：只接受向量检索，依赖故障返回受控错误。
- `RAG_MODE=keyword`：不加载模型，仅用于离线降级验证。

该模型是嵌入模型，不是聊天大模型；它负责语义召回，不能替代 Dify/其他聊天模型生成回复。

### 索引运行与当前限制

- `RAG_AUTO_INDEX=true` 时，`agent-service` 会在启动后异步调用一次同步；Compose 会等待 Weaviate 就绪后再启动该服务。知识文件后续变更可从训练中心点击“立即同步”，或调用 `POST /api/rag/reindex`。
- `GET /api/rag/status` 返回模型缓存、文档数、切片数、最近同步任务和实际探测得到的 `weaviate_status`（`ready` 或 `unavailable`）。
- `POST /api/rag/reindex` 当前没有真实认证边界，只适用于本机受信任演示环境；不要将 `8010` 端口直接暴露给不受信任网络。

## Dify 应用与模型提供商

本地默认 `DIFY_APP_ENABLED=false`。仓库保存 Chatflow 说明、提示词和工具契约，但不保存已发布的 Dify App、模型供应商凭据或 `DIFY_APP_API_KEY`。只有在目标环境完成模型供应商配置、发布 App 并通过环境变量注入 App Key 后，`agent-service` 才会调用 Dify；否则使用本地策略、训练主题、RAG 与转人工降级链路。
