import { BellIcon, ClipboardTextIcon, HeadsetIcon, ListBulletsIcon, RobotIcon, StorefrontIcon } from "@phosphor-icons/react";
import { useState } from "react";
import { apiClient } from "./api";
import { TrainingCenter } from "./components/TrainingCenter";
import { Workbench } from "./components/Workbench";
import type { AuditAction, ConsoleApi } from "./types";

type Route = "workbench" | "training" | "audit";

function AuditView({ actions }: { actions: AuditAction[] }) {
  return <main className="audit-shell"><header className="page-heading"><div><span className="eyebrow">可追溯操作</span><h1>审计记录</h1><p>显示当前选中会话或训练主题最近读取到的操作记录。</p></div></header><section className="audit-scroll" aria-label="审计记录列表"><div className="audit-table">{actions.length ? actions.map((action) => <article key={action.id}><span>{new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(action.created_at))}</span><strong>{action.action}</strong><span>{action.actor_role}</span><code>{action.trace_id ?? "—"}</code></article>) : <div className="empty-state"><ClipboardTextIcon weight="duotone" size={32} />选择会话或训练主题后，这里会展示其审计证据。</div>}</div></section></main>;
}

export default function App({ api = apiClient }: { api?: ConsoleApi }) {
  const [route, setRoute] = useState<Route>("workbench");
  const [auditActions, setAuditActions] = useState<AuditAction[]>([]);
  const [notificationOpen, setNotificationOpen] = useState(false);
  const navigation: Array<{ route: Route; label: string; icon: JSX.Element }> = [
    { route: "workbench", label: "工作台", icon: <HeadsetIcon weight="duotone" /> },
    { route: "training", label: "AI 训练", icon: <RobotIcon weight="duotone" /> },
    { route: "audit", label: "审计", icon: <ClipboardTextIcon weight="duotone" /> },
  ];
  return <div className="app-frame">
    <header className="global-header"><div className="brand-lockup"><span className="brand-icon"><StorefrontIcon weight="fill" /></span><div><strong>云栈店铺</strong><small>AI 客服运营台 · 模拟环境</small></div></div><div className="global-meta"><span><i className="live-dot" />模拟渠道在线</span><span>坐席：林墨</span><button className="icon-button" aria-label="通知" aria-expanded={notificationOpen} onClick={() => setNotificationOpen((open) => !open)}><BellIcon weight="duotone" /></button>{notificationOpen && <div className="notification-popover" role="status"><strong>模拟环境通知</strong><span>当前没有需要处理的系统通知。</span><button onClick={() => setNotificationOpen(false)}>知道了</button></div>}</div></header>
    <div className="app-body"><nav className="side-nav" aria-label="主导航"><div className="nav-group">{navigation.map((item) => <button key={item.route} className={route === item.route ? "nav-item active" : "nav-item"} onClick={() => setRoute(item.route)} aria-current={route === item.route ? "page" : undefined}>{item.icon}<span>{item.label}</span></button>)}</div><div className="nav-footer"><ListBulletsIcon weight="duotone" /><span>所有外发均为本地模拟</span></div></nav><section className="app-content">{route === "workbench" && <Workbench api={api} onAuditChange={setAuditActions} />}{route === "training" && <TrainingCenter api={api} onAuditChange={setAuditActions} />}{route === "audit" && <AuditView actions={auditActions} />}</section></div>
  </div>;
}
