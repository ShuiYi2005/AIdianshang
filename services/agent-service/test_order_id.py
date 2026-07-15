import unittest

from main import extract_order_id


class ExtractOrderIdTests(unittest.TestCase):
    def test_extracts_the_expected_platform_order_id(self) -> None:
        self.assertEqual("ORD-DBTEST", extract_order_id("Please check order ORD-DBTEST"))

    def test_does_not_treat_the_word_order_as_an_order_id(self) -> None:
        self.assertIsNone(extract_order_id("Please check order status"))


if __name__ == "__main__":
    unittest.main()
