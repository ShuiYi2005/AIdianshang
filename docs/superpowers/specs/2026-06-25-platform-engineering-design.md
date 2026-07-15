# Platform Engineering Design

## Goal

把项目从工程化 Demo 推进到 MVP 骨架：环境配置标准化、资产文件化、模拟工作流规范化、业务数据库接入路径明确化。

## Scope

本设计覆盖：

- 环境配置和 Secret 分层。
- 一键验证脚本。
- Prompt、Dify、n8n 资产化目录。
- 客服规则配置。
- db-simulator 连接业务库的后续路径。

不覆盖：

- 真实电商 API 对接。
- 生产 Kubernetes 部署。
- 完整人工客服后台。

## Architecture

项目保留 Dify 和 n8n 作为平台层，业务能力沉淀在 `services/`。平台配置、Prompt、工作流、客服规则以文件形式保存在仓库中。运行环境通过 `deployment/env/<env>.env` 和 `config/app.<env>.yaml` 分层加载。

## Verification

每一阶段必须通过：

- Compose config 解析。
- 核心 HTTP 接口验证。
- 业务库 schema 验证。
- 环境变量检查。
- 明文密钥扫描。
