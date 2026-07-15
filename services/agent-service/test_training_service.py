import unittest

from training_service import (
    MAX_ASSET_BYTES,
    asset_type_for_filename,
    next_publish_state,
    preview_training,
    validate_asset,
)


class TrainingServiceTests(unittest.TestCase):
    def test_sensitive_refund_request_always_requires_handoff(self) -> None:
        topic = {"trigger_phrases": ["退款"], "reply_text": "已收到退款请求"}

        result = preview_training(topic, "我要退款并赔偿")

        self.assertTrue(result["handoff_required"])
        self.assertFalse(result["matched"])
        self.assertIn("人工客服", str(result["reply"]))

    def test_rejects_unsupported_asset_extension(self) -> None:
        self.assertEqual(
            validate_asset("invoice.exe", "application/octet-stream", 1),
            "unsupported_file_type",
        )

    def test_rejects_asset_larger_than_limit(self) -> None:
        self.assertEqual(
            validate_asset("product.png", "image/png", MAX_ASSET_BYTES + 1),
            "asset_too_large",
        )

    def test_empty_trigger_phrase_does_not_match_every_query(self) -> None:
        result = preview_training(
            {"trigger_phrases": [""], "reply_text": "通用答复"},
            "请问今天能发货吗",
        )

        self.assertFalse(result["matched"])
        self.assertFalse(result["handoff_required"])

    def test_valid_asset_and_type_are_accepted(self) -> None:
        self.assertIsNone(validate_asset("guide.MD", "text/markdown", 10))
        self.assertEqual(asset_type_for_filename("guide.MD"), "text")
        self.assertEqual(asset_type_for_filename("product.webp"), "image")
        self.assertEqual(asset_type_for_filename("demo.mp4"), "video")

    def test_publish_state_transitions_are_explicit(self) -> None:
        self.assertEqual(next_publish_state("draft"), "published")
        self.assertEqual(next_publish_state("published"), "superseded")
        self.assertEqual(next_publish_state("rolled_back"), "published")
        with self.assertRaises(ValueError):
            next_publish_state("archived")


if __name__ == "__main__":
    unittest.main()
