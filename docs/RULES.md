# RULES

## 强制规则

- 先 Spec，后 Coding。
- 必须测试或执行可复现验证。
- 禁止改平台源码。
- Dify、n8n 等平台能力保持隔离。
- 业务逻辑进入 `services/`。
- 部署配置进入 `deployment/`。

## 当前项目约束

- Dify 使用本地可用的 `1.14.2` 镜像；`deployment/docker-compose-old.yml` 仅保留 `0.15.3` 的历史兼容配置。
- `db-simulator` 是当前唯一业务服务。
- 真实抖店/飞鸽 API 尚未接入，当前使用模拟数据服务验证链路。
