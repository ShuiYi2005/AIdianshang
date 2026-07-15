# DECISIONS

## Dify 版本

当前主部署配置使用：

- `langgenius/dify-api:1.14.2`
- `langgenius/dify-web:1.14.2`
- `langgenius/dify-plugin-daemon:0.6.1-local`

原因：`1.14.2` 是当前可拉取并已完成本地验证的 Dify 1.x 镜像版本；项目已从 `0.15.3` 升级到该版本。

保留 `deployment/docker-compose-old.yml` 作为旧版参考配置。

## 密钥管理

密钥不再直接写在 `deployment/docker-compose.yml` 中，改由 `deployment/.env` 注入。

`.env` 只适合本地开发和 Demo，不应提交到代码仓库。正式环境应使用云密钥管理、Docker/Kubernetes Secret、CI/CD Secret 或企业密码库。

## 任务队列

Celery broker 使用 Redis：`redis://redis:6379/1`。

原因：项目已包含 Redis 服务；未配置时 worker 会退回连接 RabbitMQ，但当前 Compose 中没有 RabbitMQ。

## 模拟数据服务

`db-simulator` 保留为独立 FastAPI 服务。

原因：当前真实抖店/飞鸽 API 尚未接入，模拟服务用于验证订单、商品、物流查询链路。
