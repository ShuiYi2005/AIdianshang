import { ArrowClockwiseIcon, FloppyDiskIcon, PaperclipIcon, PlayCircleIcon, PlusIcon, UploadSimpleIcon } from "@phosphor-icons/react";
import { useEffect, useMemo, useState } from "react";
import type { ConsoleApi, TrainingTopic, TrainingTopicDetail } from "../types";

type TrainingApi = Pick<ConsoleApi, "listTopics" | "getTopic" | "createTopic" | "updateTopic" | "uploadAsset" | "previewTopic" | "publishTopic" | "rollbackTopic">;

const emptyForm = { name: "", triggerPhrases: "", replyText: "", storeScope: "simulated-store", productScope: "all-products", channel: "simulated-ecommerce" };

export function TrainingCenter({ api, onAuditChange }: { api: TrainingApi; onAuditChange?: (actions: TrainingTopicDetail["audit_actions"]) => void }) {
  const [topics, setTopics] = useState<TrainingTopic[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<TrainingTopicDetail | null>(null);
  const [form, setForm] = useState(emptyForm);
  const [previewQuery, setPreviewQuery] = useState("");
  const [preview, setPreview] = useState<{ matched: boolean; handoff_required: boolean; reply: string } | null>(null);
  const [assetFile, setAssetFile] = useState<File | null>(null);
  const [assetDescription, setAssetDescription] = useState("");
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const versions = useMemo(() => detail?.versions.filter((version) => version.version !== detail.topic.current_version) ?? [], [detail]);
  const [rollbackVersion, setRollbackVersion] = useState<number | null>(null);
  const [topicDrawerOpen, setTopicDrawerOpen] = useState(false);

  const loadTopics = async () => {
    try { const result = await api.listTopics(); setTopics(result.items); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "训练主题加载失败。"); }
  };
  useEffect(() => { void loadTopics(); }, []);

  const loadDetail = async (id: string) => {
    setError("");
    try {
      const next = await api.getTopic(id);
      setDetail(next); setSelectedId(id); onAuditChange?.(next.audit_actions);
      setForm({ name: next.topic.name, triggerPhrases: next.topic.trigger_phrases.join("\n"), replyText: next.topic.reply_text, storeScope: next.topic.store_scope, productScope: next.topic.product_scope, channel: next.topic.channel });
      const historicalVersions = next.versions.filter((version) => version.version !== next.topic.current_version);
      setRollbackVersion(historicalVersions.length ? historicalVersions[historicalVersions.length - 1].version : null);
      setPreview(null);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "训练主题详情加载失败。"); }
  };

  const newTopic = () => { setSelectedId(null); setDetail(null); setForm(emptyForm); setPreview(null); setNotice("正在创建新的训练主题。"); setError(""); };
  const input = (key: keyof typeof form) => (event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setForm({ ...form, [key]: event.target.value });
  const inputPayload = () => ({ name: form.name.trim(), trigger_phrases: form.triggerPhrases.split(/[\n,]/).map((phrase) => phrase.trim()).filter(Boolean), reply_text: form.replyText.trim(), store_scope: form.storeScope.trim(), product_scope: form.productScope.trim(), channel: form.channel.trim() });

  const save = async () => {
    const payload = inputPayload();
    if (!payload.name || !payload.trigger_phrases.length || !payload.reply_text) { setError("请填写主题名称、至少一个触发语和标准回复。"); return; }
    setBusy("save"); setError("");
    try {
      const saved = selectedId ? await api.updateTopic(selectedId, payload) : await api.createTopic(payload);
      setSelectedId(saved.id);
      setDetail((current) => current ? { ...current, topic: saved } : { topic: saved, assets: [], versions: [], audit_actions: [] });
      setNotice(selectedId ? "草稿已更新，发布前可继续预览。" : "训练主题已创建，现在可以上传素材并预览。");
      await loadTopics();
    } catch (reason) { setError(reason instanceof Error ? reason.message : "保存失败，填写内容未丢失。"); }
    finally { setBusy(null); }
  };

  const upload = async () => {
    if (!selectedId || !assetFile) { setError("请先保存主题并选择素材文件。"); return; }
    setBusy("upload"); setError("");
    try {
      await api.uploadAsset(selectedId, assetFile, assetDescription);
      setAssetFile(null); setAssetDescription(""); setNotice("素材已上传到本地训练卷。"); await loadDetail(selectedId);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "素材上传失败，请检查格式和大小。"); }
    finally { setBusy(null); }
  };

  const runPreview = async () => {
    if (!selectedId || !previewQuery.trim()) { setError("请先保存主题并输入预览问题。"); return; }
    setBusy("preview"); setError("");
    try { setPreview(await api.previewTopic(selectedId, previewQuery.trim())); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "预览失败，请重试。"); }
    finally { setBusy(null); }
  };

  const publish = async () => {
    if (!selectedId) return;
    setBusy("publish"); setError("");
    try { await api.publishTopic(selectedId); setNotice("训练已发布：已生成不可变版本，并可随时回滚。"); await loadDetail(selectedId); await loadTopics(); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "发布失败，请重试。"); }
    finally { setBusy(null); }
  };

  const rollback = async () => {
    if (!selectedId || rollbackVersion === null) return;
    setBusy("rollback"); setError("");
    try { await api.rollbackTopic(selectedId, rollbackVersion); setNotice(`已从版本 ${rollbackVersion} 生成新的当前发布版本。`); await loadDetail(selectedId); await loadTopics(); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "回滚失败，请重试。"); }
    finally { setBusy(null); }
  };

  return <main className="training-shell">
    {topicDrawerOpen && <button className="drawer-backdrop" aria-label="关闭主题覆盖层" onClick={() => setTopicDrawerOpen(false)} />}
    <aside className={`topic-list-panel${topicDrawerOpen ? " is-mobile-open" : ""}`} role={topicDrawerOpen ? "dialog" : undefined} aria-modal={topicDrawerOpen || undefined} aria-label={topicDrawerOpen ? "主题列表" : undefined}>{topicDrawerOpen && <button className="drawer-close" aria-label="关闭主题列表" onClick={() => setTopicDrawerOpen(false)}>关闭</button>}<div className="panel-heading"><div><span className="eyebrow">训练资产</span><h2>主题库</h2></div><button className="icon-button" onClick={() => { newTopic(); setTopicDrawerOpen(false); }} aria-label="新建主题快捷入口"><PlusIcon weight="bold" /></button></div><button className="new-topic-button" onClick={() => { newTopic(); setTopicDrawerOpen(false); }}><PlusIcon weight="bold" />新建主题</button><div className="topic-list">{topics.map((topic) => <button key={topic.id} className={topic.id === selectedId ? "topic-item selected" : "topic-item"} onClick={() => { void loadDetail(topic.id); setTopicDrawerOpen(false); }}><span><strong>{topic.name}</strong><small>{topic.trigger_phrases.slice(0, 2).join(" · ")}</small></span><em className={`topic-status ${topic.status}`}>{topic.status === "published" ? `V${topic.current_version}` : "草稿"}</em></button>)}{!topics.length && <p className="empty-state">尚无训练主题，创建第一条店铺经验。</p>}</div></aside>
    <section className="training-editor"><header className="page-heading"><div><span className="eyebrow">可验证训练</span><h1>AI 训练中心</h1><p>把店铺经验变成可验证、可回滚的 AI 回复。</p></div><div className="training-header-actions"><button className="mobile-topic-toggle secondary-action" aria-expanded={topicDrawerOpen} onClick={() => setTopicDrawerOpen(true)}>主题列表</button><button className="secondary-action" disabled={!selectedId || busy === "preview"} onClick={() => void runPreview()}><PlayCircleIcon weight="fill" />快速预览</button><button className="primary-action" disabled={!selectedId || busy === "publish"} onClick={() => void publish()}><FloppyDiskIcon weight="fill" />发布训练</button></div></header>
      {error && <div className="notice error-notice" role="alert">{error}</div>}{notice && <div className="notice success-notice" role="status">{notice}</div>}
      <div className="editor-grid"><section className="editor-card"><h2>回复规则</h2><label>主题名称<input aria-label="主题名称" value={form.name} onChange={input("name")} placeholder="例如：物流催发" /></label><label>触发语<textarea aria-label="触发语" value={form.triggerPhrases} onChange={input("triggerPhrases")} placeholder="每行一条，例如：\n什么时候发货" /></label><label>标准回复<textarea aria-label="标准回复" className="reply-field" value={form.replyText} onChange={input("replyText")} placeholder="给客户的安全、可执行答复" /></label><div className="scope-grid"><label>店铺范围<input value={form.storeScope} onChange={input("storeScope")} /></label><label>商品范围<input value={form.productScope} onChange={input("productScope")} /></label><label>渠道<input value={form.channel} onChange={input("channel")} /></label></div><button className="primary-action" disabled={busy === "save"} onClick={() => void save()}><FloppyDiskIcon weight="fill" />保存主题</button></section>
      <section className="editor-card"><h2>素材与安全预览</h2><div className="upload-box"><UploadSimpleIcon weight="duotone" size={28} /><div><strong>上传训练素材</strong><p>支持 txt、md、png、jpg、webp、mp4，单个文件不超过 16 MB。</p></div><label className="file-picker"><PaperclipIcon weight="bold" />选择文件<input aria-label="选择训练素材" type="file" accept=".txt,.md,.png,.jpg,.jpeg,.webp,.mp4" onChange={(event) => setAssetFile(event.target.files?.[0] ?? null)} /></label><input value={assetDescription} onChange={(event) => setAssetDescription(event.target.value)} placeholder="素材说明（可选）" /><button className="secondary-action" disabled={!assetFile || busy === "upload"} onClick={() => void upload()}>上传素材</button></div>
        {detail?.assets.length ? <ul className="asset-list">{detail.assets.map((asset) => <li key={asset.id}><PaperclipIcon weight="fill" /><span><strong>{asset.filename}</strong><small>{asset.asset_type} · {Math.ceil(asset.byte_size / 1024)} KB</small></span></li>)}</ul> : <p className="muted-copy">素材会保存在 Docker 卷中，不进入代码仓库。</p>}
        <div className="preview-box"><label>预览问题<input aria-label="预览问题" value={previewQuery} onChange={(event) => setPreviewQuery(event.target.value)} placeholder="输入一条客户问题" /></label><button className="secondary-action" disabled={!selectedId || busy === "preview"} onClick={() => void runPreview()}><PlayCircleIcon weight="fill" />预览回复</button>{preview && <div className={preview.handoff_required ? "preview-result risk" : "preview-result"}><strong>{preview.handoff_required ? "安全策略：转人工" : preview.matched ? "命中训练主题" : "未命中训练主题"}</strong><p>{preview.reply}</p></div>}</div>
      </section></div>
      <section className="version-card"><div><h2>发布版本</h2><p>每次发布都会生成不可变快照；回滚将生成新的当前版本，不覆盖历史。</p></div><div className="version-actions"><select aria-label="回滚版本" value={rollbackVersion ?? ""} onChange={(event) => setRollbackVersion(event.target.value ? Number(event.target.value) : null)} disabled={!versions.length}>{!versions.length && <option value="">暂无可回滚版本</option>}{versions.map((version) => <option key={version.id} value={version.version}>版本 {version.version} · {version.status}</option>)}</select><button className="secondary-action" disabled={rollbackVersion === null || busy === "rollback"} onClick={() => void rollback()}><ArrowClockwiseIcon weight="bold" />回滚版本</button></div></section>
    </section>
  </main>;
}
