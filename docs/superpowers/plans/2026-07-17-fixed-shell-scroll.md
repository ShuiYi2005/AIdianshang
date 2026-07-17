# 固定壳层与单一主滚动区 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将客服控制台改造成不产生文档级滚动、桌面端消息主滚动与移动端覆盖式抽屉均可验证的固定壳层。

**Architecture:** 应用根节点和 `App` 负责把动态视口限制在 CSS Grid 壳层中。`Workbench` 通过同一份队列/证据内容在桌面三栏和移动覆盖层间切换，`TrainingCenter` 以同样的方式把主题列表移入覆盖层；所有长内容均收敛为页面内部的显式滚动容器。

**Tech Stack:** React 18、TypeScript、Vite、Vitest、Testing Library、CSS Grid、Docker Compose、Codex 应用内浏览器。

## Global Constraints

- 仅修改 `services/support-console`、前端测试、前端布局验证脚本和 `scripts/verify.ps1`；禁止修改 `platform/`、后端 API、数据模型或工作流。
- `html`、`body`、`#root` 必须为 `height: 100%` 与 `overflow: hidden`；应用壳层必须为 `height: 100dvh` 与 `overflow: hidden`。
- 桌面布局使用 CSS Grid；不得使用 `position: fixed` 拼接顶栏、侧栏、会话或输入框。
- 每一个滚动 Grid/Flex 子项显式声明 `min-height: 0`；需要横向收缩的子项同时声明 `min-width: 0`。
- 工作台的消息流是默认主滚动区，右侧证据栏独立滚动；回复输入框必须位于会话 Grid 的最后一行。
- 移动端的会话队列、证据栏和训练主题列表必须为覆盖式抽屉，不得挤压聊天或编辑区域；回复区包含 `env(safe-area-inset-bottom)`。
- 保持所有既有 API 调用、失败时保留输入、敏感操作确认和模拟渠道语义不变。
- 每个任务先执行失败测试，再写最小实现，任务结束时执行测试与提交。

---

## 文件结构

- 修改 `services/support-console/src/styles.css`：唯一的布局源，定义根壳层、桌面 Grid、页面内部滚动区、移动抽屉和安全区样式。
- 修改 `services/support-console/src/App.tsx`：让审计记录拥有内部滚动容器，并给 `app-content` 一个受控高度边界。
- 修改 `services/support-console/src/components/Workbench.tsx`：增加移动队列/证据抽屉状态与入口，不改变业务 API 调用。
- 修改 `services/support-console/src/components/EvidencePanel.tsx`：接受可选关闭回调，以便同一面板可在移动抽屉中关闭。
- 修改 `services/support-console/src/components/TrainingCenter.tsx`：增加主题列表抽屉开闭状态与移动入口。
- 修改 `services/support-console/src/App.test.tsx`、`services/support-console/src/components/Workbench.test.tsx`、`services/support-console/src/components/TrainingCenter.test.tsx`：覆盖抽屉的打开、关闭和既有闭环。
- 创建 `services/support-console/src/layout.contract.test.ts`：锁定根节点、壳层、主消息区、右栏和安全区的 CSS 合同，防止后续重新引入文档滚动。
- 创建 `tests/ui/verify_fixed_shell_layout.mjs`：作为仓库级源代码合同检查；由 `scripts/verify.ps1` 调用。

## Task 1: 根壳层、审计页与 CSS 滚动合同

**Files:**
- Modify: `services/support-console/src/App.tsx`
- Modify: `services/support-console/src/styles.css`
- Modify: `services/support-console/src/App.test.tsx`
- Create: `services/support-console/src/layout.contract.test.ts`

**Interfaces:**
- Consumes: 现有 `App` 的 `Route` 与 `AuditView`。
- Produces: `.app-frame`、`.app-body`、`.app-content` 和 `.audit-scroll` 均受动态视口约束；样式合同测试从 `styles.css?raw` 读取选择器文本。

- [ ] **Step 1: 写失败的布局合同与审计可访问性测试**

```ts
import { expect, it } from "vitest";
import stylesheet from "./styles.css?raw";

it("locks the document root and defines isolated scroll regions", () => {
  expect(stylesheet).toMatch(/html,\s*body,\s*#root\s*\{[^}]*height:\s*100%[^}]*overflow:\s*hidden/s);
  expect(stylesheet).toMatch(/\.app-frame\s*\{[^}]*height:\s*100dvh[^}]*overflow:\s*hidden/s);
  expect(stylesheet).toMatch(/\.audit-scroll\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
});
```

在 `App.test.tsx` 新增审计页断言：点击“审计”后存在 `aria-label="审计记录列表"` 的区域。

- [ ] **Step 2: 运行测试并确认失败**

Run: `Push-Location services/support-console; npm test -- --run src/layout.contract.test.ts src/App.test.tsx; Pop-Location`

Expected: `layout.contract.test.ts` 因缺少根锁定样式和 `.audit-scroll` 失败；审计可访问性断言失败。

- [ ] **Step 3: 写最小根壳层与审计实现**

在 `styles.css` 顶部替换根高度规则，并在 `App.tsx` 将审计表包装为内部滚动容器：

```tsx
function AuditView({ actions }: { actions: AuditAction[] }) {
  return <main className="audit-shell">
    <header className="page-heading">{/* 保留现有标题内容 */}</header>
    <section className="audit-scroll" aria-label="审计记录列表">
      <div className="audit-table">{/* 保留现有 actions / empty-state 内容 */}</div>
    </section>
  </main>;
}
```

```css
html, body, #root { height: 100%; overflow: hidden; }
body { margin: 0; min-width: 320px; background: #edf1f6; }
.app-frame { height: 100dvh; min-height: 0; overflow: hidden; display: grid; grid-template-rows: 72px minmax(0, 1fr); }
.app-body { min-height: 0; overflow: hidden; display: grid; grid-template-columns: 94px minmax(0, 1fr); }
.app-content { min-width: 0; min-height: 0; overflow: hidden; }
.audit-shell { min-height: 0; height: 100%; overflow: hidden; display: grid; grid-template-rows: auto minmax(0, 1fr); padding: 28px 32px; }
.audit-scroll { min-height: 0; overflow-y: auto; }
```

保留 `.global-header` 与 `.side-nav` 在普通 Grid 流中；删除其与页面固定效果有关的 `position: sticky` 规则。

- [ ] **Step 4: 运行前端测试和构建**

Run: `Push-Location services/support-console; npm test -- --run; npm run build; Pop-Location`

Expected: Vitest 全部通过，Vite 输出 `dist/`。

- [ ] **Step 5: 提交根壳层任务**

```powershell
git add services/support-console/src/App.tsx services/support-console/src/styles.css services/support-console/src/App.test.tsx services/support-console/src/layout.contract.test.ts
git commit -m "feat: lock support console application shell"
```

## Task 2: 工作台三栏 Grid、消息主滚动与移动抽屉

**Files:**
- Modify: `services/support-console/src/components/Workbench.tsx`
- Modify: `services/support-console/src/components/EvidencePanel.tsx`
- Modify: `services/support-console/src/styles.css`
- Modify: `services/support-console/src/components/Workbench.test.tsx`
- Modify: `services/support-console/src/layout.contract.test.ts`

**Interfaces:**
- Consumes: `WorkbenchApi`、`HandoffDetail`、现有 `EvidencePanel` 的 `detail`。
- Produces: `mobilePanel: "queue" | "evidence" | null`，可读的“会话列表”“客户信息”“关闭会话列表”“关闭客户信息”控件；`.message-stream`、`.evidence-panel`、`.queue-list` 独立滚动。

- [ ] **Step 1: 写失败的抽屉交互和滚动合同测试**

在 `Workbench.test.tsx` 使用现有 fake API 添加：

```tsx
it("opens and closes the mobile queue and customer-information drawers", async () => {
  const user = userEvent.setup();
  render(<Workbench api={api} />);
  await screen.findByText("顾客 3028");
  await user.click(screen.getByRole("button", { name: "会话列表" }));
  expect(screen.getByRole("dialog", { name: "会话列表" })).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "关闭会话列表" }));
  expect(screen.queryByRole("dialog", { name: "会话列表" })).not.toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "客户信息" }));
  expect(screen.getByRole("dialog", { name: "客户信息" })).toBeInTheDocument();
});
```

将以下断言补入 `layout.contract.test.ts`：

```ts
expect(stylesheet).toMatch(/\.workbench-shell\s*\{[^}]*grid-template-columns:[^}]*minmax\(0,\s*1fr\)[^}]*overflow:\s*hidden/s);
expect(stylesheet).toMatch(/\.message-stream\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
expect(stylesheet).toMatch(/\.evidence-panel\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
expect(stylesheet).toMatch(/\.reply-composer\s*\{[^}]*grid-row:\s*-1/s);
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `Push-Location services/support-console; npm test -- --run src/components/Workbench.test.tsx src/layout.contract.test.ts; Pop-Location`

Expected: 找不到移动入口、dialog 和新的 Grid/overflow 合同。

- [ ] **Step 3: 实现无业务副作用的移动抽屉状态**

在 `Workbench` 增加局部状态并只在窄屏工具条显示入口：

```tsx
const [mobilePanel, setMobilePanel] = useState<"queue" | "evidence" | null>(null);

<div className="mobile-context-actions" aria-label="移动会话上下文">
  <button className="secondary-action" aria-expanded={mobilePanel === "queue"}
    onClick={() => setMobilePanel("queue")}>会话列表</button>
  <button className="secondary-action" aria-expanded={mobilePanel === "evidence"}
    onClick={() => setMobilePanel("evidence")}>客户信息</button>
</div>
{mobilePanel && <button className="drawer-backdrop" aria-label="关闭覆盖层" onClick={() => setMobilePanel(null)} />}
```

将队列和证据栏保留为工作台 Grid 子项。为它们传入状态类和关闭控件，而不是复制 API 数据或重新请求：

```tsx
<section className={`queue-panel ${mobilePanel === "queue" ? "is-mobile-open" : ""}`}
  role={mobilePanel === "queue" ? "dialog" : undefined}
  aria-modal={mobilePanel === "queue" || undefined}
  aria-label="会话列表">
  <button className="drawer-close" aria-label="关闭会话列表" onClick={() => setMobilePanel(null)}>关闭</button>
  {/* 保留原有标题、筛选和 queue-list */}
</section>
<EvidencePanel detail={detail} mobileOpen={mobilePanel === "evidence"} onClose={() => setMobilePanel(null)} />
```

将 `EvidencePanel` 签名改为：

```tsx
export function EvidencePanel({ detail, mobileOpen = false, onClose }: {
  detail: HandoffDetail | null;
  mobileOpen?: boolean;
  onClose?: () => void;
})
```

在移动打开时为其输出 `role="dialog"`、`aria-modal="true"`、`aria-label="客户信息"` 和关闭按钮。桌面时不添加 dialog 角色。

- [ ] **Step 4: 将会话结构改为 Grid 固定输入区并补齐样式**

把现有的会话头、操作条、条件表单/提示包进 `.conversation-inline-state`，使会话栏的最后两项始终是消息流和输入框。使用以下关键样式，保留既有视觉 token：

```css
.workbench-shell { position: relative; min-width: 0; min-height: 0; height: 100%; overflow: hidden; display: grid; grid-template-columns: minmax(250px, 290px) minmax(0, 1fr) minmax(255px, 315px); background: #fff; }
.queue-panel { min-width: 0; min-height: 0; overflow: hidden; display: grid; grid-template-rows: auto auto minmax(0, 1fr); }
.queue-list { min-height: 0; overflow-y: auto; }
.conversation-panel { min-width: 0; min-height: 0; overflow: hidden; display: grid; grid-template-rows: auto auto auto auto minmax(0, 1fr) auto; background: #fff; }
.conversation-inline-state { min-height: 0; }
.message-stream { min-height: 0; overflow-y: auto; overscroll-behavior: contain; }
.reply-composer { grid-row: -1; min-height: 0; padding-bottom: calc(16px + env(safe-area-inset-bottom)); }
.evidence-panel { min-width: 0; min-height: 0; overflow-y: auto; overscroll-behavior: contain; }
.mobile-context-actions, .drawer-backdrop, .drawer-close { display: none; }
```

在 `max-width: 1180px` 断点起隐藏非打开状态的队列和证据栏；在 `max-width: 900px` 让 `.workbench-shell` 仅有一列，显示 `.mobile-context-actions`，并用 `.queue-panel.is-mobile-open` 与 `.evidence-panel.is-mobile-open` 作为 `position: absolute; inset: 0; z-index: 3; display: grid;` 的覆盖层。`drawer-backdrop` 为 `position: absolute; inset: 0; z-index: 2;`，只负责点击关闭。抽屉内容自身使用 `min-height: 0` 和 `overflow-y: auto`。

- [ ] **Step 5: 运行工作台测试和构建**

Run: `Push-Location services/support-console; npm test -- --run src/components/Workbench.test.tsx src/layout.contract.test.ts; npm run build; Pop-Location`

Expected: 人工回复闭环、队列状态切换、抽屉开闭与 CSS 合同均通过；构建成功。

- [ ] **Step 6: 提交工作台滚动任务**

```powershell
git add services/support-console/src/components/Workbench.tsx services/support-console/src/components/EvidencePanel.tsx services/support-console/src/components/Workbench.test.tsx services/support-console/src/styles.css services/support-console/src/layout.contract.test.ts
git commit -m "feat: isolate workbench scrolling and mobile drawers"
```

## Task 3: 训练中心移动主题抽屉与编辑器主滚动区

**Files:**
- Modify: `services/support-console/src/components/TrainingCenter.tsx`
- Modify: `services/support-console/src/components/TrainingCenter.test.tsx`
- Modify: `services/support-console/src/styles.css`
- Modify: `services/support-console/src/layout.contract.test.ts`

**Interfaces:**
- Consumes: 现有 `TrainingApi`、主题列表及编辑器表单状态。
- Produces: `topicDrawerOpen: boolean`；“主题列表”与“关闭主题列表”可访问按钮；`.training-editor` 为该页唯一主数据滚动区。

- [ ] **Step 1: 写失败的主题抽屉测试与样式合同**

```tsx
it("opens and closes the training-topic drawer without leaving the editor", async () => {
  const user = userEvent.setup();
  render(<TrainingCenter api={api} />);
  await user.click(screen.getByRole("button", { name: "主题列表" }));
  expect(screen.getByRole("dialog", { name: "主题列表" })).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "关闭主题列表" }));
  expect(screen.queryByRole("dialog", { name: "主题列表" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "AI 训练中心" })).toBeVisible();
});
```

在 `layout.contract.test.ts` 添加：

```ts
expect(stylesheet).toMatch(/\.training-shell\s*\{[^}]*height:\s*100%[^}]*min-height:\s*0[^}]*overflow:\s*hidden/s);
expect(stylesheet).toMatch(/\.training-editor\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `Push-Location services/support-console; npm test -- --run src/components/TrainingCenter.test.tsx src/layout.contract.test.ts; Pop-Location`

Expected: 找不到主题列表移动入口、dialog 和训练区样式合同。

- [ ] **Step 3: 实现主题抽屉和受控编辑器滚动**

在 `TrainingCenter` 加入：

```tsx
const [topicDrawerOpen, setTopicDrawerOpen] = useState(false);

<button className="mobile-topic-toggle secondary-action" aria-expanded={topicDrawerOpen}
  onClick={() => setTopicDrawerOpen(true)}>主题列表</button>
<aside className={`topic-list-panel ${topicDrawerOpen ? "is-mobile-open" : ""}`}
  role={topicDrawerOpen ? "dialog" : undefined}
  aria-modal={topicDrawerOpen || undefined}
  aria-label="主题列表">
  <button className="drawer-close" aria-label="关闭主题列表" onClick={() => setTopicDrawerOpen(false)}>关闭</button>
  {/* 保留现有新建主题和 topic-list 内容；选择主题后额外 setTopicDrawerOpen(false) */}
</aside>
```

添加移动专用遮罩，并为主题选择回调写成 `onClick={() => { void loadDetail(topic.id); setTopicDrawerOpen(false); }}`。样式必须包含：

```css
.training-shell { min-width: 0; min-height: 0; height: 100%; overflow: hidden; display: grid; grid-template-columns: 270px minmax(0, 1fr); }
.topic-list-panel { min-width: 0; min-height: 0; overflow: hidden; display: grid; grid-template-rows: auto auto minmax(0, 1fr); }
.topic-list { min-height: 0; overflow-y: auto; }
.training-editor { min-width: 0; min-height: 0; overflow-y: auto; overscroll-behavior: contain; }
```

在窄屏断点把 `.topic-list-panel` 默认移出普通布局，仅 `.is-mobile-open` 作为覆盖层显示；`.training-editor` 始终保持单列的可用高度。

- [ ] **Step 4: 运行训练测试和构建**

Run: `Push-Location services/support-console; npm test -- --run src/components/TrainingCenter.test.tsx src/layout.contract.test.ts; npm run build; Pop-Location`

Expected: 主题创建/预览既有闭环、主题抽屉开闭和滚动合同均通过；构建成功。

- [ ] **Step 5: 提交训练中心任务**

```powershell
git add services/support-console/src/components/TrainingCenter.tsx services/support-console/src/components/TrainingCenter.test.tsx services/support-console/src/styles.css services/support-console/src/layout.contract.test.ts
git commit -m "feat: make training editor scroll within fixed shell"
```

## Task 4: 仓库级布局检查、容器回归与浏览器验收

**Files:**
- Create: `tests/ui/verify_fixed_shell_layout.mjs`
- Modify: `scripts/verify.ps1`
- Modify: `docs/design-qa.md`

**Interfaces:**
- Consumes: `services/support-console/src/styles.css` 和运行中的 `http://localhost:4173`。
- Produces: `OK fixed-shell source contract verified`，并记录桌面、右栏、窄屏抽屉与 200 条消息的浏览器验收结果。

- [ ] **Step 1: 运行不存在的仓库级布局检查并确认失败**

Run: `node tests/ui/verify_fixed_shell_layout.mjs`

Expected: Node 以 `ERR_MODULE_NOT_FOUND` 退出，因为布局检查脚本尚未创建。

- [ ] **Step 2: 写仓库级 CSS 合同脚本**

```js
import { readFile } from "node:fs/promises";

const stylesheet = await readFile(new URL("../../services/support-console/src/styles.css", import.meta.url), "utf8");
const required = [
  /html,\s*body,\s*#root\s*\{[^}]*height:\s*100%[^}]*overflow:\s*hidden/s,
  /\.app-frame\s*\{[^}]*height:\s*100dvh[^}]*overflow:\s*hidden/s,
  /\.message-stream\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s,
  /\.evidence-panel\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s,
  /safe-area-inset-bottom/,
];
for (const matcher of required) if (!matcher.test(stylesheet)) throw new Error(`missing fixed-shell rule: ${matcher}`);
console.log("OK fixed-shell source contract verified");
```

- [ ] **Step 3: 将检查加入全量验证**

在 `scripts/verify.ps1` 中已有 `node tests/ui/verify_support_console_ui.mjs` 成功检查后加入：

```powershell
& node tests/ui/verify_fixed_shell_layout.mjs
if ($LASTEXITCODE -ne 0) { throw "Verification script failed: tests/ui/verify_fixed_shell_layout.mjs" }
```

- [ ] **Step 4: 运行自动化回归**

Run: `node tests/ui/verify_fixed_shell_layout.mjs; Push-Location services/support-console; npm test -- --run; npm run build; Pop-Location; docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml config; powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env`

Expected: 新脚本输出 `OK fixed-shell source contract verified`；前端测试、构建、Compose 配置和全量验证均退出码 0。

- [ ] **Step 5: 用应用内浏览器执行真实滚动验收**

1. 打开 `http://localhost:4173`，在宽度不少于 1440px 的视口截图，记录顶栏、左导航、输入框和商品卡的矩形。
2. 使用以下 PowerShell 先创建并领取一条隔离的模拟会话，再向同一会话连续提交 200 条人工回复；刷新页面后将消息流滚动到底和回到顶部。比较记录的矩形，确认窗口滚动位置为 0，只有 `.message-stream` 的内容改变。

```powershell
$suffix = [Guid]::NewGuid().ToString("N")
$created = Invoke-RestMethod -Method Post -ContentType "application/json" -Uri "http://localhost:8010/api/agent/reply" -Body (@{ conversation_id = "layout-$suffix"; customer_id = "layout-customer-$suffix"; platform = "simulated-ecommerce"; user_message = "I need a refund and a human agent" } | ConvertTo-Json)
$handoffId = [string]$created.handoff_id
Invoke-RestMethod -Method Post -Uri "http://localhost:8010/api/console/handoffs/$handoffId/claim" | Out-Null
1..200 | ForEach-Object {
  Invoke-RestMethod -Method Post -ContentType "application/json" -Uri "http://localhost:8010/api/console/handoffs/$handoffId/reply" -Body (@{ content = "Layout verification message $_"; role = "support_agent" } | ConvertTo-Json) | Out-Null
}
```
3. 在右侧证据栏滚动到底，确认仅该栏内容移动，消息流位置不变；截取一张证据栏滚动后的截图。
4. 将视口设为 390px 宽，确认回复输入框仍在动态视口内。分别打开并关闭“会话列表”“客户信息”和训练中心的“主题列表”，确认它们覆盖而不挤压主内容。
5. 将验收结果、视口尺寸、验证时间和截图路径写入 `docs/design-qa.md` 的“固定壳层回归”小节。

- [ ] **Step 6: 提交验证任务**

```powershell
git add tests/ui/verify_fixed_shell_layout.mjs scripts/verify.ps1 docs/design-qa.md
git commit -m "test: verify fixed support console shell"
```

## Plan Self-Review

- **规格覆盖：** Task 1 锁定根、壳层与审计页；Task 2 实现桌面三栏、固定输入框、消息/证据独立滚动及工作台移动抽屉；Task 3 实现训练页的内部滚动和移动抽屉；Task 4 覆盖源代码合同、Compose、核心 HTTP、前端构建与真实浏览器四项验收。
- **占位检查：** 计划没有待定项；各任务提供了明确文件、断言、命令、预期结果和提交边界。
- **接口一致性：** 抽屉只使用 `mobilePanel` 或 `topicDrawerOpen` 前端局部状态，继续复用 `WorkbenchApi`、`TrainingApi`、`HandoffDetail` 和既有请求接口，不引入后端契约变化。
