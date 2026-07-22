# README 客服工作台截图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 GitHub 仓库首页展示一张真实运行的客服工作台截图。

**Architecture:** 复用现有 React 运营台，不增加页面、服务、依赖或运行时配置。将本地演示数据下的桌面端界面保存为 JPEG，并使用相对路径嵌入根目录 README 的项目摘要之后。

**Tech Stack:** React/Vite 现有前端、PNG、Markdown、Git。

## Global Constraints

- 只修改 `README.md` 和新增的 `docs/images/support-console-overview.jpg`；不修改 `services/`、`platform/`、`workflows/` 或部署配置。
- 截图必须来自当前可运行的客服工作台，且只包含本地演示数据，不包含凭据或真实客户信息。
- 图片置于 README 顶部项目摘要位置，不新增 GitHub Pages 或其他展示页。

---

### Task 1: 生成并嵌入真实工作台截图

**Files:**
- Create: `docs/images/support-console-overview.jpg`
- Modify: `README.md`
- Test: 文件可读、README 相对图片路径可解析

**Interfaces:**
- Consumes: `services/support-console` 在 `http://localhost:4173` 提供的现有运营台。
- Produces: `docs/images/support-console-overview.jpg`，供根目录 README 的 Markdown 图片引用。

- [x] **Step 1: 启动或确认现有客服运营台可访问**

Run `Invoke-WebRequest http://localhost:4173 -UseBasicParsing`。预期响应状态码为 `200`；若服务未运行，则使用仓库既有启动方式启动，不改动服务配置。

- [x] **Step 2: 在桌面宽屏下截取客服工作台**

Capture the existing workbench at a 1440px-class desktop viewport. Ensure the frame contains the conversation list, chat panel, composer, and right-side order/product panel. Save exactly as `docs/images/support-console-overview.jpg`.

- [x] **Step 3: 在 README 摘要后插入图片**

Insert `![AI 客服工作台界面](docs/images/support-console-overview.jpg)` immediately after the “30 秒了解项目” summary bullets and before the “3 分钟演示” heading.

- [x] **Step 4: 静态核验图片和引用**

Run `$image = Get-Item 'docs/images/support-console-overview.jpg'; if ($image.Length -le 0) { throw '截图文件为空' }; if (-not (Select-String -Path README.md -Pattern '\!\[AI 客服工作台界面\]\(docs/images/support-console-overview\.jpg\)')) { throw 'README 未引用截图' }`。

Expected: 命令无错误，图片文件非空，README 含唯一正确路径。

- [x] **Step 5: 审核变更并提交**

Run `git diff --check`、`git status --short`、`git add README.md docs/images/support-console-overview.jpg`、`git commit -m "docs: add support console screenshot"`。

Expected: 空白检查通过，提交包含 README、JPEG 截图与本次过程文档。
