import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";
import { Workbench } from "./Workbench";

const handoff = {
  id: "1b6f0a8e-0477-4cc5-ae32-7e3cb59466d1",
  conversation_id: "conversation-1",
  customer_id: "customer-1",
  trigger_reason: "sensitive_case",
  priority: "high",
  status: "pending",
  created_at: "2026-07-15T11:00:00Z",
  customer_nickname: "顾客 3028",
  platform_customer_id: "3028",
  platform: "simulated-ecommerce",
  platform_conversation_id: "conversation-1",
  conversation_status: "ai_handling",
  payload: { user_message: "I need a refund" },
};

const detail = {
  handoff,
  messages: [
    { id: "message-1", sender_type: "customer", content: "I need a refund", created_at: "2026-07-15T11:00:00Z", metadata: {} },
    { id: "message-2", sender_type: "ai", content: "This needs a human review.", created_at: "2026-07-15T11:00:03Z", metadata: {} },
  ],
  tickets: [],
  audit_actions: [],
};

it("sends a human reply and renders simulated delivery status", async () => {
  const user = userEvent.setup();
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [handoff] }),
    getHandoff: vi.fn().mockResolvedValue(detail),
    claim: vi.fn().mockResolvedValue({ handoff: { ...handoff, status: "assigned" } }),
    reply: vi.fn().mockResolvedValue({
      message: { id: "message-3", sender_type: "human", content: "We are reviewing it now.", created_at: "2026-07-15T11:01:00Z", metadata: {} },
      delivery_status: "simulated_sent",
    }),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  await user.click(await screen.findByRole("button", { name: "领取" }));
  await user.type(screen.getByLabelText("人工回复"), "We are reviewing it now.");
  await user.click(screen.getByRole("button", { name: "发送回复" }));

  await waitFor(() => expect(api.reply).toHaveBeenCalledWith(handoff.id, "We are reviewing it now."));
  expect(await screen.findByText("模拟渠道已发送")).toBeInTheDocument();
});
