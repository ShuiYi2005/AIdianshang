import unittest

from rag import contains_restricted_pii, split_document
from rag_types import RagSettings


class RagTests(unittest.TestCase):
    def test_hybrid_is_the_default_mode(self) -> None:
        self.assertEqual(RagSettings.from_environment({}).mode, "hybrid")

    def test_invalid_mode_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            RagSettings.from_environment({"RAG_MODE": "automatic"})

    def test_chunker_keeps_the_configured_overlap(self) -> None:
        chunks = split_document("a" * 950, chunk_size=800, overlap=120)

        self.assertEqual(len(chunks), 2)
        self.assertEqual(chunks[0][-120:], chunks[1][:120])

    def test_rejects_phone_address_id_and_order_identifiers(self) -> None:
        self.assertTrue(contains_restricted_pii("请寄到北京市朝阳区，电话 13800138000"))
        self.assertTrue(contains_restricted_pii("身份证号 11010519491231002X"))
        self.assertTrue(contains_restricted_pii("订单 ORD-TEST001 已退款"))
        self.assertFalse(contains_restricted_pii("质量问题支持七天退换"))


if __name__ == "__main__":
    unittest.main()
