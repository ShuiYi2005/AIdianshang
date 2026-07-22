# AI 智能客服系统

> 面向电商售前、订单查询与售后场景的本地可运行 AI 客服 MVP：把 AI 回复、风险转人工、人工接管、训练发布和知识检索做成可演示、可审计的闭环。

## 30 秒了解项目

**解决的问题**：电商客服的常见问答可由 AI 和可配置训练主题处理；订单等实时事实必须通过受控工具查询；退款、投诉、赔偿、身份核验等风险请求必须转人工，并留下审计记录。

**项目实现**：React 运营台、FastAPI `agent-service`、模拟电商 Tool、PostgreSQL 业务库、Weaviate 向量检索、n8n webhook 编排与 Docker Compose 一键运行。

**可展示成果**：

- 客服工作台支持转人工队列、领取、人工回复、建工单、解决会话和审计时间线。
- AI 训练中心支持主题、图文/视频素材、预览、不可变发布版本、回滚和知识库同步。
- 本地 RAG 基于 `BAAI/bge-small-zh-v1.5` 与 Weaviate；订单与物流等实时事实不进入向量库。
- 风险请求优先转人工，订单查询优先走 Tool；两类请求不会执行无用 RAG 检索。

## 3 分钟演示

启动后访问 `http://localhost:4173`。完整面试演示步骤、可复制命令和预期现象见 [HR 演示指南](docs/HR_DEMO_GUIDE.md)。

1. 在“客服工作台”查看转人工队列，领取会话、模拟发送人工回复、创建工单并解决任务。
2. 用演示命令触发订单查询与投诉/退款请求：前者返回脱敏订单信息，后者进入人工队列。
3. 在“AI 训练中心”创建一个主题，上传素材、预览回复、发布版本并回滚。
4. 点击“立即同步”，查看嵌入模型、Weaviate 连通性、文档数与切片数。

## 技术亮点与验证证据

| 领域 | 实现与证据 |
|---|---|
| 服务编排 | Docker Compose 启动 Dify、n8n、PostgreSQL、Redis、Weaviate、模拟 Tool、`agent-service` 与 React 运营台。 |
| 安全策略 | 风险词转人工、订单/地址/手机号脱敏、上下文快照与 AI/Tool 审计。 |
| RAG | 启动自动索引、Weaviate 健康探测、失败可重试；向量结果包含资料来源、版本与切片标识。 |
| 回归测试 | 后端单元测试 **27/27**、前端测试 **18/18**；完整 Docker 验收入口为 `scripts/verify.ps1`。 |

```powershell
# 后端单元测试
Set-Location services/agent-service
python -m unittest discover -v

# 前端测试
Set-Location ../support-console
npm test -- --run

# 回到仓库根目录后执行完整 Docker 验收
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

## 真实边界

- 当前是**模拟电商渠道**：人工发送、订单/物流查询和会话数据均在本地模拟闭环中验证，尚未接入真实抖店/飞鸽或 CRM。
- 仓库不包含大模型供应商凭据、Dify App Key 或已发布 Chatflow。受版本控制的默认配置会走本地策略、训练主题、RAG 和转人工降级链路；未提交的本机环境配置可按需覆盖该默认值。
- 本项目验证的是本地 Docker 闭环，不等同于真实店铺、真实模型供应商或生产环境验收。

详细能力、已知限制和运行边界见 [当前项目状态](docs/CURRENT_STATUS.md)。

## 本地启动

前提：安装并启动 Docker Desktop，且首次启动可访问 Docker Hub、npm 与 PyPI。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

脚本会从 `deployment/env/local.env.example` 生成被 Git 忽略的本机环境文件、迁移业务数据库、构建本项目服务并启动完整栈。

常用入口：

- AI 客服运营台：`http://localhost:4173`
- Dify Web：`http://localhost:8080`
- n8n：`http://localhost:5678`
- `agent-service`：`http://localhost:8010`

## 项目结构

- `services/`：`agent-service`、模拟电商 Tool 与 React 运营台。
- `knowledge/`、`prompts/`、`workflows/`：可版本化的知识、策略与工作流资产。
- `deployment/`：Docker Compose、环境模板与数据库迁移。
- `docs/`：使用、架构、运维、安全、演示与当前能力边界。
- `tests/`：Docker、数据库、接口、RAG、前端与评测验证。

历史设计与发布快照仅用于追溯，不替代当前 `main` 代码；说明见 [设计与实施历史](docs/superpowers/README.md) 与 [发布快照说明](releases/README.md)。
