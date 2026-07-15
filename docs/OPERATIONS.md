# 运行与运维

## 本地启动

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d
```

## 全量验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
```

验证内容包括：

- 环境变量完整性。
- 明文密钥扫描。
- Compose 配置解析。
- Docker 服务启动。
- 业务库 schema 校验。
- 配置、Prompt、知识资产校验。
- `db-simulator` 读取 `business-db` 的集成测试。
- Dify Web/API、n8n、db-simulator HTTP 检查。
- Dify worker Redis broker 检查。

## 受限网络构建

当前机器没有本地 `python:3.12-slim` 基础镜像时，可以使用已有模拟服务镜像作为本地 base：

```powershell
docker tag ai20-db-simulator:latest ai20-db-simulator-base:latest
```

然后在本地环境文件中设置：

```text
DB_SIMULATOR_BASE_IMAGE=ai20-db-simulator-base:latest
```

联网或 CI 环境可保持默认：

```text
DB_SIMULATOR_BASE_IMAGE=python:3.12-slim
```

## 回滚

当前回滚点：

- Compose 升级前备份在 `backups/`。
- Dify 数据库升级前备份在 `backups/`。
- `deployment/docker-compose-old.yml` 保留旧版 Dify 参考配置。
- `ai20-db-simulator-base:latest` 可作为本地模拟服务回滚基础镜像。
- 当前目录不是 Git 仓库时，回滚主要依赖上述备份文件、镜像标签和 Docker volume 备份。

回滚原则：

1. 停止新容器。
2. 恢复 Compose 或镜像标签。
3. 如涉及数据库迁移，先恢复数据库备份。
4. 重新运行 `scripts/verify.ps1`。
