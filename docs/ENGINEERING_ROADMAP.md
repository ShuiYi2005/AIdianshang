# ENGINEERING ROADMAP

## 目标

本页记录工程化路线。当前 `main` 已完成本地 MVP 的主要纵切：业务库、`agent-service`、训练中心、模拟客服工作台、RAG、审计、评测入口和 Docker 验收均已有实现。真实电商适配器与生产部署仍是后续阶段。

- 当前服务仍可启动。
- 核心 HTTP 验证可通过。
- 有脚本化验证命令。
- 有回滚点或不破坏旧入口。

## 阶段 A：工程底座

范围：

- 环境分层：`local`、`dev`、`staging`、`prod`。
- 配置来源和优先级。
- Secret 与 `.env` 管理。
- 一键验证脚本。
- 环境变量校验脚本。
- 文档编码和内容修复。

验收：

- `docker compose` 仍可启动。
- `scripts/verify.ps1` 可验证核心服务。
- `scripts/check-env.ps1` 可验证必要变量。
- `docs/CONFIGURATION.md` 描述配置来源、优先级和环境分层。

## 阶段 B：资产化与模拟编排

范围：

- Prompt 目录规范。
- Dify 工具/应用配置导出规范。
- n8n 模拟工作流规范。
- 客服场景规则文件。
- 高风险转人工规则文件。

验收：

- `prompts/`、`workflows/`、`config/` 有可版本化资产。
- 不依赖平台界面记忆项目关键规则。
- 有模拟客服消息流程说明。

## 阶段 C：业务服务连接业务库

范围：

- `db-simulator` 从 Python 字典迁移到读取 `business-db`。
- 初始化种子数据。
- 保持原有 API 路径兼容。
- 增加服务级测试。

验收：

- 原有 `/api/order/{order_id}` 等接口仍可用。
- 数据来自 `business-db`。
- 数据库 schema 验证和服务接口验证均通过。

## 阶段 D：可观测与审计

范围：

- 请求日志格式规范。
- 工具调用日志规范。
- AI 回复日志规范。
- 转人工记录规范。
- 运维检查清单。

验收：

- 关键调用有 trace id。
- 审计数据能落到 `audit` schema 或有明确落库路径。

## 尚未纳入当前本地 MVP

- 真实电商 API 对接。
- 生产级 Kubernetes 部署。
- 多租户计费。
- 真实平台上的人工坐席与渠道消息同步。
