# AI 客服工作台与训练中心设计

## 目标

在不修改 Dify、n8n 或其他 `platform/` 源码的前提下，交付可独立部署的 React 客服运营后台。后台把现有 `agent-service` 的会话、订单查询、上下文快照、审计和转人工能力，连接为坐席可操作的客服工作台；同时提供商家可操作的 AI 训练、素材管理、测试预览、灰度发布和回滚闭环。

## 范围与边界

本轮包含两个独立页面及其全部可见交互：

1. **客服工作台**：查看/筛选转人工队列、领取任务、查看会话和 AI 证据、发送人工回复、创建工单、解决任务。
2. **AI 训练中心**：创建训练主题、上传文字/图片/视频素材、配置触发语和标准回复、绑定店铺/商品范围、预览、发布、回滚。

当前没有真实电商账号，因此对外消息发送使用 `simulated-ecommerce` 渠道：写入会话消息、操作审计和上下文快照，并在界面标明“模拟渠道已发送”。真实电商 Adapter、OAuth、Webhook 签名和真实退款执行不在本轮范围内。

图片和视频素材会真实上传、持久化、预览并作为客服回复附件保存。没有配置视觉/视频模型时，客户上传的图片或视频不会被伪装为已理解：服务保存附件元数据，回复“需人工核验”并创建转人工任务。这是安全降级而非假识别。

## 架构

采用独立 React 单页应用服务 `services/support-console`，由 Docker Compose 暴露在 `http://localhost:4173`。服务使用 React、TypeScript、Vite 构建，容器内的 Node 静态服务器托管构建产物。浏览器通过 `VITE_AGENT_API_BASE_URL=http://localhost:8010` 调用 `agent-service`；`agent-service` 仅对白名单本地控制台来源启用 CORS。

所有业务判断、状态变更、文件校验、数据库持久化和审计仍放在 `services/agent-service`。前端只负责展示、输入校验、加载/空/失败状态和调用 API。`workflows/` 不承载业务逻辑，`deployment/` 只承载支持控制台服务配置。

## 页面与交互

### 客服工作台

页面沿用参考产品的高密度桌面式工作区，但使用白灰中性色背景、深蓝主操作色和红橙风险提示色；不使用泛黄滤镜、原产品品牌、文案、头像或图标。

- 顶栏：店铺标识、当前模拟坐席、待处理总数和训练中心入口。
- 左侧导航：工作台、AI 训练、审计。
- 队列栏：按 `pending`/`assigned` 状态筛选，按优先级与创建时间排序；每项显示客户、触发原因、优先级和状态。
- 会话栏：显示客户消息、AI 消息和人工消息；可领取、发送人工回复、创建工单、解决转人工。
- 证据栏：显示订单/客户脱敏信息、AI 转人工原因、知识来源、工具调用和上下文快照 ID。

所有按钮对应后端持久化操作或页面导航。敏感操作在前端确认后才调用 API；API 失败时保留输入并显示可恢复错误。

### AI 训练中心

- 主题列表：显示草稿、已发布、已回滚状态及版本号。
- 训练编辑器：主题名称、触发语、标准回复、店铺、商品范围和渠道。
- 素材区：接受 `.txt`、`.md`、`.png`、`.jpg`、`.jpeg`、`.webp`、`.mp4`；后端限制单文件 16 MB，保存原始文件、MIME 类型、大小和用户提供描述。
- 预览：使用触发语运行本地训练规则，展示命中的主题、标准回复和将发送的素材；退款、赔偿、投诉、身份核验始终返回转人工提示。
- 发布：由草稿生成不可变发布版本，状态改为 `published`；同一范围内旧发布版本改为 `superseded`。
- 回滚：选择已发布历史版本，恢复为当前发布版本并写操作审计。

## 后端接口

现有 `/api/agent/reply`、`/api/workbench/handoffs` 和解决任务接口继续兼容。新增接口统一返回 JSON，使用 `X-Trace-Id` 关联审计：

- `GET /api/console/queue?status=pending|assigned`：转人工队列。
- `GET /api/console/handoffs/{id}`：会话、脱敏客户/订单、上下文、审计证据。
- `POST /api/console/handoffs/{id}/claim`：将 pending 项改为 assigned。
- `POST /api/console/handoffs/{id}/reply`：持久化人工回复和模拟渠道出站审计。
- `POST /api/console/handoffs/{id}/ticket`：创建或关联本地工单。
- `POST /api/console/handoffs/{id}/resolve`：解决任务；兼容现有 resolve 行为。
- `GET /api/training/topics`、`POST /api/training/topics`、`PUT /api/training/topics/{id}`：训练主题 CRUD。
- `POST /api/training/topics/{id}/assets`：受限素材上传。
- `POST /api/training/topics/{id}/preview`：安全训练预览。
- `POST /api/training/topics/{id}/publish`：发布版本。
- `POST /api/training/topics/{id}/rollback`：回滚指定版本。

## 数据与安全

新增迁移创建 `knowledge.training_topics`、`knowledge.training_assets`、`knowledge.training_versions` 与 `audit.console_action_logs`。主题、素材和版本都带 `tenant_id`（本地 Demo 可以为空）、时间戳和操作元数据。上传文件写入命名 Docker volume，不写入 Git 仓库；数据库只保存相对路径，下载接口拒绝目录穿越。

转人工、退款、赔偿、投诉、身份核验和附件理解失败均以转人工为准。训练主题的标准回复不能绕过该策略。所有坐席动作和训练发布/回滚都写审计记录；界面仅展示脱敏客户数据。

## 验收与验证

- 后端单元测试覆盖敏感语义优先转人工、训练触发语匹配、文件类型/大小拒绝和发布/回滚状态机。
- 服务级 PowerShell 测试覆盖训练主题创建、素材上传、预览、发布、回滚、队列领取、人工回复、工单创建、解决和数据库审计。
- 前端测试覆盖页面切换、队列选择、领取、回复、工单、解决、训练主题保存、预览、上传、发布和回滚的成功与失败状态。
- Docker Compose 配置、前端构建、控制台 HTTP 健康检查、Agent HTTP 接口和已有核心验证脚本全部运行。

## 明确排除

- 真实电商后台、CRM、支付、退款或赔偿的外部写操作。
- 未配置模型凭证时的图片/视频语义识别。
- 真实登录态、生产级多租户认证和外部对象存储。

这些能力在后续接入真实 Adapter 和模型供应商后扩展；本轮的 API、数据模型和 UI 状态已为其保留替换边界。
