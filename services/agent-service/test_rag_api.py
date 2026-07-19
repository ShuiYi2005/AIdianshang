import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app, rag_service


class RagApiTests(unittest.TestCase):
    def test_status_exposes_model_cache_and_last_sync(self) -> None:
        payload = {
            "mode": "hybrid",
            "model_name": "BAAI/bge-small-zh-v1.5",
            "model_cache_status": "ready",
            "weaviate_status": "ready",
            "index_status": "ready",
            "last_sync": None,
            "document_count": 0,
            "chunk_count": 0,
        }
        with patch.object(rag_service, "status", return_value=payload):
            response = TestClient(app).get("/api/rag/status")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["model_cache_status"], "ready")

    def test_reindex_returns_an_accepted_job(self) -> None:
        with patch.object(rag_service, "start_reindex", return_value={"sync_job_id": "job-1", "status": "running", "accepted": True}):
            response = TestClient(app).post("/api/rag/reindex")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.json()["sync_job_id"], "job-1")

    def test_search_reports_keyword_fallback(self) -> None:
        result = {
            "results": [],
            "retrieval_mode": "keyword_fallback",
            "fallback_reason": "weaviate_unavailable",
            "index_status": "degraded",
        }
        with patch.object(rag_service, "search", return_value=type("Response", (), {"as_dict": lambda self: result})()):
            response = TestClient(app).post("/api/rag/search", json={"query": "坏了可以退吗", "limit": 3})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["retrieval_mode"], "keyword_fallback")


if __name__ == "__main__":
    unittest.main()
