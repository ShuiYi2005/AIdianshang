# 语言设置

- 默认输出语言：简体中文
- 代码中的注释可用英文，但对话和解释必须用中文

# 项目开发规则

- 先读 `.spec/`、`docs/`、`specs/` 中的约束，再修改代码。
- 禁止修改 `platform/` 中的开源平台源码。
- 业务代码只放在 `services/`。
- `workflows/` 只做流程编排，不承载复杂业务计算。
- `prompts/` 用文件管理提示词，不把提示词只留在平台界面。
- 部署配置统一放在 `deployment/`。
- 修改后必须验证 Docker Compose 和核心 HTTP 接口。

## 当前工程事实

- 业务服务位于 `services/db-simulator/`、`services/agent-service/` 和 `services/support-console/`；不得把业务逻辑移入 `platform/`、`workflows/` 或 `deployment/`。
- 新克隆仓库的推荐入口是 `scripts/start-local.ps1`；完整本地验收入口是 `scripts/verify.ps1 -EnvFile deployment/env/local.env`。
- 受版本控制的默认配置不含模型供应商凭据或 Dify App Key；真实电商渠道尚未接入，当前为模拟渠道闭环。
- `docs/CURRENT_STATUS.md` 是已实现能力与已知限制的权威摘要；`docs/superpowers/` 和 `releases/` 仅作历史追溯。
