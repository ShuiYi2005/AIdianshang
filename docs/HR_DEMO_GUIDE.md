# HR / 面试演示指南

> 目标：用约 3 分钟展示“项目解决了什么、如何工作、我如何验证它”，同时明确它仍是模拟电商 MVP。

## 演示前准备

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```

浏览器打开 `http://localhost:4173`。首次运行会下载镜像和依赖；正式演示前建议先完成一次启动。

## 讲解顺序

### 1. 先讲业务闭环（30 秒）

“这是一个电商 AI 客服 MVP。普通商品问题可以由训练主题和知识库处理；订单信息必须通过 Tool 查询；退款、投诉、赔偿等风险场景自动转人工。人工接手后仍能看到上下文、回复记录和审计证据。”

### 2. 演示订单查询与风险转人工（60 秒）

在 PowerShell 中发送两条模拟客户消息：

```powershell
$order = @{ conversation_id = 'hr-order-demo'; platform = 'demo'; customer_id = 'hr-customer-1'; user_message = '请查询订单 ORD-DBTEST' } | ConvertTo-Json
Invoke-RestMethod http://localhost:8010/api/agent/reply -Method Post -ContentType 'application/json; charset=utf-8' -Body $order

$risk = @{ conversation_id = 'hr-risk-demo'; platform = 'demo'; customer_id = 'hr-customer-2'; user_message = 'I want to complain and request compensation' } | ConvertTo-Json
Invoke-RestMethod http://localhost:8010/api/agent/reply -Method Post -ContentType 'application/json; charset=utf-8' -Body $risk
```

预期：

- 订单请求返回脱敏后的订单状态和物流信息，说明实时事实来自受控 Tool，而不是知识库编造。
- 风险请求返回 `handoff_required=true`。回到运营台“客服工作台”刷新队列，可领取会话、发送模拟人工回复、创建工单并解决任务。

### 3. 演示训练与回滚（60 秒）

进入“AI 训练中心”：

1. 新建主题，填写触发短语和回复内容。
2. 上传允许的图片、视频或文本素材。
3. 输入一条客户问题，点击“预览回复”。
4. 点击“发布训练”，说明系统生成不可变版本。
5. 选择历史版本并回滚，说明回滚生成新版本，不会篡改历史记录。

### 4. 演示 RAG 与工程验证（30 秒）

在训练中心点击“立即同步”。页面会展示模型名、Weaviate 连通性、文档数、切片数和同步状态。

最后说明：

“本地检索使用轻量中文嵌入模型与 Weaviate。后端有 27 个单元测试、前端有 18 个测试，完整 Docker 验收由 `scripts/verify.ps1` 执行。”

## 必须如实说明的边界

- 当前订单、物流与人工发送是本地模拟渠道，不是已接入的真实店铺后台。
- 公开仓库没有大模型 API Key、已发布 Dify Chatflow 或模型供应商凭据。
- Dify 可作为目标环境的模型编排入口；没有凭据时系统会走本地策略、训练主题、RAG 和转人工降级链路。

这些边界不是功能缺失的掩饰，而是公开演示仓库避免暴露凭据、避免伪造真实电商接入状态的设计选择。
