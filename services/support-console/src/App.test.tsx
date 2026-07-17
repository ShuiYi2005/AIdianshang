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
