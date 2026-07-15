# .spec

本目录是给编码代理读取的规格入口。

## 读取顺序

1. `docs/RULES.md`
2. `docs/ARCHITECTURE.md`
3. `specs/designs/current-architecture.md`
4. `specs/tools/db-simulator.yaml`
5. `specs/schemas/db-simulator.json`
6. `specs/workflows/customer-support.yaml`

## 编码边界

- 业务代码：`services/`
- 部署配置：`deployment/`
- 平台源码：`platform/`，禁止修改
