"use strict";

const $ = (id) => document.getElementById(id);

function api(path, opts) {
  return fetch(path, Object.assign({ headers: { "Content-Type": "application/json" } }, opts))
    .then(async (r) => {
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.detail || r.statusText || "请求失败");
      return data;
    });
}

function fmtTime(ts) {
  if (!ts) return "-";
  const diff = Date.now() - ts * 1000;
  if (diff < 60e3) return "刚刚";
  if (diff < 3600e3) return Math.floor(diff / 60e3) + " 分钟前";
  if (diff < 86400e3) return Math.floor(diff / 3600e3) + " 小时前";
  const d = new Date(ts * 1000);
  return `${d.getMonth() + 1}-${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function fmtTokens(n) {
  if (!n) return "0";
  return n >= 1000 ? (n / 1000).toFixed(1) : String(n);
}

let timer = null;
let sessionTimer = null;
let busy = false;
let curSession = null;

/* ---------- 登录 ---------- */
function showLogin() {
  $("app-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
  $("password").focus();
}

function showApp() {
  $("login-view").classList.add("hidden");
  $("app-view").classList.remove("hidden");
  refreshAll();
  if (timer) clearInterval(timer);
  timer = setInterval(refreshStatus, 5000);
  if (sessionTimer) clearInterval(sessionTimer);
  sessionTimer = setInterval(refreshSessions, 15000);
  warmConsole();
}

function warmConsole() {
  fetch("/").then((r) => r.text()).then((html) => {
    const head = document.head;
    const add = (url, as, crossorigin) => {
      const l = document.createElement("link");
      l.rel = "preload";
      l.as = as;
      if (crossorigin) l.crossOrigin = "anonymous";
      l.href = url;
      head.appendChild(l);
    };
    let m;
    const rePlugin = /"url":"(\/plugins\/[^"]+)"/g;
    while ((m = rePlugin.exec(html))) add(m[1], "script", false);
    const reModule = /<script[^>]*type="module"[^>]*src="(\/assets\/[^"]+)"/g;
    while ((m = reModule.exec(html))) add(m[1], "script", true);
    const rePre = /<link[^>]*rel="modulepreload"[^>]*href="(\/assets\/[^"]+)"/g;
    while ((m = rePre.exec(html))) add(m[1], "script", true);
    const reCss = /<link[^>]*rel="stylesheet"[^>]*href="(\/assets\/[^"]+)"/g;
    while ((m = reCss.exec(html))) add(m[1], "style", false);
  }).catch(() => {});
}

/* ---------- 监控 ---------- */
function refreshStatus() {
  return api("/gw/status").then((s) => {
    const dot = $("status-dot");
    dot.className = "dot " + (s.running ? "on" : "off");
    $("status-text").textContent = s.running ? "DSH 运行中" : "DSH 未运行";
    $("stat-sessions").textContent = s.session_count ?? "-";
    $("stat-latest").textContent = fmtTime(s.latest_activity);
    $("btn-open").disabled = !s.running;
    $("conn-dot").className = "dot sm " + (s.running ? "on" : "off");
    return s;
  }).then(() => api("/gw/sessions")).then((d) => {
    const list = d.sessions || [];
    const working = list.filter((x) => x.working);
    $("stat-working").textContent = working.length || 0;
    const total = list.reduce((a, x) => a + (x.decodeTokens || 0), 0);
    $("stat-tokens").textContent = fmtTokens(total);
    const ul = $("working-list");
    ul.innerHTML = "";
    $("working-count").textContent = working.length ? "" : "暂无";
    if (!working.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "当前没有正在工作的会话";
      ul.appendChild(li);
      return;
    }
    working.slice(0, 5).forEach((s) => {
      const li = document.createElement("li");
      li.onclick = () => openPreview(s);
      const main = document.createElement("div");
      main.className = "sess-main";
      const t = document.createElement("div");
      t.className = "sess-title";
      t.textContent = s.title || "(未命名会话)";
      const sub = document.createElement("div");
      sub.className = "sess-sub";
      sub.textContent = `${s.workspace || ""} · ${fmtTime(s.lastActivity)}`;
      main.append(t, sub);
      li.appendChild(main);
      ul.appendChild(li);
    });
  }).catch(() => {
    $("status-dot").className = "dot off";
    $("status-text").textContent = "网关异常";
  });
}

/* ---------- 会话 ---------- */
function refreshSessions() {
  return api("/gw/sessions").then((d) => {
    const ul = $("session-list");
    ul.innerHTML = "";
    const list = d.sessions || [];
    if (!list.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "暂无会话";
      ul.appendChild(li);
      return;
    }
    list.slice(0, 50).forEach((s) => {
      const li = document.createElement("li");
      li.onclick = () => openPreview(s);
      const main = document.createElement("div");
      main.className = "sess-main";
      const t = document.createElement("div");
      t.className = "sess-title";
      t.textContent = s.title || "(未命名会话)";
      const sub = document.createElement("div");
      sub.className = "sess-sub";
      sub.textContent = `${s.workspace || ""} · ${s.turns} 轮 · ${fmtTokens(s.decodeTokens)}K token`;
      main.append(t, sub);
      const side = document.createElement("div");
      side.className = "sess-side";
      const tm = document.createElement("div");
      tm.className = "sess-time";
      tm.textContent = fmtTime(s.lastActivity);
      side.appendChild(tm);
      if (s.working) {
        const b = document.createElement("span");
        b.className = "badge work";
        b.textContent = "工作中";
        side.appendChild(b);
      } else if (s.turns > 0) {
        const b = document.createElement("span");
        b.className = "badge";
        b.textContent = "已完成";
        side.appendChild(b);
      }
      li.append(main, side);
      ul.appendChild(li);
    });
  }).catch(() => {});
}

/* ---------- 会话预览 ---------- */
let replyPolling = null;
let questionPolling = null;
let questionState = {};   // qid -> Set(选中项)

function openPreview(s) {
  curSession = s;
  $("preview-title").textContent = s.title || "(未命名会话)";
  const body = $("preview-body");
  const info = s.workspace ? `${s.workspace} · ${s.turns} 轮 · ${fmtTokens(s.decodeTokens)}K token` : "";
  body.innerHTML = `<div class="preview-info">${info}<br><span class="muted small">加载中…</span></div>`;
  $("preview-view").classList.remove("hidden");
  $("reply-box").classList.remove("hidden");
  $("reply-input").value = "";
  stopReplyPolling();
  stopQuestionPolling();
  loadPreview(s, false);
  questionPolling = setInterval(pollQuestions, 3000);
  pollQuestions();
}

function stopReplyPolling() {
  if (replyPolling) { clearInterval(replyPolling); replyPolling = null; }
}

function stopQuestionPolling() {
  if (questionPolling) { clearInterval(questionPolling); questionPolling = null; }
  questionState = {};
  const old = $("question-cards");
  if (old) old.remove();
}

function loadPreview(s, scrollToBottom) {
  api("/gw/session/" + encodeURIComponent(s.id) + "/tail?n=40").then((d) => {
    const body = $("preview-body");
    body.innerHTML = "";
    if (s.workspace) {
      const infoEl = document.createElement("div");
      infoEl.className = "preview-info";
      infoEl.textContent = `${s.workspace} · ${s.turns} 轮 · ${fmtTokens(s.decodeTokens)}K token`;
      body.appendChild(infoEl);
    }
    const f = d.filtered || {};
    const parts = [];
    if (f.thinking) parts.push(`思考 ${f.thinking} 条`);
    if (f.tools) parts.push(`工具调用 ${f.tools} 条`);
    if (parts.length) {
      const note = document.createElement("div");
      note.className = "filter-note";
      note.textContent = "已隐藏：" + parts.join(" · ");
      body.appendChild(note);
    }
    const entries = d.entries || [];
    if (!entries.length) {
      body.innerHTML += '<div class="empty">该会话暂无对话内容</div>';
      return;
    }
    const merged = [];
    entries.forEach((e) => {
      const last = merged[merged.length - 1];
      if (last && last.role === e.role && e.role !== "user" && e.role !== "question") {
        last.text += "\n\n" + e.text;
      } else {
        merged.push({ role: e.role, time: e.time, text: e.text });
      }
    });
    merged.forEach((e) => {
      const b = document.createElement("div");
      const isQ = e.role === "question";
      b.className = "bubble " + (e.role === "user" ? "user" : isQ ? "assistant question" : "assistant");
      const who = document.createElement("div");
      who.className = "who";
      who.textContent = e.role === "user" ? "我" : isQ ? "DSH 提问" : "DSH";
      const txt = document.createElement("div");
      txt.className = "txt";
      txt.textContent = e.text;
      b.append(who, txt);
      if (e.role === "user" && e.time) {
        const tm = document.createElement("div");
        tm.className = "time";
        tm.textContent = new Date(e.time).toLocaleString("zh-CN", { hour12: false });
        b.appendChild(tm);
      }
      body.appendChild(b);
    });
    if (scrollToBottom) body.scrollTop = body.scrollHeight;
  }).catch((err) => {
    $("preview-body").innerHTML = '<div class="empty">加载失败: ' + err.message + "</div>";
  });
}

function appendBubble(role, text) {
  const body = $("preview-body");
  const b = document.createElement("div");
  b.className = "bubble " + role;
  const who = document.createElement("div");
  who.className = "who";
  who.textContent = role === "user" ? "我" : "DSH";
  const txt = document.createElement("div");
  txt.className = "txt";
  txt.textContent = text;
  b.append(who, txt);
  body.appendChild(b);
  body.scrollTop = body.scrollHeight;
}

function sendReply() {
  if (!curSession) return;
  const input = $("reply-input");
  const text = input.value.trim();
  if (!text) return;
  const btn = $("reply-send");
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "Asia/Shanghai";
  input.value = "";
  btn.disabled = true;
  appendBubble("user", text);
  const wait = document.createElement("div");
  wait.className = "filter-note";
  wait.id = "reply-waiting";
  wait.textContent = "已发送，等待 DSH 回复…";
  $("preview-body").appendChild(wait);
  api("/gw/session/" + encodeURIComponent(curSession.id) + "/send", {
    method: "POST",
    body: JSON.stringify({ text, tz }),
  }).then(() => {
    const sentAt = Date.now();
    let tries = 0;
    replyPolling = setInterval(() => {
      tries++;
      api("/gw/session/" + encodeURIComponent(curSession.id) + "/tail?n=6").then((d) => {
        const entries = d.entries || [];
        const last = entries[entries.length - 1];
        const done = last && last.role === "assistant" && last.time > sentAt - 10000;
        if (done || tries >= 36) {
          stopReplyPolling();
          btn.disabled = false;
          loadPreview(curSession, true);
        }
      }).catch(() => {
        if (tries >= 36) {
          stopReplyPolling();
          btn.disabled = false;
        }
      });
    }, 5000);
  }).catch((err) => {
    btn.disabled = false;
    const w = $("reply-waiting");
    if (w) w.textContent = "发送失败：" + err.message;
  });
}

/* ---------- 选择题 ---------- */
function pollQuestions() {
  if (!curSession) return;
  api("/gw/questions?sid=" + encodeURIComponent(curSession.id)).then((d) => {
    const list = d.questions || [];
    const rpcIds = list.map((q) => q.rpcId);
    const card = $("question-cards");
    if (!list.length) {
      if (card) card.remove();
      return;
    }
    if (card && card.dataset.rpc === rpcIds.join(",")) return; // 已渲染同一批
    renderQuestions(list);
  }).catch(() => {});
}

function renderQuestions(list) {
  stopQuestionPolling();  // 渲染后停止轮询，答题完成再重新开始
  const old = $("question-cards");
  if (old) old.remove();
  const wrap = document.createElement("div");
  wrap.id = "question-cards";
  wrap.dataset.rpc = list.map((q) => q.rpcId).join(",");
  wrap.className = "qcard";
  const title = document.createElement("div");
  title.className = "qtitle";
  title.textContent = "DSH 向你提问";
  wrap.appendChild(title);
  list.forEach((batch) => {
    (batch.questions || []).forEach((q) => {
      const box = document.createElement("div");
      box.className = "qbox";
      const qt = document.createElement("div");
      qt.className = "qtext";
      qt.textContent = q.question || q.header || q.id;
      box.appendChild(qt);
      const opts = q.options || [];
      if (opts.length) {
        const optWrap = document.createElement("div");
        optWrap.className = "qopts";
        opts.forEach((o) => {
          const b = document.createElement("button");
          b.type = "button";
          b.className = "qopt";
          b.textContent = o.label;
          b.onclick = () => {
            const sel = questionState[q.id] = questionState[q.id] || new Set();
            if (q.multiSelect) {
              if (sel.has(o.label)) { sel.delete(o.label); b.classList.remove("sel"); }
              else { sel.add(o.label); b.classList.add("sel"); }
            } else {
              sel.clear();
              sel.add(o.label);
              optWrap.querySelectorAll(".qopt").forEach((x) => x.classList.remove("sel"));
              b.classList.add("sel");
            }
          };
          optWrap.appendChild(b);
        });
        box.appendChild(optWrap);
      }
      const submit = document.createElement("button");
      submit.type = "button";
      submit.className = "btn primary qsubmit";
      submit.textContent = "提交选择";
      submit.onclick = () => {
        const answers = [];
        let any = false;
        (list[0].questions || []).forEach((qq) => {
          const sel = questionState[qq.id] || new Set();
          if (sel.size) any = true;
          answers.push({ id: qq.id, selected: [...sel] });
        });
        if (!any) return;
        submit.disabled = true;
        submit.textContent = "已提交…";
        api("/gw/session/" + encodeURIComponent(curSession.id) + "/answer", {
          method: "POST",
          body: JSON.stringify({ rpcId: batch.rpcId, answers }),
        }).then(() => {
          submit.textContent = "✓ 已提交，等待回复";
          const sentAt = Date.now();
          let tries = 0;
          replyPolling = setInterval(() => {
            tries++;
            api("/gw/session/" + encodeURIComponent(curSession.id) + "/tail?n=8").then((d) => {
              const entries = d.entries || [];
              const last = entries[entries.length - 1];
              if (last && last.role === "assistant" && last.time > sentAt - 10000) {
                stopReplyPolling();
                const w2 = $("question-cards");
                if (w2) w2.remove();
                questionPolling = setInterval(pollQuestions, 3000);
                loadPreview(curSession, true);
              } else if (tries >= 36) {
                stopReplyPolling();
                questionPolling = setInterval(pollQuestions, 3000);
              }
            }).catch(() => { if (tries >= 36) { stopReplyPolling(); questionPolling = setInterval(pollQuestions, 3000); } });
          }, 5000);
        }).catch((err) => {
          submit.disabled = false;
          submit.textContent = "提交失败：" + err.message;
        });
      };
      box.appendChild(submit);
      wrap.appendChild(box);
    });
  });
  $("preview-body").appendChild(wrap);
  const pb = $("preview-body");
  pb.scrollTop = pb.scrollHeight;
}

function closePreview() {
  $("preview-view").classList.add("hidden");
  $("reply-box").classList.add("hidden");
  stopReplyPolling();
  stopQuestionPolling();
  curSession = null;
}

/* ---------- 日志 ---------- */
function refreshLog() {
  return api("/gw/log?n=300").then((d) => {
    $("log-view").textContent = d.log || "（暂无日志）";
    const lv = $("log-view");
    lv.scrollTop = lv.scrollHeight;
  }).catch(() => {});
}

function refreshAll() {
  refreshStatus();
  refreshSessions();
}

/* ---------- 控制 ---------- */
function setCtrlMsg(text, kind) {
  const el = $("ctrl-msg");
  el.textContent = text || "";
  el.className = "msg " + (kind || "");
}

function doControl(act) {
  const labels = { start: "启动", stop: "停止", restart: "重启" };
  if (act === "stop" && !confirm("确认停止 DSH？正在跑的任务会被中断。")) return;
  if (act === "restart" && !confirm("确认重启 DSH？")) return;
  if (busy) return;
  busy = true;
  setCtrlMsg("执行中…", "ok");
  api("/gw/control/" + act, { method: "POST" }).then((d) => {
    setCtrlMsg(d.detail || labels[act] + "成功", "ok");
    refreshAll();
  }).catch((e) => {
    setCtrlMsg(e.message, "err");
  }).finally(() => { busy = false; });
}

/* ---------- Tab 切换 ---------- */
function switchTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.add("hidden"));
  $("tab-" + name).classList.remove("hidden");
  document.querySelectorAll(".tabbtn").forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
  const titles = { monitor: "监控", sessions: "会话", log: "日志" };
  $("app-title").textContent = titles[name];
  if (name === "sessions") refreshSessions();
  if (name === "log") refreshLog();
}

/* ---------- 事件绑定 ---------- */
$("login-form").addEventListener("submit", (e) => {
  e.preventDefault();
  api("/gw/login", { method: "POST", body: JSON.stringify({ password: $("password").value }) })
    .then(() => { showApp(); })
    .catch((err) => {
      const el = $("login-msg");
      el.textContent = err.message;
      el.className = "msg err";
    });
});

$("logout-btn").addEventListener("click", () => {
  api("/gw/logout", { method: "POST" }).finally(() => showLogin());
});

$("btn-open").addEventListener("click", () => { location.href = "/"; });
$("btn-start").addEventListener("click", () => doControl("start"));
$("btn-stop").addEventListener("click", () => doControl("stop"));
$("btn-restart").addEventListener("click", () => doControl("restart"));
$("refresh-log").addEventListener("click", () => refreshLog());
$("refresh-sessions").addEventListener("click", () => refreshSessions());
$("preview-back").addEventListener("click", () => closePreview());
$("reply-send").addEventListener("click", () => sendReply());
$("reply-input").addEventListener("keydown", (e) => { if (e.key === "Enter") sendReply(); });
document.querySelectorAll(".tabbtn").forEach((b) =>
  b.addEventListener("click", () => switchTab(b.dataset.tab)));

/* ---------- 初始视图 ---------- */
api("/gw/session").then((s) => { if (s.authed) showApp(); else showLogin(); }).catch(() => showLogin());