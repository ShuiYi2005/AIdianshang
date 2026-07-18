import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";
import { TrainingCenter } from "./TrainingCenter";

const topic = {
  id: "5aec95de-88d2-40e5-a557-bd3378ab12a3",
  name: "After-sales guide",
  trigger_phrases: ["where is my parcel"],
  reply_text: "I will check the dispatch status for you.",
  store_scope: "simulated-store",
  product_scope: "all-products",
  channel: "simulated-ecommerce",
  status: "draft",
  current_version: 0,
  created_at: "2026-07-15T11:00:00Z",
  updated_at: "2026-07-15T11:00:00Z",
  metadata: {},
};

it("creates a topic and previews its protected reply", async () => {
  const user = userEvent.setup();
  const api = {
    listTopics: vi.fn().mockResolvedValue({ items: [] }),
    getTopic: vi.fn(),
    createTopic: vi.fn().mockResolvedValue(topic),
    updateTopic: vi.fn(),
    uploadAsset: vi.fn(),
    previewTopic: vi.fn().mockResolvedValue({ matched: false, handoff_required: true, reply: "需要人工客服核验后处理。" }),
    publishTopic: vi.fn(),
    rollbackTopic: vi.fn(),
  };
  render(<TrainingCenter api={api} />);

  await user.click(screen.getByRole("button", { name: "新建主题" }));
  await user.type(screen.getByLabelText("主题名称"), "After-sales guide");
  await user.type(screen.getByLabelText("触发语"), "where is my parcel");
  await user.type(screen.getByLabelText("标准回复"), "I will check the dispatch status for you.");
  await user.click(screen.getByRole("button", { name: "保存主题" }));
  await waitFor(() => expect(api.createTopic).toHaveBeenCalled());

  await user.type(screen.getByLabelText("预览问题"), "I need a refund");
  await user.click(screen.getByRole("button", { name: "预览回复" }));
  expect(await screen.findByText("需要人工客服核验后处理。")).toBeInTheDocument();
});

it("opens and closes the training-topic drawer without leaving the editor", async () => {
  const user = userEvent.setup();
  const api = {
    listTopics: vi.fn().mockResolvedValue({ items: [topic] }),
    getTopic: vi.fn(),
    createTopic: vi.fn(),
    updateTopic: vi.fn(),
    uploadAsset: vi.fn(),
    previewTopic: vi.fn(),
    publishTopic: vi.fn(),
    rollbackTopic: vi.fn(),
  };
  render(<TrainingCenter api={api} />);

  await user.click(screen.getByRole("button", { name: "主题列表" }));
  expect(screen.getByRole("dialog", { name: "主题列表" })).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "关闭主题列表" }));
  expect(screen.queryByRole("dialog", { name: "主题列表" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "AI 训练中心" })).toBeVisible();
});
