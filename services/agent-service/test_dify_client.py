import json
import unittest

import httpx

from dify_client import DifyChatClient, DifyClientConfig, DifyStructuredResponseError


class DifyChatClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_chat_parses_the_customer_service_contract(self) -> None:
        observed: dict[str, object] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            observed["authorization"] = request.headers.get("Authorization")
            observed["body"] = json.loads(request.content)
            return httpx.Response(
                200,
                json={
                    "answer": json.dumps(
                        {
                            "reply": "Order ORD-DBTEST is being shipped.",
                            "handoff_required": False,
                            "handoff_reason": "",
                            "used_tool": True,
                            "used_knowledge": False,
                        }
                    ),
                    "conversation_id": "dify-conversation-1",
                    "message_id": "dify-message-1",
                    "metadata": {"usage": {"total_tokens": 12}},
                },
            )

        client = DifyChatClient(
            DifyClientConfig(
                enabled=True,
                api_url="http://dify-api:5001/v1/chat-messages",
                api_key="test-api-key",
                timeout_seconds=5.0,
            ),
            transport=httpx.MockTransport(handler),
        )

        result = await client.chat(
            query="Where is ORD-DBTEST?",
            user="business-conversation-id",
            inputs={"platform": "simulated-ecommerce", "role": "support_agent"},
        )

        self.assertEqual("Bearer test-api-key", observed["authorization"])
        self.assertEqual("blocking", observed["body"]["response_mode"])
        self.assertEqual("Where is ORD-DBTEST?", observed["body"]["query"])
        self.assertEqual("Order ORD-DBTEST is being shipped.", result.reply)
        self.assertTrue(result.used_tool)
        self.assertEqual("dify-conversation-1", result.conversation_id)

    async def test_chat_rejects_an_unstructured_answer(self) -> None:
        def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"answer": "plain text is not an accepted contract"})

        client = DifyChatClient(
            DifyClientConfig(
                enabled=True,
                api_url="http://dify-api:5001/v1/chat-messages",
                api_key="test-api-key",
                timeout_seconds=5.0,
            ),
            transport=httpx.MockTransport(handler),
        )

        with self.assertRaises(DifyStructuredResponseError):
            await client.chat(query="test", user="business-conversation-id", inputs={})

    async def test_chat_marks_knowledge_tool_usage_as_tool_usage(self) -> None:
        def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200,
                json={
                    "answer": json.dumps(
                        {
                            "reply": "Shipping policy found.",
                            "handoff_required": False,
                            "handoff_reason": "",
                            "used_tool": False,
                            "used_knowledge": True,
                        }
                    )
                },
            )

        client = DifyChatClient(
            DifyClientConfig(
                enabled=True,
                api_url="http://dify-api:5001/v1/chat-messages",
                api_key="test-api-key",
            ),
            transport=httpx.MockTransport(handler),
        )

        result = await client.chat(query="What is the shipping policy?", user="conversation-1", inputs={})

        self.assertTrue(result.used_knowledge)
        self.assertTrue(result.used_tool)


if __name__ == "__main__":
    unittest.main()
