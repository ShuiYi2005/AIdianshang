# 数据架构

## 当前分层

项目现在按平台数据、业务数据、向量数据、缓存数据、文件数据、审计数据分层。

- Dify PostgreSQL：Dify 平台自身数据，Compose 服务名 `db`。
- Business PostgreSQL：业务主库，Compose 服务名 `business-db`，本机端口 `5433`。
- Weaviate：Dify 知识库向量数据。
- Redis：缓存、短期状态、限流状态和 Celery broker。
- `dify/storage`：Dify 文件与运行存储。
- `services/db-simulator/mock_data.py`：Demo 兼容兜底数据。

## 业务主库

业务主库使用 PostgreSQL 16，初始化脚本位于：

```text
deployment/business-db/init/01_schema.sql
```

Schema 分域如下：

- `core`：用户、客户等基础主体。
- `commerce`：商品、订单、物流。
- `recruitment`：简历、岗位、投递关系。
- `support`：客服会话、消息、工单。
- `ops`：上传任务、异步任务、草稿等临时/中间状态。
- `audit`：操作日志、审批记录、状态变更、AI 和工具调用日志。
- `knowledge`：知识文档、版本、切片和同步任务。
- `memory`：长期记忆和 AI 上下文快照。

## 服务读取关系

`db-simulator` 现在优先通过 `BUSINESS_DATABASE_URL` 读取 `business-db` 中的商品、订单、物流数据；如果未配置连接串或没有命中记录，则回退到本地 mock 数据，保证旧 Demo 用例仍可运行。

## 记忆与上下文

长期记忆保存到 `memory.long_term_memories` 和 `support.conversation_summaries`；短期记忆放 Redis，必须设置 TTL。每次 AI 回复时使用的最近消息、长期记忆、RAG 召回、Tool 结果和策略规则会保存到 `memory.context_snapshots`，并关联到会话和消息。

## RAG 与数据库边界

| 数据 | 推荐位置 | 是否适合 RAG |
|---|---|---|
| 商品价格、库存 | 业务主库 / 电商 API | 否 |
| 商品说明、尺码建议 | 知识库 / 向量库 | 是 |
| 订单状态 | 业务主库 / 电商 API | 否 |
| 物流轨迹 | 业务主库 / 物流 API | 否 |
| 售后规则 | 知识库 / 向量库 | 是 |
| 客服话术 | Prompt / 知识库 | 是 |
| 简历原文 | 对象存储 + 向量库 | 是 |
| 简历结构化字段 | 业务主库 | 否 |
| 岗位要求 | 业务主库 + 向量库 | 可两边 |
| 审批记录 | 审计表 | 否 |
| 状态变更记录 | 审计表 | 否 |

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File tests/database/verify_business_schema.ps1
powershell -ExecutionPolicy Bypass -File tests/services/verify_db_simulator_business_db.ps1
powershell -ExecutionPolicy Bypass -File tests/database/verify_ai_customer_service_schema.ps1
```
