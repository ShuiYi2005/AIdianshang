# 数据库表结构

## 服务

业务数据库服务：

```text
business-db
```

本机连接：

```text
host: localhost
port: 5433
database: app_business
user: app_user
```

真实密码位于 `deployment/env/local.env` 或对应环境的受保护配置文件中，不写入代码和文档。

## Schema 划分

| Schema | 职责 |
|---|---|
| `core` | 用户、客户等主体 |
| `commerce` | 商品、订单、订单明细、物流、物流轨迹 |
| `recruitment` | 简历、岗位、投递关系 |
| `support` | 客服会话、消息、工单 |
| `ops` | 上传任务、异步任务、草稿 |
| `audit` | 操作日志、审批、状态变更、AI/工具调用日志 |
| `knowledge` | 知识文档、版本、切片、同步任务 |
| `memory` | 长期记忆、上下文快照 |

## 设计原则

- Dify 平台库不存业务核心数据。
- 业务主库存结构化、长期、强一致数据。
- Redis 只放可丢失、可重建、带 TTL 的缓存数据。
- Weaviate 只放适合语义检索的非结构化知识。
- 文件原文和附件后续应放对象存储，数据库只保存 URI 和元数据。
- 审计表追加写，关键记录不随意物理删除。
- 外部事件和写操作使用唯一键、幂等键防重。
- 每次 AI 回复的上下文快照可追溯。

## 验证入口

```powershell
powershell -ExecutionPolicy Bypass -File tests/database/verify_business_schema.ps1
powershell -ExecutionPolicy Bypass -File tests/database/verify_ai_customer_service_schema.ps1
powershell -ExecutionPolicy Bypass -File tests/database/verify_data_governance_rules.ps1
```
