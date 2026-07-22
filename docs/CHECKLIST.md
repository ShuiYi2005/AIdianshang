# CHECKLIST

## 修改前

- 阅读 `.spec/README.md`、相关 `specs/` 与根 `AGENTS.md`。
- 确认业务代码只在 `services/`，工作流只做编排，平台源码不修改。

## 修改后

在 Docker Desktop 可用时，执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

该入口覆盖 Compose、业务库 Schema、Dify/n8n/模拟 Tool/`agent-service`/运营台 HTTP、训练中心、RAG、可观测性、评测和固定壳层 UI 合同。

## RAG 专项验收

- `GET /api/rag/status` 显示模型缓存、`weaviate_status`、索引状态和最近同步记录。
- 训练中心“知识库同步”可启动同步、显示进行中、成功或失败状态，并可重试。
- `POST /api/rag/search` 在索引成功后返回 `retrieval_mode=vector`、资料来源、版本与切片标识。
- Weaviate 或模型不可用时，`hybrid` 返回 `keyword_fallback`；`vector` 不伪装关键词结果。
