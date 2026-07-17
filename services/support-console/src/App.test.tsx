import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";
import App from "./App";

const api = {
  listQueue: vi.fn().mockResolvedValue({ items: [] }),
  getHandoff: vi.fn(),
  claim: vi.fn(),
  reply: vi.fn(),
  createTicket: vi.fn(),
  resolve: vi.fn(),
  listTopics: vi.fn().mockResolvedValue({ items: [] }),
  getTopic: vi.fn(),
  createTopic: vi.fn(),
  updateTopic: vi.fn(),
  uploadAsset: vi.fn(),
  previewTopic: vi.fn(),
  publishTopic: vi.fn(),
  rollbackTopic: vi.fn(),
};

it("switches from the workbench to AI training", async () => {
  const user = userEvent.setup();
  render(<App api={api} />);

  await user.click(screen.getByRole("button", { name: "AI 训练" }));

  expect(screen.getByRole("heading", { name: "AI 训练中心" })).toBeInTheDocument();
  expect(screen.getByText("把店铺经验变成可验证、可回滚的 AI 回复。")).toBeInTheDocument();
});

it("opens the simulation notification panel", async () => {
  const user = userEvent.setup();
  render(<App api={api} />);

  await user.click(screen.getByRole("button", { name: "通知" }));

  expect(await screen.findByRole("status")).toHaveTextContent("当前没有需要处理的系统通知");
});

it("renders audit records inside an accessible internal region", async () => {
  const user = userEvent.setup();
  render(<App api={api} />);

  await user.click(screen.getByRole("button", { name: "审计" }));

  expect(screen.getByRole("region", { name: "审计记录列表" })).toBeInTheDocument();
});

it("makes app-level navigation inert while a mobile workbench drawer is open", async () => {
  const user = userEvent.setup();
  const handoff = {
    id: "handoff-1", conversation_id: "conversation-1", customer_id: "customer-1", trigger_reason: "sensitive_case", priority: "high" as const, status: "assigned" as const, created_at: "2026-07-15T11:00:00Z", customer_nickname: "顾客 3028", platform_customer_id: "3028", platform: "simulated-ecommerce", platform_conversation_id: "conversation-1", conversation_status: "human_handling", payload: { user_message: "I need a refund" },
  };
  const modalApi = { ...api, listQueue: vi.fn().mockResolvedValue({ items: [handoff] }), getHandoff: vi.fn().mockResolvedValue({ handoff, messages: [], tickets: [], audit_actions: [] }) };
  render(<App api={modalApi} />);

  await screen.findByText("顾客 3028");
  await user.click(screen.getByRole("button", { name: "会话列表" }));

  expect(await screen.findByRole("dialog", { name: "会话列表" })).toBeInTheDocument();
  expect(document.querySelector(".global-header")).toHaveAttribute("aria-hidden", "true");
  expect(document.querySelector(".global-header")).toHaveAttribute("inert");
  expect(document.querySelector(".side-nav")).toHaveAttribute("aria-hidden", "true");
  expect(document.querySelector(".conversation-panel")).toHaveAttribute("inert");
});
