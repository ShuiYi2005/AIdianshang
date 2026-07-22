# 运行与运维

## 本地启动

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

首次联网启动会拉取固定版本的第三方镜像，并从仓库构建 `db-simulator`、`agent-service` 和 `support-console`。离线机器必须使用包含镜像归档的发布包，不应直接执行此命令。

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
- Dify Web/API、n8n、db-simulator、agent-service 与运营台 HTTP 检查。
- Dify worker Redis broker 检查。
- n8n webhook、训练中心、RAG、可观测性、评测与固定壳层 UI 合同检查。

该脚本验证的是本地 Docker 闭环；它不表示 Dify Chatflow 已发布、模型供应商已配置、真实电商后台已接入，或生产环境已验证。当前限制见 [CURRENT_STATUS.md](CURRENT_STATUS.md)。

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

- 当前仓库不保留本机 `backups/` 目录；代码与文档回滚使用 Git 提交。
- 需要回滚数据库时，应在变更前执行 `scripts/backup-release-data.ps1`，并把备份保存在受保护的仓库外位置。
- `deployment/docker-compose-old.yml` 保留旧版 Dify 参考配置。
- `ai20-db-simulator-base:latest` 可作为本地模拟服务回滚基础镜像。
- 当前项目是 Git 仓库；Docker volume 回滚仍需在变更前另行备份。

回滚原则：

1. 停止新容器。
2. 恢复 Compose 或镜像标签。
3. 如涉及数据库迁移，先恢复数据库备份。
4. 重新运行 `scripts/verify.ps1`。
