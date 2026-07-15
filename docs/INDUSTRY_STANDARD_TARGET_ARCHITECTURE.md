# 行业标准目标架构与接口边界

## 设计原则

这套架构先定义稳定边界，再接具体店铺 API。行业标准部分可以现在确定，平台字段、状态枚举、鉴权细节在接入抖店、淘宝、京东或 CRM 后细化。

核心原则：

- 平台无关：内部模型不绑定某一家电商平台。
- 事实优先：订单、库存、物流以业务库或平台 API 为准。
- 可追溯：每次回复都能追踪 prompt、context、RAG、Tool 和审计日志。
- 可回滚：Prompt、知识库、Workflow、Tool、Adapter 都要版本化。
- 可观测：每个关键链路都有日志、指标和告警。
- 可控执行：查询类 Tool 可自动调用，写入类 Tool 需要权限、幂等和必要审批。

## 分层

| 层 | 职责 | 当前状态 |
|---|---|---|
| 渠道层 | 接收店铺、网页、IM、CRM 消息 | 待接入 |
| API 管理层 | 鉴权、限流、幂等、版本、错误码、日志 | 设计中 |
| Workflow 引擎 | webhook、路由、重试、通知、转人工编排 | n8n 已运行，正式流程待导出 |
| Agent 服务层 | 记忆、上下文、RAG、Tool、策略、审计编排 | 待实现 |
| Dify/模型层 | LLM 应用、Prompt、知识库、工具调用 | 已运行 |
| Tool 层 | AI 可调用的受控业务能力 | 已有 `db-simulator` |
| Adapter 层 | CRM/电商平台字段映射和 API 对接 | 待实现 |
| 数据层 | 业务库、Redis、Weaviate、审计 | 已有基础 |
| 监控评测层 | 质量、延迟、成本、命中率、安全评测 | 待实现 |

## 正式 Agent 服务层

Agent 服务层是 AI 客服的核心编排服务，不替代 Dify，而是在 Dify 前后补齐生产级控制。

输入：

- 用户消息。
- 会话 ID。
- 平台来源。
- 用户/客户 ID。
- trace ID。

输出：

- 回复内容。
- 是否转人工。
- 使用的 Tool。
- context snapshot ID。
- 风险标记。
- 审计事件。

边界：

- 读取长期记忆和最近消息。
- 组装 prompt context。
- 调用 Dify 或模型。
- 调用 RAG 检索。
- 调用 Tool。
- 写入 `memory.context_snapshots`、`audit.tool_call_logs`、`audit.ai_response_logs`。
- 不直接持有外部平台差异，平台差异交给 Adapter。

## API 管理层

API 管理层位于外部系统和内部服务之间。

必须具备：

- 统一鉴权。
- 请求签名校验。
- 速率限制。
- 幂等键。
- 请求/响应日志。
- 错误码标准化。
- API 版本管理。
- 敏感字段脱敏。
- trace ID 透传。

标准 Header：

```text
X-Request-Id
X-Trace-Id
X-Idempotency-Key
X-Client-Id
X-Signature
X-Api-Version
```

## Workflow 引擎

n8n 负责流程编排，不负责复杂业务判断。

标准流程：

1. 接收 webhook。
2. 写入 `ops.webhook_events` 去重。
3. 校验 `ops.idempotency_keys`。
4. 调用 Agent 服务。
5. 处理超时、重试、降级。
6. 命中转人工时通知 CRM 或客服台。
7. 返回渠道统一响应。

## RAG 系统

RAG 负责知识检索，不负责实时事实。

适合进入 RAG：

- 售后政策。
- FAQ。
- 商品说明。
- 尺码建议。
- 客服话术。
- 岗位 JD。
- 简历摘要。

不适合进入 RAG：

- 实时订单状态。
- 实时库存。
- 最新物流轨迹。
- 支付状态。
- 审批状态。

RAG 数据以 `knowledge.documents`、`knowledge.document_versions`、`knowledge.document_chunks` 做版本管理，向量数据进入 Weaviate。

## Tool 层

Tool 是 AI 可调用的受控 API。

Tool 类型：

- 查询类：查订单、查商品、查物流、查客户资料。
- 创建类：创建工单、创建转人工任务。
- 更新类：更新客户标签、更新工单状态。
- 高风险类：退款、赔偿、改地址、取消订单。

规则：

- 查询类可以自动调用。
- 创建类需要幂等和审计。
- 更新类需要权限和状态校验。
- 高风险类默认转人工或审批。

## CRM/电商适配器

Adapter 负责把外部平台差异转换为内部统一模型。

电商适配器统一输出：

- `UnifiedOrder`
- `UnifiedProduct`
- `UnifiedLogistics`
- `UnifiedRefund`
- `UnifiedCustomer`

CRM 适配器统一输出：

- `CustomerProfile`
- `Ticket`
- `HandoffTask`
- `AgentUser`
- `Conversation`

## 监控评测体系

监控关注系统是否稳定，评测关注 AI 答得是否好。

监控指标：

- 请求量。
- 错误率。
- P50/P95/P99 延迟。
- Tool 超时率。
- RAG 命中率。
- 转人工率。
- 用户满意度。
- 模型成本。
- 缓存命中率。

评测维度：

- 是否编造。
- 是否正确调用 Tool。
- 是否正确转人工。
- 是否引用正确知识。
- 是否泄露敏感信息。
- 是否符合话术规范。

## 生产化补强能力

以下能力已作为基础规格和数据库结构纳入设计：

- 权限模型：RBAC + 数据访问策略。
- 数据脱敏：按资源、字段、权限做 masking。
- 数据保留：按数据域配置保留期和归档/删除/匿名化动作。
- 多租户隔离：核心业务表引入 `tenant_id`。
- 模型评测集：Prompt、知识库、Workflow、Tool 改动后运行评测。
- Tool 超时与降级：按工具配置 timeout、retry、fallback。
- 监控告警：系统指标、告警事件、AI 质量指标。
- 成本控制：按租户、模型、调用链统计 token、Tool、成本。
- 数据同步：同步任务、cursor、webhook 去重、幂等。
- 灰度发布：feature flag 与 rollout。
- 人工客服台：转人工队列和坐席会话后端基础。

## 当前可立即设计，后续需平台细化

现在可以确定：

- 分层架构。
- 接口边界。
- 数据模型基线。
- Tool 权限等级。
- Workflow 标准步骤。
- 监控评测指标。
- 幂等、去重、审计、脱敏规则。

接具体 API 后细化：

- 平台鉴权。
- 字段映射。
- 订单/售后状态枚举。
- webhook 事件类型。
- 错误码映射。
- 速率限制。
- 平台操作权限。
