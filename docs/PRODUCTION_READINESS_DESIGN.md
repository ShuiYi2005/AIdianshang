# 生产化能力设计

## 当前能立即完善的部分

以下能力不依赖具体店铺 API，可以现在标准化：

- 权限模型。
- 数据脱敏。
- 数据保留策略。
- 多租户隔离基础字段。
- 模型评测集结构。
- Tool 超时与降级策略。
- 监控告警指标结构。
- 成本统计结构。
- 数据同步任务结构。
- 灰度发布结构。
- 人工客服台后端数据基础。

以下能力需要接具体平台 API 后细化：

- 平台字段映射。
- 店铺 API 鉴权。
- 订单、售后、退款状态枚举。
- 平台错误码和重试策略。
- 平台速率限制。
- CRM 工单字段和坐席状态。
- 人工客服台前端交互。

## 权限模型

采用 RBAC 加数据策略：

- `core.roles`：角色。
- `core.permissions`：权限点。
- `core.role_permissions`：角色权限绑定。
- `core.user_roles`：用户角色绑定。
- `core.data_access_policies`：数据访问策略。

默认权限点：

| 权限 | 说明 |
|---|---|
| `orders.read` | 查看订单 |
| `resumes.read` | 查看简历 |
| `refunds.handle` | 处理退款 |
| `audit.read` | 查看审计日志 |
| `pii.read_full` | 查看完整敏感个人信息 |

高风险权限必须单独授权，不随普通客服角色默认开放。

## 数据脱敏

脱敏策略放在 `core.data_masking_policies`。

默认策略：

- 手机号：部分脱敏。
- 地址：部分脱敏。
- 简历内容：默认隐藏或摘要化。
- 聊天记录：按角色决定是否展示完整内容。
- API 返回值：默认隐藏敏感字段。

原则：

- AI 默认拿脱敏数据。
- 人工客服按角色拿必要字段。
- 审计人员可查看日志，但不默认获得完整 PII。

## 数据保留策略

保留策略放在：

- `ops.data_retention_policies`
- `ops.retention_jobs`

建议默认值：

| 数据 | 建议保留 |
|---|---|
| Redis 短期记忆 | 30 分钟到 7 天 |
| Tool 查询缓存 | 5 分钟到 1 小时 |
| 会话消息 | 180 天到 2 年 |
| 上下文快照 | 30 天到 180 天 |
| 工单与转人工记录 | 2 年以上 |
| 审计日志 | 1 年到 5 年 |
| 模型评测记录 | 1 年以上 |

实际保留期需要根据行业、合同和合规要求调整。

## 多租户隔离

基础方式是给核心表增加 `tenant_id`。

已覆盖：

- 客户、订单、商品、物流。
- 简历、岗位。
- 会话、消息、工单、转人工。
- 审计、上下文、长期记忆。
- 知识文档。

当前为了兼容 Demo 数据，`tenant_id` 暂时允许为空。正式多租户上线时，需要先给历史数据绑定默认租户，再收紧约束。

## 模型评测集

评测数据放在：

- `knowledge.evaluation_sets`
- `knowledge.evaluation_cases`
- `knowledge.evaluation_runs`
- `knowledge.evaluation_results`

每次 Prompt、知识库、Workflow、Tool 改动后，应至少跑以下场景：

- 订单查询。
- 物流查询。
- 库存查询。
- 退款争议。
- 投诉。
- 赔偿。
- 转人工。
- 无法确认时拒绝编造。
- 敏感信息不泄露。

## Tool 超时与降级

策略放在：

- `ops.tool_fallback_policies`
- `ops.tool_invocation_policies`

推荐规则：

- 查询订单/商品：优先短重试，失败可用短缓存。
- 物流查询：失败时说明暂时无法确认，必要时转人工。
- 创建工单：失败后可重试，必须幂等。
- 退款/赔偿/改地址：默认人工审批。

## 监控告警

指标和告警事件放在：

- `audit.metrics_events`
- `audit.alert_events`

必须监控：

- Dify API 可用性。
- n8n webhook 成功率。
- Tool 超时率。
- 数据库连接和慢查询。
- Redis 可用性。
- Weaviate 检索失败率。
- RAG 命中率。
- 转人工率。
- 模型错误率。

## 成本控制

成本事件放在 `audit.cost_usage_events`。

统计内容：

- 模型调用次数。
- prompt tokens。
- completion tokens。
- RAG tokens。
- Tool 调用次数。
- 估算成本。
- 缓存命中率。

成本应按 tenant、模型、渠道、Agent、工作流维度统计。

## 数据同步

同步结构：

- `ops.external_sync_jobs`
- `ops.external_sync_cursors`
- `ops.webhook_events`
- `ops.idempotency_keys`

必须处理：

- 延迟。
- 重复。
- 乱序。
- 失败重试。
- 增量 cursor。
- webhook 对账。

## 灰度发布

灰度结构：

- `ops.feature_flags`
- `ops.release_rollouts`

适用对象：

- Prompt。
- 知识库。
- Workflow。
- Tool。
- 模型。

原则：

- 先小流量。
- 跑评测。
- 观察指标。
- 可暂停、可回滚。

## 人工客服台

当前后端基础：

- `support.handoff_queue`
- `support.agent_workbench_sessions`
- `support.tickets`
- `support.conversations`
- `memory.context_snapshots`

前端客服台后续需要：

- 待处理队列。
- 会话详情。
- AI 摘要和上下文。
- 客户画像。
- 工单操作。
- 转接、关闭、备注。
- 敏感字段按权限展示。
