import tempfile
import unittest
from pathlib import Path

from rag_service import RagDependencyError, RagService
from rag_types import RagSettings
from rag_vector import WeaviateKnowledgeStore
import httpx


class FakeEmbedder:
    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [[0.0] * 512 for _ in texts]

    def embed_query(self, query: str) -> list[float]:
        return [0.0] * 512


class RaisingEmbedder:
    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        raise RagDependencyError("embedding_unavailable")

    def embed_query(self, query: str) -> list[float]:
        raise RagDependencyError("embedding_unavailable")


class FakeStore:
    def __init__(self) -> None:
        self.upserted = []

    def ensure_schema(self) -> None:
        return None

    def upsert_chunks(self, chunks: list[object]) -> None:
        self.upserted.extend(chunks)

    def search(self, vector: list[float], limit: int) -> list[dict[str, object]]:
        return [
            {
                "source_uri": "faq/refund.md",
                "title": "退款规则",
                "content": "质量问题支持退换",
                "distance": 0.02,
                "document_version_id": "version-1",
                "chunk_id": "chunk-1",
            }
        ][:limit]

    def delete_document_versions(self, version_ids: set[str]) -> None:
        return None

    def health(self) -> str:
        return "ready"


class FakeRepository:
    def start_sync_job(self) -> str:
        return "job-1"

    def complete_sync_job(self, job_id: str, result: dict[str, object]) -> None:
        return None

    def fail_sync_job(self, job_id: str, message: str) -> None:
        return None

    def upsert_document_version(self, source_uri: str, title: str, content_hash: str) -> dict[str, object]:
        return {"document_version_id": "version-1", "changed": True, "expired_version_ids": []}

    def replace_chunks(self, document_version_id: str, chunks: list[object]) -> None:
        return None

    def latest_sync_status(self) -> dict[str, object] | None:
        return None

    def counts(self) -> dict[str, int]:
        return {"document_count": 0, "chunk_count": 0}


class FlakyStartRepository(FakeRepository):
    def __init__(self) -> None:
        self.fail_next_start = True

    def start_sync_job(self) -> str:
        if self.fail_next_start:
            self.fail_next_start = False
            raise RuntimeError("database_unavailable")
        return super().start_sync_job()


def keyword_search(query: str, limit: int) -> list[dict[str, object]]:
    return [{"source_uri": "faq/refund.md", "title": "退款规则", "excerpt": "质量问题支持退换"}][:limit]


class RagVectorTests(unittest.TestCase):
    def test_reindex_writes_512_dimension_chunks_and_marks_vector_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "faq.md").write_text("质量问题支持七天退换", encoding="utf-8")
            store = FakeStore()
            service = RagService(
                RagSettings(mode="vector"),
                FakeEmbedder(),
                store,
                FakeRepository(),
                knowledge_root=root,
            )

            status = service.reindex()

        self.assertEqual(status.status, "succeeded")
        self.assertEqual(status.chunk_count, 1)
        self.assertEqual(len(store.upserted[0].vector), 512)

    def test_hybrid_falls_back_with_machine_readable_reason(self) -> None:
        service = RagService(
            RagSettings(mode="hybrid"),
            RaisingEmbedder(),
            FakeStore(),
            FakeRepository(),
            keyword_search=keyword_search,
        )

        response = service.search("坏了可以退吗", 3)

        self.assertEqual(response.retrieval_mode, "keyword_fallback")
        self.assertEqual(response.fallback_reason, "embedding_unavailable")

    def test_vector_mode_never_returns_keyword_results_after_vector_failure(self) -> None:
        service = RagService(RagSettings(mode="vector"), RaisingEmbedder(), FakeStore(), FakeRepository())

        with self.assertRaises(RagDependencyError):
            service.search("坏了可以退吗", 3)

    def test_reindex_releases_lock_when_creating_sync_job_fails(self) -> None:
        service = RagService(RagSettings(mode="vector"), FakeEmbedder(), FakeStore(), FlakyStartRepository())

        with self.assertRaisesRegex(RuntimeError, "database_unavailable"):
            service.reindex()

        self.assertEqual(service.reindex().status, "succeeded")

    def test_status_reports_actual_store_health(self) -> None:
        service = RagService(RagSettings(mode="vector"), FakeEmbedder(), FakeStore(), FakeRepository())

        self.assertEqual(service.status()["weaviate_status"], "ready")

    def test_weaviate_health_returns_unavailable_when_probe_fails(self) -> None:
        store = WeaviateKnowledgeStore("http://weaviate:8080")
        store._client = httpx.Client(transport=httpx.MockTransport(lambda _: (_ for _ in ()).throw(httpx.ConnectError("down"))))

        self.assertEqual(store.health(), "unavailable")


if __name__ == "__main__":
    unittest.main()
