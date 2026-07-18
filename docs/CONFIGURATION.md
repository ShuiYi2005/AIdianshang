# CONFIGURATION

## 环境分层

项目按以下环境分层设计：

| 环境 | 用途 | 数据 | 密钥 |
|---|---|---|---|
| `local` | 本机开发和 Demo | 本地 Docker volume | `deployment/env/local.env` |
| `dev` | 团队联调 | 非真实数据 | CI/CD Secret 或 dev secret |
| `staging` | 上线前验收 | 脱敏或仿真数据 | Secret Manager |
| `prod` | 正式生产 | 真实数据 | Secret Manager / KMS |

## 配置来源优先级

从高到低：

1. 云 Secret / CI Secret / Docker Secret / Kubernetes Secret。
2. Shell 环境变量。
3. `deployment/env/<env>.env`。
4. `config/app.<env>.yaml`。
5. `config/app.example.yaml`。
6. 代码默认值。

原则：

- 密码、API Key、Secret 只允许来自 1-3 层。
- 业务规则优先来自 `config/` 或数据库。
- Compose 中只保留服务拓扑、端口、volume、健康检查等非敏感配置。

## 当前本地运行

本地运行使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

该命令是 GitHub 新克隆仓库的唯一推荐入口：当 `deployment/env/local.env` 不存在时会从模板生成随机本地密钥；已有环境文件绝不会被覆盖。它会在启动 API 与前端前完成业务数据库迁移。

仅用于已初始化环境的排障方式：

```powershell
docker compose -f deployment/docker-compose.yml up -d
```

直接 Compose 启动不会自动执行增量迁移；请优先使用 `scripts/start-local.ps1`。

## 环境变量分类

### 平台密钥

- `DIFY_SECRET_KEY`
- `DIFY_INIT_PASSWORD`
- `DIFY_INNER_API_KEY`
- `PLUGIN_SERVER_KEY`
- `N8N_ENCRYPTION_KEY`

### 数据库

- `POSTGRES_PASSWORD`
- `BUSINESS_DB_USER`
- `BUSINESS_DB_PASSWORD`
- `BUSINESS_DB_NAME`

### 缓存

- `REDIS_PASSWORD`

### 应用环境

- `APP_ENV`

## 校验

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile deployment/env/local.env
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```
