# ASSET MANAGEMENT

## 目标

把 Dify、n8n、Prompt、客服规则从平台界面记忆中沉淀到仓库，做到可追踪、可审查、可回滚。

## Prompt

目录：

```text
prompts/
  support/
  sales/
  shared/
```

规则：

- 系统提示词、工具说明、拒答策略、转人工策略必须文件化。
- 文件命名使用业务域和用途。
- 平台界面中的 Prompt 变更后，应同步回仓库。

## Dify 资产

目录：

```text
dify-assets/
  apps/
  tools/
  datasets/
```

规则：

- 应用配置导出到 `dify-assets/apps/`。
- 工具接口契约放 `specs/tools/`。
- 知识库原文放 `knowledge/`，向量索引由 Dify/Weaviate 生成。

## n8n 工作流

目录：

```text
workflows/n8n/
```

规则：

- 工作流导出 JSON 后提交。
- Workflow 只做编排，不承载复杂业务计算。
- 复杂逻辑进入 `services/`。

## 客服规则

目录：

```text
config/customer-service/
```

文件：

- `handoff-rules.yaml`
- `faq-routing.yaml`
- `risk-keywords.yaml`

原则：

- 高风险问题转人工。
- 规则配置可被测试脚本读取。
- 不把规则散落在平台界面。
