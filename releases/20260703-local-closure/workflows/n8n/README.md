# n8n Workflows

本目录保存 n8n 工作流导出 JSON。

Workflow 规则：

- 只做编排。
- 不做复杂业务计算。
- 复杂逻辑进入 `services/`。
- 密钥通过 n8n credential 或环境变量管理，不写入 JSON。

当前建议模拟流程：

```text
Webhook 接收客服消息
-> 调用 Dify API
-> 根据结果调用 db-simulator 或业务服务
-> 输出标准客服回复 JSON
```
