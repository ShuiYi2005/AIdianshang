# 可复现 Docker 交付设计

## 目标

让具备 Docker Desktop 与互联网访问能力的开发者从 GitHub 克隆仓库后，通过一个 PowerShell 命令生成本地环境、执行数据库迁移并启动全部服务；同时让离线发布包带齐全部运行镜像（包括客服前端）。

## 部署模式

默认 `deployment/docker-compose.yml` 是联网开发模式：第三方镜像允许在本机缺失时从公开仓库拉取；本项目三个服务（`db-simulator`、`agent-service`、`support-console`）始终由仓库源码构建。n8n 固定到当前已验证的 `2.22.5` 版本。`deployment/docker-compose.release.yml` 是离线覆盖层：禁用拉取和构建，只使用发布包加载的带版本镜像。

## 启动与迁移

`scripts/bootstrap-local.ps1` 只在本地环境文件不存在时从模板生成随机强密钥，绝不覆盖已有文件。`scripts/start-local.ps1` 先启动业务数据库、执行全部幂等迁移，再启动完整服务栈。README 和运维文档只将该脚本作为新克隆的默认入口。

## 离线包

打包脚本构建并以发布版本标记三个本项目镜像，把它们写进 manifest 和发布包环境模板。离线 Compose 覆盖所有三个服务的 `build`，使安装机不需要源码或联网。安装脚本在完整启动前执行迁移。

## 验收

1. 模板环境可通过 Compose 配置检查，默认 Compose 不再把公开第三方镜像锁为 `pull_policy: never`。
2. 空目录运行 bootstrap 后得到非模板密钥的环境文件；start 脚本按“数据库、迁移、全栈”顺序调用。
3. 发布 manifest、发布 Compose 和打包脚本均包含 `ai20-support-console`，且其发布镜像标记可由安装机使用。
4. 现有 Docker Compose 完整验证和前端测试保持通过。
