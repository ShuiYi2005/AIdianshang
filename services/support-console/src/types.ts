export type QueueStatus = "pending" | "assigned" | "resolved";

export interface Handoff {
  id: string;
  conversation_id: string;
  customer_id: string | null;
  tenant_id?: string | null;
  trigger_reason: string;
  priority: "low" | "normal" | "high" | "urgent";
  status: QueueStatus;
  created_at: string;
  assigned_at?: string | null;
  resolved_at?: string | null;
  customer_nickname?: string | null;
  platform_customer_id?: string | null;
  platform?: string | null;
  platform_conversation_id?: string | null;
  conversation_status?: string | null;
  payload: Record<string, unknown>;
}

export interface ConversationMessage {
  id: string;
  sender_type: "customer" | "ai" | "human" | "system";
  content: string;
  created_at: string;
  metadata: Record<string, unknown>;
}

export interface Ticket {
  id: string;
  type: string;
  status: string;
  priority: string;
  subject: string;
  description: string;
  created_at: string;
  updated_at: string;
}

export interface AuditAction {
  id: string;
  actor_role: string;
  action: string;
  target_type: string;
  target_id: string | null;
  trace_id: string | null;
  details: Record<string, unknown>;
  created_at: string;
}

export interface HandoffDetail {
  handoff: Handoff;
  messages: ConversationMessage[];
  tickets: Ticket[];
  audit_actions: AuditAction[];
}

export interface TrainingTopic {
  id: string;
  tenant_id?: string | null;
  name: string;
  trigger_phrases: string[];
  reply_text: string;
  store_scope: string;
  product_scope: string;
  channel: string;
  status: "draft" | "published" | "archived";
  current_version: number;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface TrainingAsset {
  id: string;
  topic_id: string;
  asset_type: "text" | "image" | "video";
  filename: string;
  mime_type: string;
  byte_size: number;
  storage_path: string;
  description: string;
  created_at: string;
}

export interface TrainingVersion {
  id: string;
  topic_id: string;
  version: number;
  status: "published" | "superseded" | "rolled_back";
  snapshot: Record<string, unknown>;
  published_at: string;
  rolled_back_at: string | null;
  created_at: string;
}

export interface TrainingTopicDetail {
  topic: TrainingTopic;
  assets: TrainingAsset[];
  versions: TrainingVersion[];
  audit_actions: AuditAction[];
}

export interface TrainingTopicInput {
  name: string;
  trigger_phrases: string[];
  reply_text: string;
  store_scope: string;
  product_scope: string;
  channel: string;
}

export interface TrainingPreview {
  matched: boolean;
  handoff_required: boolean;
  reply: string;
}

export interface RagStatus {
  mode: "hybrid" | "vector" | "keyword";
  model_name: string;
  model_cache_status: "missing" | "downloading" | "ready" | "failed";
  weaviate_status: "ready" | "unavailable" | "unknown";
  index_status: "idle" | "running" | "ready" | "failed" | "degraded" | "succeeded";
  last_sync: { status: string; finished_at: string | null; error_message: string | null } | null;
  document_count: number;
  chunk_count: number;
}

export interface RagReindexResponse { sync_job_id: string; status: "running"; accepted: boolean; }

export interface ConsoleApi {
  listQueue(status: QueueStatus): Promise<{ items: Handoff[] }>;
  getHandoff(id: string): Promise<HandoffDetail>;
  claim(id: string): Promise<{ handoff: Handoff }>;
  reply(id: string, content: string): Promise<{ message: ConversationMessage; delivery_status: "simulated_sent" }>;
  createTicket(id: string, subject: string, description: string): Promise<{ ticket: Ticket }>;
  resolve(id: string): Promise<{ handoff_id: string; resolved: boolean }>;
  listTopics(): Promise<{ items: TrainingTopic[] }>;
  getTopic(id: string): Promise<TrainingTopicDetail>;
  createTopic(input: TrainingTopicInput): Promise<TrainingTopic>;
  updateTopic(id: string, input: Partial<TrainingTopicInput>): Promise<TrainingTopic>;
  uploadAsset(id: string, file: File, description: string): Promise<TrainingAsset>;
  previewTopic(id: string, query: string): Promise<TrainingPreview>;
  publishTopic(id: string): Promise<{ topic: TrainingTopic }>;
  rollbackTopic(id: string, version: number): Promise<{ topic: TrainingTopic; restored_from_version: number }>;
  getRagStatus(): Promise<RagStatus>;
  reindexKnowledge(): Promise<RagReindexResponse>;
}
