# AI 客服产品化完善执行计划

## 目标

把当前工程化 MVP 推进为可继续接真实业务的产品化 MVP 底座。先实现不依赖具体店铺 API 的通用能力，真实平台字段、鉴权、状态枚举在接入时通过 Adapter 补齐。

## 第一阶段：产品化纵切

目标是新增 `agent-service`，把以下能力串成一条可验证链路：

- API 管理基础：`X-Trace-Id`、`X-Idempotency-Key`、统一错误结构。
- Tool 调用：通过 `db-simulator` 查询订单、商品、物流。
- 权限与脱敏：API 返回值按默认策略隐藏手机号、地址等敏感字段。
- Context：保存 `memory.context_snapshots`。
- 审计：记录 Tool 调用和 AI 回复基础日志。
- 降级：Tool 超时或失败时返回可控说明，并可转人工。
- 健康检查：提供 `/health` 和 `/metrics`。

## 第二阶段：评测与发布控制

- 增加本地评测用例。
- 实现 `scripts/run-evaluations.ps1`。
- 每次 Prompt、Workflow、Tool 变更后跑评测。
- 将评测结果写入 `knowledge.evaluation_runs` 和 `knowledge.evaluation_results`。
- 引入灰度发布读取 `ops.feature_flags` 和 `ops.release_rollouts` 的执行逻辑。

## 第三阶段：监控与保留任务

- 增强健康检查，覆盖 Dify、n8n、Redis、Weaviate、业务库、Tool。
- 实现成本统计写入 `audit.cost_usage_events`。
- 实现数据保留任务，处理 context snapshot、消息、日志归档或删除。

## 第四阶段：人工客服台

- 实现最小客服台前端。
- 展示转人工队列、会话详情、客户画像、context 摘要、工单操作。
- 所有敏感字段按角色脱敏展示。

## 第五阶段：真实平台接入

- 接 CRM Adapter。
- 接电商 Adapter。
- 映射订单、售后、退款、物流、客户字段。
- 处理平台 webhook、限流、签名、错误码、重试。

## 当前交付边界

本轮已完成第一阶段的最小纵切，并把第二阶段的评测入口补成可运行脚本。真实 CRM/电商 API 不在本轮实现范围内，只保留接口边界。
