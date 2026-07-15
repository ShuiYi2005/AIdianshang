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

it("keeps a claimed conversation active in the assigned queue", async () => {
  const user = userEvent.setup();
  const otherPendingHandoff = { ...handoff, id: "pending-2", customer_nickname: "顾客 4001" };
  const assignedHandoff = { ...handoff, status: "assigned" as const };
  const api = {
    listQueue: vi.fn()
      .mockResolvedValueOnce({ items: [handoff] })
      .mockImplementation((status) => Promise.resolve({ items: status === "assigned" ? [assignedHandoff] : [otherPendingHandoff] })),
    getHandoff: vi.fn().mockImplementation((handoffId) => Promise.resolve({
      ...detail,
      handoff: handoffId === handoff.id ? handoff : otherPendingHandoff,
    })),
    claim: vi.fn().mockResolvedValue({ handoff: assignedHandoff }),
    reply: vi.fn(),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  await user.click(screen.getByRole("button", { name: "领取" }));

  await waitFor(() => expect(api.listQueue).toHaveBeenLastCalledWith("assigned"));
  expect(screen.getByLabelText("人工回复")).not.toBeDisabled();
});

it("keeps a resolved conversation visible in the resolved queue", async () => {
  const user = userEvent.setup();
  const assignedHandoff = { ...handoff, status: "assigned" as const };
  const resolvedHandoff = { ...handoff, status: "resolved" as const };
  const otherPendingHandoff = { ...handoff, id: "pending-3", customer_nickname: "顾客 5002" };
  const api = {
    listQueue: vi.fn()
      .mockResolvedValueOnce({ items: [assignedHandoff] })
      .mockImplementation((status) => Promise.resolve({ items: status === "resolved" ? [resolvedHandoff] : [otherPendingHandoff] })),
    getHandoff: vi.fn().mockImplementation((handoffId) => Promise.resolve({
      ...detail,
      handoff: handoffId === handoff.id ? assignedHandoff : otherPendingHandoff,
    })),
    claim: vi.fn(),
    reply: vi.fn(),
    createTicket: vi.fn(),
    resolve: vi.fn().mockResolvedValue({ resolved: true }),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  await user.click(screen.getByRole("button", { name: "解决任务" }));
  await user.click(screen.getByRole("button", { name: "确认解决" }));

  await waitFor(() => expect(api.listQueue).toHaveBeenLastCalledWith("resolved"));
  expect(await screen.findByText("已解决", { selector: ".status-chip.resolved" })).toBeInTheDocument();
  expect(screen.getByLabelText("人工回复")).toBeDisabled();
});
