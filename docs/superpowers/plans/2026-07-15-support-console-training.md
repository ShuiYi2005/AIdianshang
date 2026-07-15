# AI 客服工作台与训练中心 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 交付独立 React 客服运营后台，使客服工作台和 AI 训练中心通过 agent-service、PostgreSQL、素材卷和模拟渠道形成可验证闭环。

**Architecture:** 新增 support-console React/Vite 服务，浏览器通过带 CORS 白名单的 agent-service API 访问业务能力。业务写入拆为 console_repository.py、training_service.py 和两个 FastAPI router；数据库迁移保存训练版本、素材与控制台审计。真实渠道与多模态模型缺失时使用安全的模拟发送或人工接管，不伪造外部执行。

**Tech Stack:** React 18、TypeScript、Vite、Vitest、FastAPI、Pydantic v2、psycopg 3、PostgreSQL 16、Docker Compose、PowerShell HTTP 验证。

## Global Constraints

- 不修改 platform/、Dify 或 n8n 源码。
- 业务代码仅放在 services/；部署配置仅放在 deployment/；工作流不承载业务计算。
- 前端运行在 http://localhost:4173；API 保持在 http://localhost:8010。
- 退款、赔偿、投诉、身份核验和无法理解的客户附件必须转人工；训练主题不能绕过此策略。
- 没有真实电商 Adapter 时，人工发送写入本地模拟渠道、会话消息与审计。
- 上传文件仅允许 txt、md、png、jpg、jpeg、webp、mp4，单文件不超过 16 MB，保存到 Git 忽略的 Docker volume。
- 每个新增函数先有失败测试；完整性结论必须基于新鲜命令输出。

---

## Task 1: 训练与审计数据结构

**Files:**
- Create: deployment/business-db/migrations/20260715_support_console_training.sql
- Create: tests/database/verify_support_console_training_schema.ps1
- Modify: scripts/apply-business-migrations.ps1

**Interfaces:**
- Produces: knowledge.training_topics、knowledge.training_assets、knowledge.training_versions、audit.console_action_logs。
- Consumed by: Task 2 和 Task 3。

- [ ] **Step 1: 写失败 schema 验证**

    $requiredTables = @('knowledge.training_topics', 'knowledge.training_assets', 'knowledge.training_versions', 'audit.console_action_logs')
    $tables = docker exec ai20-business-db-1 psql -U app_user -d app_business -t -A -c "select table_schema || '.' || table_name from information_schema.tables;"
    foreach ($table in $requiredTables) {
      if ($tables -notcontains $table) { throw "Missing required table: $table" }
    }

- [ ] **Step 2: 观察 RED**

Run: powershell -ExecutionPolicy Bypass -File tests/database/verify_support_console_training_schema.ps1  
Expected: Missing required table: knowledge.training_topics.

- [ ] **Step 3: 写最小迁移**

    CREATE TABLE IF NOT EXISTS knowledge.training_topics (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id uuid REFERENCES core.tenants(id) ON DELETE CASCADE,
      name varchar(128) NOT NULL,
      trigger_phrases text[] NOT NULL DEFAULT ARRAY[]::text[],
      reply_text text NOT NULL,
      store_scope varchar(128) NOT NULL DEFAULT 'simulated-store',
      product_scope varchar(128) NOT NULL DEFAULT 'all-products',
      channel varchar(64) NOT NULL DEFAULT 'simulated-ecommerce',
      status varchar(32) NOT NULL DEFAULT 'draft',
      current_version integer NOT NULL DEFAULT 0 CHECK (current_version >= 0),
      metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT training_topics_status_check CHECK (status IN ('draft', 'published', 'archived'))
    );

Create assets with topic foreign key, relative storage path, MIME type, byte size and description. Create versions with unique topic/version and states published, superseded, rolled_back. Create audit table with action, actor role, target, trace ID and JSON details.

- [ ] **Step 4: Apply and verify GREEN**

Run:

    powershell -ExecutionPolicy Bypass -File scripts/apply-business-migrations.ps1 -EnvFile deployment/env/local.env
    powershell -ExecutionPolicy Bypass -File tests/database/verify_support_console_training_schema.ps1

Expected: migration is recorded once and schema script prints OK support-console training schema verified.

- [ ] **Step 5: Commit**

    git add deployment/business-db/migrations/20260715_support_console_training.sql tests/database/verify_support_console_training_schema.ps1 scripts/apply-business-migrations.ps1
    git commit -m "feat: add support console training schema"

## Task 2: 训练安全规则和素材校验

**Files:**
- Create: services/agent-service/training_service.py
- Create: services/agent-service/test_training_service.py

**Interfaces:**
- Produces: validate_asset(filename, content_type, content_length), preview_training(topic, query), next_publish_state(status)。
- Consumed by: Task 4。

- [ ] **Step 1: 写失败单元测试**

    from training_service import preview_training, validate_asset

    def test_sensitive_refund_request_always_requires_handoff() -> None:
        topic = {"trigger_phrases": ["退款"], "reply_text": "已收到"}
        result = preview_training(topic, "我要退款并赔偿")
        assert result["handoff_required"] is True
        assert result["matched"] is False

    def test_rejects_unsupported_asset_extension() -> None:
        assert validate_asset("invoice.exe", "application/octet-stream", 1) == "unsupported_file_type"

- [ ] **Step 2: 观察 RED**

Run: Push-Location services/agent-service; python -m unittest test_training_service.py; Pop-Location  
Expected: ModuleNotFoundError: No module named training_service.

- [ ] **Step 3: 实现最小安全规则**

    SENSITIVE_TERMS = ("退款", "赔偿", "投诉", "身份核验", "refund", "compensation", "complaint")
    ALLOWED_EXTENSIONS = {".txt", ".md", ".png", ".jpg", ".jpeg", ".webp", ".mp4"}
    MAX_ASSET_BYTES = 16 * 1024 * 1024

    def preview_training(topic: dict[str, object], query: str) -> dict[str, object]:
        if any(term in query.lower() for term in SENSITIVE_TERMS):
            return {"matched": False, "handoff_required": True, "reply": "该请求需要人工客服核验后处理。"}
        phrases = [str(item).lower() for item in topic["trigger_phrases"]]
        matched = any(phrase and phrase in query.lower() for phrase in phrases)
        return {"matched": matched, "handoff_required": False, "reply": topic["reply_text"] if matched else "未命中训练主题。"}

- [ ] **Step 4: 验证 GREEN**

Add max-size-plus-one, empty phrase, publish and rollback cases.  
Run: Push-Location services/agent-service; python -m unittest test_training_service.py; Pop-Location  
Expected: OK.

- [ ] **Step 5: Commit**

    git add services/agent-service/training_service.py services/agent-service/test_training_service.py
    git commit -m "feat: add safe training policy helpers"

## Task 3: 客服工作台 API 和持久化

**Files:**
- Create: services/agent-service/console_repository.py
- Create: services/agent-service/console_api.py
- Modify: services/agent-service/main.py
- Create: tests/services/verify_support_console_training.ps1

**Interfaces:**
- Produces: GET /api/console/queue, GET /api/console/handoffs/{id}, POST /claim, POST /reply, POST /ticket, POST /resolve。
- Consumes: repository.connection(), support.handoff_queue, support.messages, support.tickets。

- [ ] **Step 1: 写失败服务测试**

    $queue = Invoke-RestMethod 'http://localhost:8010/api/console/queue?status=pending'
    if ($null -eq $queue.items) { throw 'console queue response is missing items' }
    $reply = Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "http://localhost:8010/api/console/handoffs/$handoffId/reply" -Body (@{content='已为您核实，稍后回复'; role='support_agent'} | ConvertTo-Json)
    if ($reply.delivery_status -ne 'simulated_sent') { throw 'console reply did not enter simulated channel' }

- [ ] **Step 2: 观察 RED**

Run: powershell -ExecutionPolicy Bypass -File tests/services/verify_support_console_training.ps1 -Phase Console  
Expected: HTTP 404 at /api/console/queue.

- [ ] **Step 3: 实现 router 和 repository**

    def claim_handoff(handoff_id: str) -> dict[str, Any] | None:
        return update_handoff_status(handoff_id, "pending", "assigned")

    def add_human_reply(handoff_id: str, content: str, trace_id: str) -> dict[str, Any] | None:
        return persist_simulated_human_reply(handoff_id, content, trace_id)

    def create_ticket(handoff_id: str, subject: str, description: str) -> dict[str, Any] | None:
        return persist_handoff_ticket(handoff_id, subject, description)

    def resolve_console_handoff(handoff_id: str) -> bool:
        return update_handoff_status(handoff_id, "assigned", "resolved") is not None

    @router.post("/handoffs/{handoff_id}/reply")
    def reply_to_handoff(handoff_id: str, payload: ConsoleReplyRequest, x_trace_id: str | None = Header(default=None)) -> dict[str, Any]:
        result = add_human_reply(handoff_id, payload.content.strip(), trace_from_header(x_trace_id))
        if result is None:
            raise HTTPException(status_code=404, detail="handoff_not_found")
        return {"message": result, "delivery_status": "simulated_sent"}

The transaction inserts a human message, changes the conversation to human_handling and inserts audit.console_action_logs. It never calls an external channel.
Main adds CORSMiddleware with allow_origins containing only http://localhost:4173 for this local console.

- [ ] **Step 4: 验证 GREEN**

Run: powershell -ExecutionPolicy Bypass -File tests/services/verify_support_console_training.ps1 -Phase Console  
Expected: script creates a handoff, lists it, claims it, writes a reply, creates a ticket, resolves it and reads matching rows.

- [ ] **Step 5: Commit**

    git add services/agent-service/console_repository.py services/agent-service/console_api.py services/agent-service/main.py tests/services/verify_support_console_training.ps1
    git commit -m "feat: add support console API"

## Task 4: AI 训练 API、素材、发布和回滚

**Files:**
- Create: services/agent-service/training_api.py
- Modify: services/agent-service/console_repository.py
- Modify: services/agent-service/main.py
- Modify: services/agent-service/requirements.txt
- Modify: deployment/docker-compose.yml
- Modify: .gitignore
- Modify: tests/services/verify_support_console_training.ps1

**Interfaces:**
- Produces: training topics CRUD, assets, preview, publish and rollback endpoints.
- Consumes: Tasks 1–2。

- [ ] **Step 1: 写失败服务测试**

    $topic = Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri 'http://localhost:8010/api/training/topics' -Body (@{name='售后指引'; trigger_phrases=@('怎么退货'); reply_text='请先提交售后申请'; store_scope='simulated-store'; product_scope='all-products'; channel='simulated-ecommerce'} | ConvertTo-Json)
    $preview = Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "http://localhost:8010/api/training/topics/$($topic.id)/preview" -Body (@{query='怎么退货'} | ConvertTo-Json)
    if ($preview.matched -ne $true) { throw 'training preview did not match trigger phrase' }

- [ ] **Step 2: 观察 RED**

Run: powershell -ExecutionPolicy Bypass -File tests/services/verify_support_console_training.ps1 -Phase Training  
Expected: HTTP 404 at /api/training/topics.

- [ ] **Step 3: 实现受限上传和版本状态**

    @router.post("/topics/{topic_id}/assets")
    async def upload_training_asset(topic_id: str, file: UploadFile, description: str = Form(default="")) -> dict[str, Any]:
        body = await file.read(MAX_ASSET_BYTES + 1)
        validation = validate_asset(file.filename or "", file.content_type or "", len(body))
        if validation:
            raise HTTPException(status_code=400, detail=validation)
        stored_path = store_training_asset(topic_id, file.filename or "asset", body)
        return create_training_asset(topic_id, file.filename or "asset", file.content_type or "", len(body), stored_path, description)

Use TRAINING_ASSET_ROOT=/app/training-assets. Reject path traversal. Mount training_assets:/app/training-assets only in agent-service. Publishing creates the next immutable version; rollback restores a selected historical version and writes an audit row.
Add python-multipart==0.0.12 to requirements.txt before importing UploadFile and Form.

- [ ] **Step 4: 验证 GREEN**

Run: powershell -ExecutionPolicy Bypass -File tests/services/verify_support_console_training.ps1 -Phase Training  
Expected: script creates topic, rejects exe, uploads allowed media, previews normal query, hands off refund query, publishes version 1, rolls it back and finds audit rows.

- [ ] **Step 5: Commit**

    git add services/agent-service/training_api.py services/agent-service/console_repository.py services/agent-service/main.py deployment/docker-compose.yml .gitignore tests/services/verify_support_console_training.ps1
    git commit -m "feat: add training center API and asset lifecycle"

## Task 5: 独立 React 控制台和组件测试

**Files:**
- Create: services/support-console/package.json
- Create: services/support-console/vite.config.ts
- Create: services/support-console/tsconfig.json
- Create: services/support-console/Dockerfile
- Create: services/support-console/server.mjs
- Create: services/support-console/src/main.tsx
- Create: services/support-console/src/App.tsx
- Create: services/support-console/src/api.ts
- Create: services/support-console/src/types.ts
- Create: services/support-console/src/styles.css
- Create: services/support-console/src/App.test.tsx
- Create: services/support-console/src/components/Workbench.tsx
- Create: services/support-console/src/components/TrainingCenter.tsx
- Create: services/support-console/src/components/EvidencePanel.tsx
- Create: services/support-console/src/components/TrainingCenter.test.tsx

**Interfaces:**
- Produces: routes /, /training, /audit and ConsoleApi.
- Consumes: Tasks 3–4 API contracts.

- [ ] **Step 1: 写失败 UI 测试**

    it("switches from the workbench to AI training", async () => {
      render(<App api={fakeApi} />)
      await userEvent.click(screen.getByRole("button", { name: "AI 训练" }))
      expect(screen.getByRole("heading", { name: "AI 训练中心" })).toBeInTheDocument()
    })

    it("sends a human reply and renders simulated delivery status", async () => {
      render(<Workbench api={fakeApi} />)
      await userEvent.type(screen.getByLabelText("人工回复"), "我正在核实")
      await userEvent.click(screen.getByRole("button", { name: "发送回复" }))
      expect(await screen.findByText("模拟渠道已发送")).toBeInTheDocument()
    })

- [ ] **Step 2: 观察 RED**

Run: Push-Location services/support-console; npm test -- --run; Pop-Location  
Expected: command fails because package.json is absent.

- [ ] **Step 3: 实现独立控制台**

    export interface ConsoleApi {
      listQueue(status: "pending" | "assigned"): Promise<QueueResponse>
      detail(id: string): Promise<HandoffDetail>
      claim(id: string): Promise<HandoffDetail>
      reply(id: string, content: string): Promise<ConsoleReply>
      createTicket(id: string, subject: string, description: string): Promise<Ticket>
      resolve(id: string): Promise<{ resolved: boolean }>
      listTopics(): Promise<TrainingTopic[]>
      createTopic(input: TrainingTopicInput): Promise<TrainingTopic>
      previewTopic(id: string, query: string): Promise<TrainingPreview>
      publishTopic(id: string): Promise<TrainingTopic>
      rollbackTopic(id: string, version: number): Promise<TrainingTopic>
    }

Use the reference-inspired five-pane workbench: top bar, nav, queue, conversation and evidence. Use white/gray surfaces, #1d4ed8 primary actions, #b91c1c risk, loading/error/empty text and one-column reflow below 960px. Implement all visible actions: 领取、发送回复、创建工单、解决任务、新建主题、上传素材、预览回复、发布训练、回滚版本. Disable request buttons while pending and retain typed input on failure.

- [ ] **Step 4: 验证 GREEN**

Run: Push-Location services/support-console; npm test -- --run; npm run build; Pop-Location  
Expected: Vitest exits 0 and Vite emits dist/.

- [ ] **Step 5: Commit**

    git add services/support-console
    git commit -m "feat: add React support console"

## Task 6: Docker、浏览器闭环和回归

**Files:**
- Modify: deployment/docker-compose.yml
- Modify: scripts/verify.ps1
- Create: tests/ui/verify_support_console_ui.mjs
- Modify: README.md
- Modify: docs/ARCHITECTURE.md
- Modify: specs/support/agent-workbench.yaml

**Interfaces:**
- Produces: support-console service on port 4173 and a complete verification entry.

- [ ] **Step 1: 写失败页面验证**

    const response = await fetch("http://localhost:4173");
    if (!response.ok) throw new Error("support console is unavailable");
    const html = await response.text();
    for (const label of ["领取", "发送回复", "创建工单", "解决任务", "预览回复", "发布训练", "回滚版本"]) {
      if (!html.includes(label)) throw new Error("missing UI action: " + label);
    }

- [ ] **Step 2: 观察 RED**

Run: node tests/ui/verify_support_console_ui.mjs  
Expected: support console is unavailable.

- [ ] **Step 3: 加入 Compose 服务**

    support-console:
      build:
        context: ../services/support-console
        dockerfile: Dockerfile
      image: ai20-support-console:latest
      pull_policy: never
      depends_on:
        agent-service:
          condition: service_healthy
      environment:
        VITE_AGENT_API_BASE_URL: http://localhost:8010
      ports:
        - "4173:4173"

Add the training_assets named volume and mount it only into agent-service. The frontend must not receive database, Dify or storage credentials.

- [ ] **Step 4: 验证 API 和浏览器闭环**

Run:

    docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d --build business-db db-simulator agent-service support-console
    powershell -ExecutionPolicy Bypass -File tests/services/verify_support_console_training.ps1
    node tests/ui/verify_support_console_ui.mjs

Expected: both test scripts exit 0. Use the in-app browser to click each visible action and confirm corresponding API and persisted result.

- [ ] **Step 5: 完整回归**

Run:

    docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml config
    powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env
    Push-Location services/support-console; npm test -- --run; npm run build; Pop-Location

Expected: Compose config, existing verification, frontend tests and frontend build exit 0.

- [ ] **Step 6: Commit**

    git add deployment/docker-compose.yml scripts/verify.ps1 tests/ui/verify_support_console_ui.mjs README.md docs/ARCHITECTURE.md specs/support/agent-workbench.yaml
    git commit -m "feat: deploy and verify support console"

## Plan Self-Review

- Scope coverage: Task 1 adds durable state; Tasks 2 and 4 enforce safe training; Task 3 closes workbench persistence; Task 5 implements every visible UI action; Task 6 validates deployment and regression.
- Safety: real platform sending and vision inference are replaced with explicit simulation or human handoff.
- Type consistency: ConsoleApi maps one-to-one to Tasks 3 and 4 API routes.
- Verification: every task starts with RED and ends with a concrete GREEN command plus commit boundary.
