# 轻量本地向量 RAG 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AI 客服接入 `BAAI/bge-small-zh-v1.5` 的本地 ONNX 向量检索、Weaviate 持久化、可审计同步任务和训练中心的同步操作闭环。

**Architecture:** `agent-service` 使用 FastEmbed 生成 512 维向量，以现有 `httpx` 调用 Weaviate REST/GraphQL，避免引入 Weaviate SDK 版本耦合。PostgreSQL 是文档、版本、切片和同步任务的审计事实源；Weaviate 只保存当前可检索切片及其向量。默认 `hybrid` 模式在向量依赖失败时回退到当前关键词检索，并在响应中明确标识。

**Tech Stack:** Python 3.12、FastAPI、FastEmbed 0.8.0、ONNX Runtime CPU、httpx、psycopg 3、PostgreSQL 16、Weaviate 1.28.5、React 18、TypeScript、Vitest、Docker Compose、PowerShell。

## Global Constraints

- 禁止修改 `platform/`；业务代码只放在 `services/`，部署配置只放在 `deployment/`。
- `workflows/` 不承载 RAG 计算；订单、物流、库存、支付仍只能来自 Tool 或外部 API。
- 仅处理 `knowledge/` 中的 `.md`、`.txt`；发现手机号、身份证号、完整收货地址或 `ORD-...` 订单号即拒绝同步。
- 默认 `RAG_MODE=hybrid`；`vector` 模式不得返回关键词结果，`keyword` 模式不得初始化模型。
- 模型固定为 `BAAI/bge-small-zh-v1.5`、512 维、缓存目录 `/models`，并使用独立 Docker 卷。
- 修改后必须验证 Docker Compose、核心 HTTP 接口和 `scripts/verify.ps1`。

---

### Task 1: 建立 RAG 领域契约、切片与降级规则

**Files:**

- Create: `services/agent-service/rag_types.py`
- Create: `services/agent-service/test_rag.py`
- Modify: `services/agent-service/rag.py`

**Interfaces:**

- `RagSettings.from_environment(env: Mapping[str, str] | None = None) -> RagSettings`
- `split_document(content: str, chunk_size: int = 800, overlap: int = 120) -> list[str]`
- `contains_restricted_pii(content: str) -> bool`
- `RagSearchResult.as_dict() -> dict[str, object]`
- 保持 `search_knowledge(query: str, limit: int = 3) -> list[dict[str, object]]` 调用兼容。

- [ ] **Step 1: 写入会失败的纯逻辑测试**

```python
class RagTests(unittest.TestCase):
    def test_hybrid_is_the_default_mode(self):
        self.assertEqual(RagSettings.from_environment({}).mode, "hybrid")

    def test_chunker_keeps_overlap(self):
        chunks = split_document("a" * 950, chunk_size=800, overlap=120)
        self.assertEqual(chunks[0][-120:], chunks[1][:120])

    def test_rejects_pii_and_order_numbers(self):
        self.assertTrue(contains_restricted_pii("电话 13800138000"))
        self.assertTrue(contains_restricted_pii("订单 ORD-TEST001"))
        self.assertFalse(contains_restricted_pii("质量问题支持七天退换"))
```

- [ ] **Step 2: 确认测试因契约不存在而失败**

Run: `python -m unittest services/agent-service/test_rag.py -v`

Expected: FAIL，缺少 `rag_types` 与新增函数。

- [ ] **Step 3: 最小实现**

在 `rag_types.py` 使用冻结 dataclass 定义 `mode: Literal["hybrid", "vector", "keyword"]`、模型名、缓存路径、Weaviate URL、自动索引标志；非法模式抛出 `ValueError`。在 `rag.py` 添加 800/120 窗口切片和 PII 正则；不改动原关键词评分算法，只为其结果补 `retrieval_mode="keyword"`。

- [ ] **Step 4: 验证并提交**

Run: `python -m unittest services/agent-service/test_rag.py -v`

Expected: PASS。

```powershell
git add services/agent-service/rag.py services/agent-service/rag_types.py services/agent-service/test_rag.py
git commit -m "feat: add rag retrieval contracts"
```

### Task 2: 实现 ONNX 向量、Weaviate 与同步元数据服务

**Files:**

- Create: `services/agent-service/rag_vector.py`
- Create: `services/agent-service/rag_repository.py`
- Create: `services/agent-service/rag_service.py`
- Create: `services/agent-service/test_rag_vector.py`
- Modify: `services/agent-service/requirements.txt`

**Interfaces:**

- `FastEmbedder.embed_documents(texts: list[str]) -> list[list[float]]`
- `FastEmbedder.embed_query(query: str) -> list[float]`
- `WeaviateKnowledgeStore.ensure_schema()`, `upsert_chunks()`, `search()`, `delete_document_versions()`
- `RagRepository.start_sync_job()`, `complete_sync_job()`, `fail_sync_job()`, `upsert_document_version()`, `replace_chunks()`, `latest_sync_status()`
- `RagService.reindex() -> RagIndexStatus` 与 `RagService.search(query: str, limit: int) -> RagSearchResponse`

- [ ] **Step 1: 写入会失败的向量服务测试**

```python
class FakeEmbedder:
    def embed_documents(self, texts): return [[0.0] * 512 for _ in texts]
    def embed_query(self, text): return [0.0] * 512

def test_reindex_marks_success_and_writes_vectors(self):
    service = RagService(RagSettings(mode="vector"), FakeEmbedder(), FakeStore(), FakeRepository(), knowledge_root=fixture_root())
    status = service.reindex()
    self.assertEqual(status.status, "succeeded")
    self.assertEqual(status.chunk_count, 1)

def test_hybrid_returns_machine_readable_fallback(self):
    service = RagService(RagSettings(mode="hybrid"), RaisingEmbedder(), FakeStore(), FakeRepository(), keyword_search=fixture_keyword_search)
    result = service.search("坏了可以退吗", 3)
    self.assertEqual(result.retrieval_mode, "keyword_fallback")
    self.assertEqual(result.fallback_reason, "embedding_unavailable")

def test_vector_mode_never_silently_falls_back(self):
    with self.assertRaises(RagDependencyError):
        RagService(RagSettings(mode="vector"), RaisingEmbedder(), FakeStore(), FakeRepository()).search("坏了可以退吗", 3)
```

- [ ] **Step 2: 确认新测试失败**

Run: `python -m unittest services/agent-service/test_rag_vector.py -v`

Expected: FAIL，缺少 `RagService`、向量适配器及异常类型。

- [ ] **Step 3: 最小实现向量与元数据边界**

在 requirements 追加唯一新依赖：

```text
fastembed==0.8.0
```

```python
class FastEmbedder:
    def __init__(self, settings: RagSettings) -> None:
        self._model = TextEmbedding(model_name=settings.model_name, cache_dir=settings.cache_path)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        vectors = [item.tolist() for item in self._model.passage_embed(texts)]
        validate_vector_dimensions(vectors, expected=512)
        return vectors

    def embed_query(self, query: str) -> list[float]:
        vector = next(self._model.query_embed(query)).tolist()
        validate_vector_dimensions([vector], expected=512)
        return vector
```

`WeaviateKnowledgeStore` 使用 `httpx.Client` 创建 `KnowledgeChunk`（`vectorizer: "none"`），批量写入明确的向量，GraphQL 查询字段为 `sourceUri title content documentVersionId chunkId _additional { distance }`。`RagRepository` 只使用参数化 psycopg SQL：内容哈希相同则跳过重算，内容改变则新增版本、替换切片、写入 `embedding_ref`，并在 `sync_jobs` 记录 `running/succeeded/failed`。同步使用进程锁，重复请求返回同一运行任务。

- [ ] **Step 4: 验证服务、现有后端测试并提交**

Run: `python -m unittest services/agent-service/test_rag.py services/agent-service/test_rag_vector.py services/agent-service/test_dify_client.py services/agent-service/test_order_id.py services/agent-service/test_training_service.py -v`

Expected: PASS，且向量模式和两种降级规则均被测试覆盖。

```powershell
git add services/agent-service/requirements.txt services/agent-service/rag_vector.py services/agent-service/rag_repository.py services/agent-service/rag_service.py services/agent-service/test_rag_vector.py
git commit -m "feat: add lightweight vector rag service"
```

### Task 3: 暴露 API、Docker 模型缓存与端到端验证

**Files:**

- Create: `services/agent-service/test_rag_api.py`
- Modify: `services/agent-service/main.py`
- Modify: `deployment/docker-compose.yml`
- Modify: `deployment/env/local.env.example`
- Modify: `scripts/verify-rag.ps1`
- Modify: `dify-assets/tools/agent-service-rag.openapi.yaml`

**Interfaces:**

- `GET /api/rag/status`
- `POST /api/rag/reindex`（202，返回 `sync_job_id`）
- 扩展 `POST /api/rag/search`：`results`、`retrieval_mode`、`fallback_reason`、`index_status`
- Compose 卷 `embedding_model_cache:/models`

- [ ] **Step 1: 写入路由失败测试**

```python
def test_status_exposes_cache_and_index_state(monkeypatch):
    monkeypatch.setattr("main.rag_service.status", lambda: {"model_cache_status": "ready", "index_status": "ready"})
    response = TestClient(app).get("/api/rag/status")
    assert response.status_code == 200
    assert response.json()["model_cache_status"] == "ready"

def test_reindex_returns_running_job(monkeypatch):
    monkeypatch.setattr("main.rag_service.start_reindex", lambda: {"sync_job_id": "job-1", "status": "running"})
    response = TestClient(app).post("/api/rag/reindex")
    assert response.status_code == 202
    assert response.json()["sync_job_id"] == "job-1"
```

- [ ] **Step 2: 确认失败**

Run: `python -m pytest services/agent-service/test_rag_api.py -q`

Expected: FAIL，缺少 `main.rag_service` 和两个新路由。

- [ ] **Step 3: 接线并配置容器**

在 `main.py` 延迟构造 `RagService`，避免 import 时下载模型；替换直调 `search_knowledge` 的 API 与本地回复路径，完整检索结果进入 `save_context_snapshot`。添加：

```python
@app.get("/api/rag/status")
async def rag_status() -> dict[str, Any]:
    return rag_service.status()

@app.post("/api/rag/reindex", status_code=202)
async def rag_reindex() -> dict[str, Any]:
    return rag_service.start_reindex()
```

在 Compose 顶层声明 `embedding_model_cache`；向 `agent-service` 注入 `RAG_MODE=hybrid`、模型名、缓存路径、`WEAVIATE_URL`、`RAG_AUTO_INDEX=true`，挂载 `embedding_model_cache:/models`，并依赖 Weaviate。同步更新 env 模板、OpenAPI 与验证脚本。验证脚本必须启动 `business-db agent-service weaviate`，触发同步并轮询不超过 180 秒，断言同义问句的响应为 `retrieval_mode=vector` 且包含来源引用；`RAG_MODE=keyword` 时只跳过向量断言。

- [ ] **Step 4: 验证并提交**

Run:

```powershell
python -m pytest services/agent-service/test_rag_api.py -q
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml config
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d --build agent-service business-db weaviate
powershell -ExecutionPolicy Bypass -File scripts/verify-rag.ps1 -EnvFile deployment/env/local.env -ComposeFile deployment/docker-compose.yml
```

Expected: PASS，首次可下载模型并返回真实向量结果，之后重启复用缓存。

```powershell
git add services/agent-service/main.py services/agent-service/test_rag_api.py deployment/docker-compose.yml deployment/env/local.env.example scripts/verify-rag.ps1 dify-assets/tools/agent-service-rag.openapi.yaml
git commit -m "feat: expose vector rag sync and status"
```

### Task 4: 在训练中心实现同步状态、失败重试与移动端闭环

**Files:**

- Modify: `services/support-console/src/types.ts`
- Modify: `services/support-console/src/api.ts`
- Modify: `services/support-console/src/components/TrainingCenter.tsx`
- Modify: `services/support-console/src/components/TrainingCenter.test.tsx`
- Modify: `services/support-console/src/styles.css`

**Interfaces:**

- `RagStatus`：模式、模型、缓存状态、Weaviate 状态、索引状态、文档数、切片数、最近同步。
- `ConsoleApi.getRagStatus()` 与 `ConsoleApi.reindexKnowledge()`。
- 一个在 `.training-editor` 内的 `knowledge-sync-card`。

- [ ] **Step 1: 写入会失败的前端行为测试**

```tsx
it("disables duplicate knowledge sync while a job is running", async () => {
  const api = {
    ...baseApi,
    getRagStatus: vi.fn().mockResolvedValue(readyRagStatus),
    reindexKnowledge: vi.fn().mockResolvedValue({ sync_job_id: "job-1", status: "running" }),
  };
  render(<TrainingCenter api={api} />);
  expect(await screen.findByText("知识库同步")).toBeInTheDocument();
  await userEvent.setup().click(screen.getByRole("button", { name: "立即同步" }));
  expect(api.reindexKnowledge).toHaveBeenCalledOnce();
  expect(screen.getByRole("button", { name: "正在同步" })).toBeDisabled();
});
```

- [ ] **Step 2: 确认测试失败**

Run: `npm test -- --run src/components/TrainingCenter.test.tsx`

Expected: FAIL，API 类型和“知识库同步”按钮均不存在。

- [ ] **Step 3: 最小实现前端状态卡**

新增 `RagStatus` 与 `RagReindexResponse`；在 `apiClient` 调用 `GET /api/rag/status`、`POST /api/rag/reindex`。训练中心挂载时获取状态，按钮发起同步后每两秒轮询；仅在 `ready/failed/degraded` 停止，卸载时清除 interval。卡片显示模式、模型、缓存、Weaviate、最近同步、文档数、切片数与后端错误摘要；失败保留“立即同步”重试入口。只新增 `.knowledge-sync-card` 局部 CSS，保持 `.training-editor` 是唯一训练区滚动容器，窄屏不改变固定壳层。

- [ ] **Step 4: 验证并提交**

Run:

```powershell
npm test -- --run src/components/TrainingCenter.test.tsx src/layout.contract.test.ts
npm run build
node tests/ui/verify_fixed_shell_layout.mjs
```

Expected: PASS，布局契约不回归。

```powershell
git add services/support-console/src/types.ts services/support-console/src/api.ts services/support-console/src/components/TrainingCenter.tsx services/support-console/src/components/TrainingCenter.test.tsx services/support-console/src/styles.css
git commit -m "feat: add knowledge sync console controls"
```

### Task 5: 完成全量验收与真实能力说明

**Files:**

- Modify: `README.md`
- Modify: `docs/CONFIGURATION.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/CHECKLIST.md`
- Modify: `scripts/verify.ps1`

- [ ] **Step 1: 先将语义回归断言加入验证脚本**

```powershell
$semantic = Invoke-RestMethod -Uri "http://localhost:8010/api/rag/search" -Method Post -ContentType "application/json" -Body (@{ query = "商品坏了能退吗"; limit = 3 } | ConvertTo-Json)
if ($semantic.retrieval_mode -ne "vector") { throw "expected vector retrieval, got $($semantic.retrieval_mode)" }
if (!$semantic.results[0].source_uri) { throw "vector result did not contain a source citation" }
```

- [ ] **Step 2: 确认该断言在旧 RAG 上失败**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify-rag.ps1 -EnvFile deployment/env/local.env -ComposeFile deployment/docker-compose.yml`

Expected: 在 Task 3 实现前 FAIL，原响应没有 `retrieval_mode`。

- [ ] **Step 3: 更新运行与能力边界文档**

记录启动、状态与清理命令：

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d --build
Invoke-RestMethod http://localhost:8010/api/rag/status
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml down
docker volume rm ai20_embedding_model_cache
```

明确模型是嵌入模型而非聊天模型；初次 ONNX 缓存约 90 MB；CPU 可用；`keyword_fallback` 是明确的降级状态。不得声称 Dify Chatflow 已发布、已配置模型提供商、已接真实电商平台、已实现 reranking 或多模态语义理解。

- [ ] **Step 4: 执行最终验证**

Run:

```powershell
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml config
docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml up -d --build
python -m unittest services/agent-service/test_rag.py services/agent-service/test_rag_vector.py services/agent-service/test_rag_api.py -v
Push-Location services/support-console; npm test -- --run; npm run build; Pop-Location
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -EnvFile deployment/env/local.env -ComposeFile deployment/docker-compose.yml
git diff --check
git status --short
```

Expected: Docker、后端、前端、语义检索、完整验证脚本和空白检查全部通过。

- [ ] **Step 5: 提交验收文档与脚本**

```powershell
git add README.md docs/CONFIGURATION.md docs/ARCHITECTURE.md docs/CHECKLIST.md scripts/verify.ps1 scripts/verify-rag.ps1
git commit -m "docs: document verified vector rag operation"
```

## Plan Self-Review

- Spec coverage: Tasks 1–3 覆盖模型、缓存、索引、元数据、模式、安全和 API；Task 4 覆盖前端同步与重试；Task 5 覆盖 Compose 验证与透明文档。
- Placeholder scan: 无未完成事项、不明确的延后实现标识或未定义接口。
- Type consistency: 后端统一使用 `RagSettings`、`RagService`、`RagIndexStatus`、`RagSearchResponse`；前端只调用已定义的两个 RAG 接口。
- Scope: 图片/视频向量、reranker、Dify 发布和真实平台 Adapter 明确不在本计划内。
