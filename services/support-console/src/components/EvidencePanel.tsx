import { FileTextIcon, PackageIcon, ShieldCheckIcon, WarningCircleIcon } from "@phosphor-icons/react";
import productImage from "../assets/product-chair.png";
import type { HandoffDetail } from "../types";

function auditActionLabel(action: string) {
  return { human_reply: "人工回复", simulated_reply_sent: "已模拟发送", handoff_claimed: "领取会话", handoff_resolved: "解决会话", ticket_created: "创建工单" }[action] ?? action;
}

function formatAuditTime(value: string) {
  return new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", month: "numeric", day: "numeric" }).format(new Date(value));
}

export function EvidencePanel({ detail, mobileOpen = false, backgroundHidden = false, onClose }: { detail: HandoffDetail | null; mobileOpen?: boolean; backgroundHidden?: boolean; onClose?: () => void }) {
  const panelProps = mobileOpen ? { role: "dialog" as const, "aria-modal": true, "aria-label": "客户信息" } : { "aria-hidden": backgroundHidden || undefined, "aria-label": "客户与证据面板" };
  const closeControl = mobileOpen ? <button className="drawer-close" aria-label="关闭客户信息" onClick={onClose}>关闭</button> : null;

  if (!detail) {
    return <aside className={`evidence-panel empty-panel${mobileOpen ? " is-mobile-open" : ""}`} {...panelProps}>{closeControl}选择一个任务，查看客户、订单与审计证据。</aside>;
  }

  const { handoff } = detail;
  const message = String(handoff.payload.user_message ?? "无原始客户消息");
  return (
    <aside className={`evidence-panel${mobileOpen ? " is-mobile-open" : ""}`} {...panelProps}>
      {closeControl}
      <section className="evidence-section customer-card">
        <div className="section-label"><ShieldCheckIcon weight="fill" /> 脱敏客户</div>
        <strong>{handoff.customer_nickname ?? "匿名客户"}</strong>
        <span>渠道：{handoff.platform ?? "simulated-ecommerce"}</span>
        <span>客户标识：{handoff.platform_customer_id ?? "—"}</span>
      </section>

      <section className="evidence-section">
        <div className="section-label"><PackageIcon weight="fill" /> 关联商品</div>
        <div className="product-row">
          <img src={productImage} alt="深蓝人体工学办公椅商品图" />
          <div>
            <strong>深蓝人体工学办公椅</strong>
            <span>模拟商品 · 支持售后训练</span>
            <b>¥ 369.00</b>
          </div>
        </div>
      </section>

      <section className="evidence-section risk-card">
        <div className="section-label"><WarningCircleIcon weight="fill" /> 转人工原因</div>
        <strong>{handoff.trigger_reason === "sensitive_case" ? "敏感售后请求" : handoff.trigger_reason}</strong>
        <p>{message}</p>
      </section>

      <section className="evidence-section">
        <div className="section-label"><FileTextIcon weight="fill" /> 上下文证据</div>
        <dl className="evidence-list">
          <div><dt>会话</dt><dd>{handoff.platform_conversation_id ?? handoff.conversation_id}</dd></div>
          <div><dt>状态</dt><dd>{handoff.conversation_status ?? "待同步"}</dd></div>
          <div><dt>审计动作</dt><dd>{detail.audit_actions.length} 条</dd></div>
          <div><dt>工单</dt><dd>{detail.tickets.length} 张</dd></div>
        </dl>
      </section>

      {detail.audit_actions.length > 0 && <section className="evidence-section evidence-audit">
        <div className="section-label"><FileTextIcon weight="fill" /> 最近操作</div>
        <ol className="evidence-audit-list">
          {detail.audit_actions.map((action) => <li key={action.id}>
            <strong>{auditActionLabel(action.action)}</strong>
            <span>{action.actor_role} · {formatAuditTime(action.created_at)}</span>
          </li>)}
        </ol>
      </section>}
    </aside>
  );
}
