# 模拟客服消息工作流

## 目标

在不接真实电商 API 的情况下，模拟客服消息处理闭环。

## 流程

1. Webhook 接收消息。
2. 记录 `ops.webhook_events`，用 `provider + event_id` 防重复。
3. 生成或校验 `ops.idempotency_keys`，防止重复回复。
4. 调用 Dify 应用。
5. Dify 根据意图决定是否调用 `db-simulator`。
6. `db-simulator` 优先读取 `business-db`，未命中时回退 mock。
7. 组装 memory、RAG、tool、policy context。
8. 保存 `memory.context_snapshots`。
9. 命中高风险规则时写入 `support.handoff_queue`。
10. 返回统一客服回复结构。

## 输出结构

```json
{
  "conversation_id": "demo-conversation-id",
  "reply_type": "ai_reply",
  "content": "客服回复内容",
  "handoff_required": false,
  "tool_called": "get_order",
  "trace_id": "demo-trace-id"
}
```
