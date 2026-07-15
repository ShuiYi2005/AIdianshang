# 系统架构

## 当前定位

项目当前是 AI 客服技术 MVP，已经具备本地可运行的 Dify、n8n、业务库、Redis、Weaviate、模拟 Tool 服务。下一阶段目标是演进为标准的 AI 客服平台架构。

## 目标架构

```mermaid
flowchart TD
  Channel["外部渠道: 店铺/IM/网页/CRM"] --> Gateway["API 管理层"]
  Gateway --> Workflow["Workflow 引擎: n8n"]
  Console["React 客服运营台"] --> Agent
  Workflow --> Agent["Agent 服务层"]
  Agent --> Dify["Dify/模型编排"]
  Agent --> Rag["RAG 系统"]
  Agent --> Tools["Tool 服务"]
  Tools --> Adapters["CRM/电商适配器"]
  Adapters --> External["外部平台 API"]
  Tools --> BusinessDb["业务 PostgreSQL"]
  Agent --> Redis["Redis 短期记忆/缓存"]
  Agent --> Audit["审计与评测"]
  Rag --> VectorDb["Weaviate 向量库"]
  Rag --> Knowledge["knowledge 版本库"]
```

## 目录边界

- `services/`：业务服务和 Tool 服务。当前包含 `db-simulator`、`agent-service` 和独立部署的 React `support-console`；后续增加 `api-gateway`、`crm-adapter`、`commerce-adapter`。
- `adapters/`：外部平台适配器，负责把店铺/CRM 的字段转换成内部统一模型。
- `workflows/`：n8n 工作流导出与说明。
- `prompts/`：Prompt 工程资产。
- `knowledge/`：知识库原始资料。
- `specs/`：Agent、Tool、Workflow、API、Adapter、RAG、Monitoring 的机器可读规格。
- `deployment/`：Docker Compose 和部署配置。
- `docs/`：架构、运维、安全、数据治理文档。

## 数据边界

- Dify PostgreSQL：只保存 Dify 平台自身数据。
- Business PostgreSQL：保存业务事实、客服会话、memory、context、审计和知识版本元数据。
- Redis：保存短期记忆、缓存、限流状态、任务中间状态。
- Weaviate：保存 RAG 向量数据。
- n8n 存储：保存 workflow 和执行数据，正式环境建议切换 PostgreSQL。

## 服务边界

- Workflow 只编排，不沉淀复杂业务逻辑。
- Agent 服务层负责编排模型、记忆、上下文、RAG、Tool、策略与审计；`agent-service` 还提供客服工作台的领取、模拟发送、工单、解决和训练主题/素材/版本接口。`support-console` 只呈现与调用这些受控接口，浏览器 CORS 仅允许本地控制台来源。
- Tool 服务提供 AI 可调用的受控能力。
- Adapter 层负责平台差异，不让平台字段污染核心业务模型。
- API 管理层统一鉴权、限流、幂等、日志、版本和错误码。
