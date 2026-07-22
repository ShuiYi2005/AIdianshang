# SECURITY

## 当前状态

当前项目已把 Compose 中的明文密码、密钥、API Key 改为变量引用。本地默认通过被 Git 忽略的 `deployment/env/local.env` 注入；该文件由 `scripts/bootstrap-local.ps1` 从受版本控制的模板生成。

已处理：

- `deployment/docker-compose.yml` 不再直接写死 `POSTGRES_PASSWORD`、`DIFY_SECRET_KEY`、`N8N_ENCRYPTION_KEY` 等敏感值。
- `deployment/env/local.env.example`、`dev.env.example`、`staging.env.example`、`prod.env.example` 和 `release.env.example` 只保留示例占位值。
- `.gitignore` 已忽略 `deployment/.env`、`deployment/env/local.env`、`dify/storage/` 和 `backups/`。

仍需注意：

- `deployment/env/local.env` 保存本机可用的 Demo 密钥。
- `dify/storage/` 下存在 Dify 运行私钥和存储数据，不能提交或公开。
- 当前密钥值是 Demo 级别，正式部署前必须更换为强随机密钥。

## 行业常见设计

### 本地开发

- `deployment/env/local.env` 保存本地密钥。
- `deployment/env/local.env.example` 保存变量名和示例值。
- `.gitignore` 忽略真实本地环境文件。

### 测试和预生产

- 使用 CI/CD Secret Variables 注入。
- 每个环境独立密钥。
- 禁止复用生产密钥。

### 正式生产

- 使用云 KMS、Vault、Kubernetes Secret、Docker Secret 或企业密码库。
- 密钥运行时注入，不写入镜像、不写入代码仓库。
- 开启访问审计、最小权限、定期轮换。
- 对 API Key、数据库密码、Webhook Secret 分级管理。

## 密钥分类建议

| 类型 | 当前位置 | 推荐位置 |
|---|---|---|
| Dify Secret Key | `deployment/env/local.env` | KMS / Secret Manager |
| 数据库密码 | `deployment/env/local.env` | KMS / Secret Manager |
| n8n Encryption Key | `deployment/env/local.env` | KMS / Secret Manager |
| 大模型 API Key | Dify 平台配置或 `.env` | KMS / Secret Manager |
| 电商平台 AppSecret | 尚未接入 | KMS / Secret Manager |
| Dify storage 私钥 | `dify/storage/` | 私有持久卷 / 对象存储 / Secret |
