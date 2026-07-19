import type {
  ConsoleApi,
  Handoff,
  HandoffDetail,
  QueueStatus,
  Ticket,
  TrainingAsset,
  TrainingPreview,
  TrainingTopic,
  TrainingTopicDetail,
  TrainingTopicInput,
  RagStatus,
  RagReindexResponse,
} from "./types";

const baseUrl = (import.meta.env.VITE_AGENT_API_BASE_URL ?? "http://localhost:8010").replace(/\/$/, "");

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set("X-Trace-Id", `console-ui-${crypto.randomUUID()}`);
  const response = await fetch(`${baseUrl}${path}`, { ...options, headers });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(String(body.detail ?? `请求失败（${response.status}）`));
  }
  return response.json() as Promise<T>;
}

function json(body?: unknown): RequestInit {
  return body === undefined
    ? { method: "POST" }
    : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
}

export const apiClient: ConsoleApi = {
  listQueue: (status: QueueStatus) => request<{ items: Handoff[] }>(`/api/console/queue?status=${status}`),
  getHandoff: (id: string) => request<HandoffDetail>(`/api/console/handoffs/${encodeURIComponent(id)}`),
  claim: (id: string) => request<{ handoff: Handoff }>(`/api/console/handoffs/${encodeURIComponent(id)}/claim`, json()),
  reply: (id: string, content: string) => request(`/api/console/handoffs/${encodeURIComponent(id)}/reply`, json({ content })),
  createTicket: (id: string, subject: string, description: string) =>
    request<{ ticket: Ticket }>(`/api/console/handoffs/${encodeURIComponent(id)}/ticket`, json({ subject, description })),
  resolve: (id: string) => request(`/api/console/handoffs/${encodeURIComponent(id)}/resolve`, json()),
  listTopics: () => request<{ items: TrainingTopic[] }>("/api/training/topics"),
  getTopic: (id: string) => request<TrainingTopicDetail>(`/api/training/topics/${encodeURIComponent(id)}`),
  createTopic: (input: TrainingTopicInput) => request<TrainingTopic>("/api/training/topics", json(input)),
  updateTopic: (id: string, input: Partial<TrainingTopicInput>) =>
    request<TrainingTopic>(`/api/training/topics/${encodeURIComponent(id)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    }),
  uploadAsset: async (id: string, file: File, description: string): Promise<TrainingAsset> => {
    const form = new FormData();
    form.append("file", file);
    form.append("description", description);
    return request<TrainingAsset>(`/api/training/topics/${encodeURIComponent(id)}/assets`, { method: "POST", body: form });
  },
  previewTopic: (id: string, query: string) => request<TrainingPreview>(`/api/training/topics/${encodeURIComponent(id)}/preview`, json({ query })),
  publishTopic: (id: string) => request<{ topic: TrainingTopic }>(`/api/training/topics/${encodeURIComponent(id)}/publish`, json()),
  rollbackTopic: (id: string, version: number) =>
    request<{ topic: TrainingTopic; restored_from_version: number }>(`/api/training/topics/${encodeURIComponent(id)}/rollback`, json({ version })),
  getRagStatus: () => request<RagStatus>("/api/rag/status"),
  reindexKnowledge: () => request<RagReindexResponse>("/api/rag/reindex", json()),
};
