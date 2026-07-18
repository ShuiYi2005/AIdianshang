import { render, screen, waitFor, within } from "@testing-library/react";
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

function deferred<T>() {
  let resolve: (value: T) => void = () => undefined;
  const promise = new Promise<T>((next) => { resolve = next; });
  return { promise, resolve };
}

it("sends a human reply and renders simulated delivery status", async () => {
  const user = userEvent.setup();
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [handoff] }),
    getHandoff: vi.fn().mockResolvedValueOnce(detail).mockResolvedValue({ ...detail, handoff: { ...handoff, status: "assigned" } }),
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
    getHandoff: vi.fn().mockResolvedValueOnce(detail).mockResolvedValue({ ...detail, handoff: assignedHandoff }),
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
    getHandoff: vi.fn().mockResolvedValueOnce({ ...detail, handoff: assignedHandoff }).mockResolvedValue({ ...detail, handoff: resolvedHandoff }),
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

it("opens and closes the mobile queue and customer-information drawers", async () => {
  const user = userEvent.setup();
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [handoff] }),
    getHandoff: vi.fn().mockResolvedValue(detail),
    claim: vi.fn(),
    reply: vi.fn(),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  await user.click(screen.getByRole("button", { name: "会话列表" }));
  expect(screen.getByRole("dialog", { name: "会话列表" })).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "关闭会话列表" }));
  expect(screen.queryByRole("dialog", { name: "会话列表" })).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "客户信息" }));
  expect(screen.getByRole("dialog", { name: "客户信息" })).toBeInTheDocument();
});

it("renders audit records in the evidence panel so long context remains locally scrollable", async () => {
  const auditActions = Array.from({ length: 3 }, (_, index) => ({
    id: `audit-${index + 1}`,
    actor_role: "human",
    action: "simulated_reply_sent",
    target_type: "handoff",
    target_id: handoff.id,
    trace_id: null,
    details: {},
    created_at: `2026-07-15T11:0${index}:00Z`,
  }));
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [handoff] }),
    getHandoff: vi.fn().mockResolvedValue({ ...detail, audit_actions: auditActions }),
    claim: vi.fn(),
    reply: vi.fn(),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  const evidencePanel = await screen.findByLabelText("客户与证据面板");
  expect(within(evidencePanel).getByText("最近操作")).toBeInTheDocument();
  expect(within(evidencePanel).getAllByText("已模拟发送")).toHaveLength(3);
});

it("refreshes the evidence timeline after a successful customer reply", async () => {
  const user = userEvent.setup();
  const assignedHandoff = { ...handoff, status: "assigned" as const };
  const replyMessage = { id: "message-3", sender_type: "human" as const, content: "We are reviewing it now.", created_at: "2026-07-15T11:01:00Z", metadata: {} };
  const refreshedDetail = {
    ...detail,
    handoff: assignedHandoff,
    messages: [...detail.messages, replyMessage],
    audit_actions: [{ id: "audit-reply", actor_role: "support_agent", action: "simulated_reply_sent", target_type: "handoff", target_id: handoff.id, trace_id: null, details: {}, created_at: "2026-07-15T11:01:00Z" }],
  };
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [assignedHandoff] }),
    getHandoff: vi.fn().mockResolvedValueOnce({ ...detail, handoff: assignedHandoff }).mockResolvedValueOnce(refreshedDetail),
    claim: vi.fn(),
    reply: vi.fn().mockResolvedValue({ message: replyMessage, delivery_status: "simulated_sent" }),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  await user.type(screen.getByLabelText("人工回复"), "We are reviewing it now.");
  await user.click(screen.getByRole("button", { name: "发送回复" }));

  await waitFor(() => expect(api.getHandoff).toHaveBeenCalledTimes(2));
  expect(await within(screen.getByLabelText("客户与证据面板")).findByText("已模拟发送")).toBeInTheDocument();
});

it("keeps the newest detail when asynchronous audit refreshes resolve out of order", async () => {
  const user = userEvent.setup();
  const assignedHandoff = { ...handoff, status: "assigned" as const };
  const firstReply = { id: "message-first", sender_type: "human" as const, content: "First reply", created_at: "2026-07-15T11:01:00Z", metadata: {} };
  const secondReply = { id: "message-second", sender_type: "human" as const, content: "Second reply", created_at: "2026-07-15T11:02:00Z", metadata: {} };
  const staleDetail = { ...detail, handoff: assignedHandoff, messages: [...detail.messages, firstReply], audit_actions: [{ id: "audit-old", actor_role: "support_agent", action: "older_action", target_type: "handoff", target_id: handoff.id, trace_id: null, details: {}, created_at: firstReply.created_at }] };
  const latestDetail = { ...detail, handoff: assignedHandoff, messages: [...detail.messages, firstReply, secondReply], audit_actions: [{ id: "audit-new", actor_role: "support_agent", action: "latest_action", target_type: "handoff", target_id: handoff.id, trace_id: null, details: {}, created_at: secondReply.created_at }] };
  const staleRefresh = deferred<typeof staleDetail>();
  const latestRefresh = deferred<typeof latestDetail>();
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [assignedHandoff] }),
    getHandoff: vi.fn().mockResolvedValueOnce({ ...detail, handoff: assignedHandoff }).mockReturnValueOnce(staleRefresh.promise).mockReturnValueOnce(latestRefresh.promise),
    claim: vi.fn(),
    reply: vi.fn().mockResolvedValueOnce({ message: firstReply, delivery_status: "simulated_sent" }).mockResolvedValueOnce({ message: secondReply, delivery_status: "simulated_sent" }),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  const replyBox = screen.getByLabelText("人工回复");
  await user.type(replyBox, firstReply.content);
  await user.click(screen.getByRole("button", { name: "发送回复" }));
  await waitFor(() => expect(api.getHandoff).toHaveBeenCalledTimes(2));
  await user.type(replyBox, secondReply.content);
  await user.click(screen.getByRole("button", { name: "发送回复" }));
  await waitFor(() => expect(api.getHandoff).toHaveBeenCalledTimes(3));

  latestRefresh.resolve(latestDetail);
  expect(await within(screen.getByLabelText("客户与证据面板")).findByText("latest_action")).toBeInTheDocument();
  staleRefresh.resolve(staleDetail);
  await new Promise((resolve) => setTimeout(resolve, 0));

  expect(within(screen.getByLabelText("客户与证据面板")).queryByText("older_action")).not.toBeInTheDocument();
  expect(within(screen.getByLabelText("客户与证据面板")).getByText("latest_action")).toBeInTheDocument();
});

it("moves focus into a mobile drawer and restores it after Escape closes the drawer", async () => {
  const user = userEvent.setup();
  const api = {
    listQueue: vi.fn().mockResolvedValue({ items: [handoff] }),
    getHandoff: vi.fn().mockResolvedValue(detail),
    claim: vi.fn(),
    reply: vi.fn(),
    createTicket: vi.fn(),
    resolve: vi.fn(),
  };
  render(<Workbench api={api} />);

  await screen.findByText("顾客 3028");
  const openQueue = screen.getByRole("button", { name: "会话列表" });
  await user.click(openQueue);
  const closeQueue = screen.getByRole("button", { name: "关闭会话列表" });
  await waitFor(() => expect(closeQueue).toHaveFocus());
  await user.keyboard("{Escape}");

  await waitFor(() => expect(screen.queryByRole("dialog", { name: "会话列表" })).not.toBeInTheDocument());
  expect(openQueue).toHaveFocus();
});
