import unittest
from contextlib import ExitStack
from unittest.mock import AsyncMock, patch

from main import AgentReplyRequest, agent_reply


class AgentReplyRagOrderingTests(unittest.IsolatedAsyncioTestCase):
    def _persistence_patches(self, stack: ExitStack) -> None:
        stack.enter_context(patch("main.ensure_customer", return_value=None))
        stack.enter_context(patch("main.ensure_conversation", return_value=None))
        stack.enter_context(patch("main.save_context_snapshot", return_value=None))
        stack.enter_context(patch("main.save_message"))
        stack.enter_context(patch("main.save_metric"))
        stack.enter_context(patch("main.save_tool_log"))
        stack.enter_context(patch("main.save_ai_log"))
        stack.enter_context(patch("main.save_cost_event"))
        stack.enter_context(patch("main.enqueue_handoff", return_value="handoff-1"))

    async def test_order_lookup_skips_rag_and_audits_rag_as_unused(self) -> None:
        with ExitStack() as stack:
            self._persistence_patches(stack)
            search = stack.enter_context(patch("main.rag_service.search", side_effect=AssertionError("RAG must not run for an order lookup")))
            audit = stack.enter_context(patch("main.save_ai_log"))
            stack.enter_context(patch("main.published_training_match", return_value=None))
            stack.enter_context(
                patch(
                    "main.call_order_tool",
                    new=AsyncMock(
                        return_value=(
                            {"data": {"order_id": "ORD-DBTEST", "status": "shipped", "logistics_no": "LOG-1"}},
                            1,
                            "success",
                        )
                    ),
                )
            )

            response = await agent_reply(
                AgentReplyRequest(
                    conversation_id="conversation-order",
                    customer_id="customer-order",
                    user_message="请查询订单 ORD-DBTEST",
                )
            )

        search.assert_not_called()
        self.assertEqual(response["retrieval_context"], [])
        self.assertFalse(audit.call_args.kwargs["rag_used"])

    async def test_sensitive_handoff_skips_rag_and_audits_rag_as_unused(self) -> None:
        with ExitStack() as stack:
            self._persistence_patches(stack)
            search = stack.enter_context(patch("main.rag_service.search", side_effect=AssertionError("RAG must not run for a handoff")))
            audit = stack.enter_context(patch("main.save_ai_log"))
            stack.enter_context(patch("main.published_training_match", return_value=None))

            response = await agent_reply(
                AgentReplyRequest(
                    conversation_id="conversation-handoff",
                    customer_id="customer-handoff",
                    user_message="我要退款并投诉",
                )
            )

        search.assert_not_called()
        self.assertTrue(response["handoff_required"])
        self.assertEqual(response["retrieval_context"], [])
        self.assertFalse(audit.call_args.kwargs["rag_used"])
