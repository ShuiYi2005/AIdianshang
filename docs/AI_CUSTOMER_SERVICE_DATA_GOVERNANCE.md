# AI 客服数据治理、记忆与上下文设计

## 设计目标

AI 客服系统的数据层按“事实、知识、记忆、上下文、缓存、审计”分开管理，避免模型把实时事实、历史偏好、知识库规则和临时上下文混在一起。

核心原则：

- 实时事实以业务库或外部 API 为准。
- 可检索知识以知识库版本为准。
- 长期记忆只保存经过提炼的事实、偏好和风险标记。
- 短期记忆放 Redis，带 TTL，可丢失、可重建。
- 每次 AI 回复的上下文要可追溯，保存到 `memory.context_snapshots`。
- 外部事件和写操作必须幂等，避免重复 webhook、重复消息、重复任务。

## 数据分层

| 层 | 位置 | 典型数据 | 生命周期 |
|---|---|---|---|
| 事实数据 | `core`、`commerce`、`recruitment`、`support` | 用户、客户、商品、订单、物流、简历、岗位、工单 | 长期 |
| 临时任务 | `ops` | 上传任务、异步任务、草稿、幂等键、webhook 事件 | 短中期 |
| 缓存数据 | Redis | 页面缓存、工具结果缓存、短期会话状态 | 短期 TTL |
| 知识数据 | `knowledge` + Weaviate | FAQ、售后政策、商品说明、岗位 JD | 版本化长期 |
| 长期记忆 | `memory.long_term_memories`、`support.conversation_summaries` | 用户偏好、会话摘要、风险标记 | 长期可更新 |
| 上下文快照 | `memory.context_snapshots` | 单次回复使用的 prompt、RAG、tool、memory、policy context | 中长期审计 |
| 审计数据 | `audit` | 操作日志、状态变更、工具调用、AI 回复、安全事件 | 长期追加 |

## 数据更新

结构化数据更新走服务层，不让 Dify、n8n 或模型直接写库。服务层负责校验、权限、脱敏、状态流转、幂等和审计。

推荐模式：

```sql
insert into commerce.products (sku_id, name, price, stock, status)
values (...)
on conflict (sku_id) do update set
  name = excluded.name,
  price = excluded.price,
  stock = excluded.stock,
  status = excluded.status,
  updated_at = now();
```

状态更新必须同时记录：

- 主表当前状态。
- `audit.status_change_logs`。
- 必要时写 `audit.data_change_events`。

## 去重与幂等

| 场景 | 约束 |
|---|---|
| 客户 | `core.customers(platform, platform_customer_id)` |
| 商品 | `commerce.products.sku_id` |
| 订单 | `commerce.orders.order_id` |
| 物流 | `commerce.logistics.tracking_no` |
| 会话 | `support.conversations(platform, platform_conversation_id)` |
| 平台消息 | `support.messages(conversation_id, platform_message_id)` |
| Webhook | `ops.webhook_events(provider, event_id)` |
| 写操作幂等 | `ops.idempotency_keys(scope, idempotency_key)` |
| 知识文档 | `knowledge.documents.source_uri` |
| 知识版本 | `knowledge.document_versions(document_id, version_no)` |
| 长期记忆 | `memory.long_term_memories(memory_scope, scope_id, memory_key)` |

## 长期记忆

长期记忆分两类：

- 会话级摘要：`support.conversation_summaries`，用于快速恢复一段会话的历史背景。
- 主体级记忆：`memory.long_term_memories`，用于保存客户偏好、候选人偏好、风险标记等可复用信息。

长期记忆不能覆盖实时事实。例如用户曾经偏好“白色 T 恤”，不能用来回答当前库存；库存必须查商品库或电商 API。

## 短期记忆

短期记忆放 Redis，不作为事实来源。

推荐 key：

```text
memory:session:{conversation_id}
memory:tool_result:{trace_id}
memory:risk:{conversation_id}
memory:draft:{user_id}:{draft_type}
cache:rag:{query_hash}
cache:tool:{tool_name}:{request_hash}
```

要求：

- 必须设置 TTL。
- 可丢失、可重建。
- 不存明文敏感信息。
- 命中业务数据更新时，通过 `ops.cache_invalidation_jobs` 触发失效。

## Context 组装

一次 AI 回复的上下文按固定优先级组装：

1. System Prompt：角色、安全边界、禁止编造。
2. 当前用户消息。
3. 最近 N 轮消息。
4. 长期记忆摘要。
5. RAG 召回知识。
6. Tool 实时查询结果。
7. 风险规则和转人工策略。
8. 输出格式约束。

每次组装后的上下文保存到 `memory.context_snapshots`，并通过 `support.messages.context_snapshot_id` 和 `support.conversations.last_context_snapshot_id` 关联，方便追溯“AI 当时为什么这么答”。

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File tests/database/verify_ai_customer_service_schema.ps1
powershell -ExecutionPolicy Bypass -File tests/database/verify_data_governance_rules.ps1
```
