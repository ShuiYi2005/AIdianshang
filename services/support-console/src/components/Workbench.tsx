import {
  CheckCircleIcon,
  ClockIcon,
  PaperPlaneTiltIcon,
  PlusIcon,
  RobotIcon,
  TicketIcon,
  UserCircleIcon,
  WarningCircleIcon,
} from "@phosphor-icons/react";
import { useEffect, useState } from "react";
import type { ConsoleApi, Handoff, HandoffDetail, QueueStatus } from "../types";
import { EvidencePanel } from "./EvidencePanel";

type WorkbenchApi = Pick<ConsoleApi, "listQueue" | "getHandoff" | "claim" | "reply" | "createTicket" | "resolve">;

function formatTime(value: string) {
  return new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", month: "numeric", day: "numeric" }).format(new Date(value));
}

function priorityLabel(priority: Handoff["priority"]) {
  return { urgent: "紧急", high: "高优先", normal: "普通", low: "低优先" }[priority];
}

export function Workbench({ api, onAuditChange }: { api: WorkbenchApi; onAuditChange?: (actions: HandoffDetail["audit_actions"]) => void }) {
  const [queueStatus, setQueueStatus] = useState<QueueStatus>("pending");
  const [items, setItems] = useState<Handoff[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<HandoffDetail | null>(null);
  const [reply, setReply] = useState("");
  const [ticketOpen, setTicketOpen] = useState(false);
  const [ticketSubject, setTicketSubject] = useState("");
  const [ticketDescription, setTicketDescription] = useState("");
  const [confirmResolve, setConfirmResolve] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  const loadQueue = async (status = queueStatus) => {
    setError("");
    try {
      const result = await api.listQueue(status);
      setItems(result.items);
      setSelectedId((current) => current && result.items.some((item) => item.id === current) ? current : result.items[0]?.id ?? null);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "队列加载失败，请重试。");
    }
  };

  useEffect(() => { void loadQueue(); }, [queueStatus]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      return;
    }
    let active = true;
    void api.getHandoff(selectedId).then((next) => {
      if (active) {
        setDetail(next);
        onAuditChange?.(next.audit_actions);
      }
    }).catch((reason: unknown) => active && setError(reason instanceof Error ? reason.message : "任务详情加载失败。"));
    return () => { active = false; };
  }, [selectedId]);

  const claim = async () => {
    if (!detail) return;
    setBusy("claim"); setError("");
    try {
      const result = await api.claim(detail.handoff.id);
      setDetail({ ...detail, handoff: result.handoff });
      setNotice("任务已领取，进入人工处理状态。");
      await loadQueue(queueStatus);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "领取失败，请重试。"); }
    finally { setBusy(null); }
  };

  const sendReply = async () => {
    if (!detail || !reply.trim()) return;
    setBusy("reply"); setError("");
    try {
      const result = await api.reply(detail.handoff.id, reply.trim());
      setDetail({ ...detail, messages: [...detail.messages, result.message] });
      setReply("");
      setNotice("模拟渠道已发送");
    } catch (reason) { setError(reason instanceof Error ? reason.message : "发送失败，已保留输入内容。"); }
    finally { setBusy(null); }
  };

  const createTicket = async () => {
    if (!detail || !ticketSubject.trim() || !ticketDescription.trim()) return;
    setBusy("ticket"); setError("");
    try {
      const result = await api.createTicket(detail.handoff.id, ticketSubject.trim(), ticketDescription.trim());
      setDetail({ ...detail, tickets: [result.ticket, ...detail.tickets] });
      setTicketSubject(""); setTicketDescription(""); setTicketOpen(false);
      setNotice("本地工单已创建并关联当前会话。");
    } catch (reason) { setError(reason instanceof Error ? reason.message : "工单创建失败，输入未丢失。"); }
    finally { setBusy(null); }
  };

  const resolve = async () => {
    if (!detail) return;
    setBusy("resolve"); setError("");
    try {
      await api.resolve(detail.handoff.id);
      setNotice("任务已解决，记录已写入审计。");
      setConfirmResolve(false);
      await loadQueue(queueStatus);
      setDetail({ ...detail, handoff: { ...detail.handoff, status: "resolved" } });
    } catch (reason) { setError(reason instanceof Error ? reason.message : "解决失败，请重试。"); }
    finally { setBusy(null); }
  };

  const statusSwitch = (status: QueueStatus, label: string) => <button className={queueStatus === status ? "queue-filter active" : "queue-filter"} onClick={() => setQueueStatus(status)}>{label}</button>;

  return <main className="workbench-shell">
    <section className="queue-panel" aria-label="转人工队列">
      <div className="panel-heading"><div><span className="eyebrow">人工接管</span><h2>会话队列</h2></div><span className="count-pill">{items.length}</span></div>
      <div className="queue-filters">{statusSwitch("pending", "待领取")}{statusSwitch("assigned", "已领取")}{statusSwitch("resolved", "已解决")}</div>
      <div className="queue-list">
        {items.map((item) => <button key={item.id} className={selectedId === item.id ? "queue-item selected" : "queue-item"} onClick={() => setSelectedId(item.id)}>
          <span className="queue-avatar"><UserCircleIcon weight="fill" /></span>
          <span className="queue-copy"><strong>{item.customer_nickname ?? "匿名客户"}</strong><small>{item.trigger_reason === "sensitive_case" ? "敏感售后请求" : item.trigger_reason}</small><small>{formatTime(item.created_at)}</small></span>
          <span className={`priority-dot ${item.priority}`}>{priorityLabel(item.priority)}</span>
        </button>)}
        {!items.length && <div className="empty-state"><ClockIcon weight="duotone" size={28} />当前筛选下没有任务</div>}
      </div>
    </section>

    <section className="conversation-panel" aria-label="客服会话">
      {detail ? <>
        <header className="conversation-header"><div><span className="eyebrow">{detail.handoff.platform ?? "模拟电商"}</span><h2>{detail.handoff.customer_nickname ?? "匿名客户"}</h2><p>AI 已保留上下文，人工操作将同步写入本地模拟渠道与审计。</p></div><span className={`status-chip ${detail.handoff.status}`}>{detail.handoff.status === "pending" ? "待领取" : detail.handoff.status === "assigned" ? "人工处理中" : "已解决"}</span></header>
        <div className="action-row">
          <button className="secondary-action" disabled={detail.handoff.status !== "pending" || busy === "claim"} onClick={() => void claim()}><UserCircleIcon weight="bold" />领取</button>
          <button className="secondary-action" onClick={() => setTicketOpen((open) => !open)}><TicketIcon weight="bold" />创建工单</button>
          <button className="danger-action" disabled={detail.handoff.status !== "assigned"} onClick={() => setConfirmResolve(true)}><CheckCircleIcon weight="bold" />解决任务</button>
        </div>
        {ticketOpen && <div className="ticket-form"><label>工单主题<input value={ticketSubject} onChange={(event) => setTicketSubject(event.target.value)} placeholder="例如：退款人工核验" /></label><label>处理说明<textarea value={ticketDescription} onChange={(event) => setTicketDescription(event.target.value)} placeholder="记录处理计划与承诺" /></label><button className="primary-action" disabled={busy === "ticket" || !ticketSubject.trim() || !ticketDescription.trim()} onClick={() => void createTicket()}><PlusIcon weight="bold" />提交工单</button></div>}
        {confirmResolve && <div className="confirmation"><WarningCircleIcon weight="fill" /><span>确认解决该任务？此操作会关闭当前会话并记录审计。</span><button onClick={() => setConfirmResolve(false)}>取消</button><button className="danger-action" disabled={busy === "resolve"} onClick={() => void resolve()}>确认解决</button></div>}
        {error && <div className="notice error-notice" role="alert">{error}</div>}
        {notice && <div className="notice success-notice" role="status">{notice}</div>}
        <div className="message-stream">
          {detail.messages.map((message) => <article key={message.id} className={`message ${message.sender_type}`}><span className="message-icon">{message.sender_type === "ai" ? <RobotIcon weight="fill" /> : <UserCircleIcon weight="fill" />}</span><div><small>{message.sender_type === "customer" ? "客户" : message.sender_type === "ai" ? "AI 客服" : "人工客服"} · {formatTime(message.created_at)}</small><p>{message.content}</p></div></article>)}
        </div>
        <div className="reply-composer"><label htmlFor="human-reply">人工回复</label><textarea id="human-reply" value={reply} onChange={(event) => setReply(event.target.value)} placeholder="输入对客户的回复；发送将写入本地模拟渠道。" disabled={detail.handoff.status !== "assigned"} /><div><span>真实电商未接入 · 当前为模拟发送</span><button className="primary-action" disabled={busy === "reply" || detail.handoff.status !== "assigned" || !reply.trim()} onClick={() => void sendReply()}><PaperPlaneTiltIcon weight="fill" />发送回复</button></div></div>
      </> : <div className="conversation-empty"><RobotIcon weight="duotone" size={42} /><h2>选择一个待处理会话</h2><p>领取后可发送人工回复、创建工单并保留审计记录。</p></div>}
    </section>
    <EvidencePanel detail={detail} />
  </main>;
}
