'use strict';
// 进程守护：端口探测、DSH/网关的启动/停止/重启、崩溃自动拉起。
// 原则：只补位不抢占 —— 端口已被监听则"收养"（标记外部启动），绝不重复拉起或强杀。
const fs = require('fs');
const net = require('net');
const path = require('path');
const { spawn, execFile } = require('child_process');

const RESTART_WINDOW_MS = 120 * 1000;
const MAX_RESTARTS = 3;
const RESTART_DELAY_MS = 3000;
const LISTEN_TIMEOUT_S = 30;

const state = {
  dsh: { listening: false, owned: false, autoRestart: true, child: null, pid: null, restarts: [], lastError: '' },
  gw: { listening: false, owned: false, autoRestart: true, child: null, pid: null, restarts: [], lastError: '' },
};

let onChange = () => {};
let settings = {}; // { supervise: boolean }

function setSettings(s) {
  settings = s || {};
}

function setOnChange(fn) {
  onChange = fn || (() => {});
}

function notify() {
  onChange(state);
}

function checkPort(host, port, timeoutMs = 800) {
  return new Promise((resolve) => {
    if (!port || !host) return resolve(false);
    const sock = net.connect({ host, port });
    let done = false;
    const finish = (ok) => {
      if (!done) {
        done = true;
        sock.destroy();
        resolve(ok);
      }
    };
    sock.setTimeout(timeoutMs);
    sock.on('connect', () => finish(true));
    sock.on('error', () => finish(false));
    sock.on('timeout', () => finish(false));
  });
}

function spawnProc(exe, args, cwd, env, logFile) {
  let out = 'ignore';
  if (logFile) {
    try {
      fs.mkdirSync(path.dirname(logFile), { recursive: true });
      out = fs.openSync(logFile, 'a');
    } catch (_) {
      out = 'ignore';
    }
  }
  return spawn(exe, args, {
    cwd,
    env: Object.assign({}, process.env, env),
    stdio: ['ignore', out, out],
    windowsHide: true,
  });
}

async function waitListen(host, port, seconds) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    if (await checkPort(host, port)) return true;
    await new Promise((r) => setTimeout(r, 400));
  }
  return await checkPort(host, port);
}

function watchChild(kind, child, restartFn) {
  child.on('exit', (code) => {
    const wasOwned = state[kind].owned;
    state[kind].child = null;
    state[kind].pid = null;
    state[kind].listening = false;
    state[kind].owned = false;
    if (wasOwned && state[kind].autoRestart !== false && settings.supervise !== false) {
      const now = Date.now();
      state[kind].restarts = state[kind].restarts.filter((t) => now - t < RESTART_WINDOW_MS);
      if (state[kind].restarts.length >= MAX_RESTARTS) {
        state[kind].lastError = `${kind === 'dsh' ? 'DSH' : '网关'} 短时间内多次崩溃，已停止自动重启`;
        notify();
        return;
      }
      state[kind].restarts.push(now);
      state[kind].lastError = `${kind === 'dsh' ? 'DSH' : '网关'} 已退出(code=${code})，${RESTART_DELAY_MS / 1000}s 后自动重启`;
      notify();
      setTimeout(() => {
        restartFn().catch((e) => {
          state[kind].lastError = '自动重启失败: ' + (e.message || e);
          notify();
        });
      }, RESTART_DELAY_MS);
    } else {
      notify();
    }
  });
}

// ---------------- 网关 ----------------

async function startGateway(cfg, extraEnv = {}) {
  if (state.gw.child) return { ok: true, adopted: false, detail: '网关已由本程序托管' };
  if (await checkPort('127.0.0.1', cfg.gatewayPort)) {
    state.gw.listening = true;
    state.gw.owned = false;
    state.gw.lastError = '';
    notify();
    return { ok: true, adopted: true, detail: '网关已在运行（外部启动，已收养）' };
  }
  if (!fs.existsSync(path.join(cfg.gatewayDir, 'start_all.py'))) {
    return { ok: false, detail: `网关目录不存在: ${cfg.gatewayDir}` };
  }
  const py = cfg.pythonExe || {};
  let child;
  try {
    child = spawnProc(
      py.exe || 'py',
      [...(py.args || []), 'start_all.py'],
      cfg.gatewayDir,
      Object.assign({ GATEWAY_HOST: '127.0.0.1', GATEWAY_PORT: String(cfg.gatewayPort) }, extraEnv)
    );
  } catch (e) {
    return { ok: false, detail: '网关启动失败: ' + (e.message || e) };
  }
  state.gw.child = child;
  state.gw.pid = child.pid;
  state.gw.owned = true;
  state.gw.autoRestart = true;
  watchChild('gw', child, () => startGateway(cfg, extraEnv));
  const up = await waitListen('127.0.0.1', cfg.gatewayPort, LISTEN_TIMEOUT_S);
  if (up) {
    state.gw.listening = true;
    state.gw.lastError = '';
    notify();
    return { ok: true, adopted: false, pid: child.pid };
  }
  state.gw.lastError = `网关启动超时（${LISTEN_TIMEOUT_S}s 内未监听端口）`;
  notify();
  return { ok: false, detail: state.gw.lastError };
}

async function stopGateway() {
  if (!state.gw.listening && !state.gw.child) return { ok: true, detail: '网关未在运行' };
  if (state.gw.owned && state.gw.child) {
    state.gw.autoRestart = false; // 主动停止，禁止守护回拉
    state.gw.owned = false;
    const child = state.gw.child;
    try {
      child.kill();
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 600));
    state.gw.listening = false;
    state.gw.child = null;
    state.gw.pid = null;
    notify();
    return { ok: true, detail: '已停止网关（本程序托管的实例）' };
  }
  return { ok: false, detail: '网关由外部启动，请用 stop-everything.cmd 关闭' };
}

// ---------------- DSH ----------------

async function startDsh(cfg) {
  if (state.dsh.child) return { ok: true, adopted: false, detail: 'DSH 已由本程序托管' };
  if (await checkPort('127.0.0.1', cfg.dshPort)) {
    state.dsh.listening = true;
    state.dsh.owned = false;
    state.dsh.lastError = '';
    notify();
    return { ok: true, adopted: true, detail: 'DSH 已在运行（外部启动，已收养）' };
  }
  if (!cfg.dshBin || !fs.existsSync(cfg.dshBin)) {
    return { ok: false, detail: '未找到 DSH 可执行文件: ' + (cfg.dshBin || '(HARNESS_ROOT 未探测到)') };
  }
  if (!cfg.nodeExe || !fs.existsSync(cfg.nodeExe)) {
    return { ok: false, detail: '未找到 Node 运行时: ' + (cfg.nodeExe || '') };
  }
  const hr = cfg.harnessRoot;
  const env = {
    NPM_CONFIG_PREFIX: path.join(hr, 'npm'),
    NPM_CONFIG_CACHE: path.join(hr, 'npm-cache'),
    DSH_HOME: cfg.dshHome,
    PATH: `${path.join(hr, 'nodejs')};${path.join(hr, 'npm')};${process.env.PATH || ''}`,
  };
  let child;
  try {
    child = spawnProc(
      cfg.nodeExe,
      [cfg.dshBin, '--profile', 'web', '--host', '127.0.0.1', '--port', String(cfg.dshPort)],
      hr,
      env,
      path.join(hr, 'logs', 'dsh.log')
    );
  } catch (e) {
    return { ok: false, detail: 'DSH 启动失败: ' + (e.message || e) };
  }
  state.dsh.child = child;
  state.dsh.pid = child.pid;
  state.dsh.owned = true;
  state.dsh.autoRestart = true;
  watchChild('dsh', child, () => startDsh(cfg));
  const up = await waitListen('127.0.0.1', cfg.dshPort, LISTEN_TIMEOUT_S);
  if (up) {
    state.dsh.listening = true;
    state.dsh.lastError = '';
    notify();
    return { ok: true, adopted: false, pid: child.pid };
  }
  state.dsh.lastError = `DSH 启动超时（${LISTEN_TIMEOUT_S}s 内未监听端口）`;
  notify();
  return { ok: false, detail: state.dsh.lastError };
}

function stopDshByPort(port) {
  // 与网关 dsh_manager.stop 语义一致：按端口找监听进程并结束。
  const ps =
    `Get-NetTCPConnection -LocalPort ${port} -State Listen -ErrorAction SilentlyContinue ` +
    '| Select-Object -First 1 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }';
  return new Promise((resolve) => {
    execFile('powershell', ['-NoProfile', '-NonInteractive', '-Command', ps], { timeout: 30000 }, (err) => {
      resolve(err ? false : true);
    });
  });
}

async function stopDsh(cfg) {
  if (!state.dsh.listening && !state.dsh.child) return { ok: true, detail: 'DSH 未在运行' };
  state.dsh.autoRestart = false; // 主动停止，禁止守护回拉
  await stopDshByPort(cfg.dshPort);
  if (state.dsh.child) {
    try {
      state.dsh.child.kill();
    } catch (_) {}
    state.dsh.child = null;
    state.dsh.pid = null;
    state.dsh.owned = false;
  }
  const freed = !(await waitListen('127.0.0.1', cfg.dshPort, 15));
  state.dsh.listening = !freed;
  notify();
  return { ok: freed, detail: freed ? '已停止 DSH' : 'DSH 停止未完全生效（端口仍被占用）' };
}

async function restartDsh(cfg) {
  const stop = await stopDsh(cfg);
  if (!stop.ok) return stop;
  await new Promise((r) => setTimeout(r, 500));
  return startDsh(cfg);
}

// ---------------- 轮询 ----------------

async function watch(cfg) {
  const [dshUp, gwUp] = await Promise.all([
    checkPort('127.0.0.1', cfg.dshPort),
    checkPort('127.0.0.1', cfg.gatewayPort),
  ]);
  let changed = false;
  if (dshUp !== state.dsh.listening) {
    state.dsh.listening = dshUp;
    if (dshUp && !state.dsh.child) {
      state.dsh.owned = false; // 外部进程补位 → 收养
    }
    changed = true;
  }
  if (gwUp !== state.gw.listening) {
    state.gw.listening = gwUp;
    if (gwUp && !state.gw.child) {
      state.gw.owned = false;
    }
    changed = true;
  }
  if (changed) notify();
  return state;
}

function quitCleanup() {
  // 退出时只回收本程序托管的子进程，外部进程一律不动。
  for (const kind of ['dsh', 'gw']) {
    if (state[kind].owned && state[kind].child) {
      try {
        state[kind].child.kill();
      } catch (_) {}
      state[kind].child = null;
    }
  }
}

module.exports = {
  state,
  setSettings,
  setOnChange,
  checkPort,
  startGateway,
  stopGateway,
  startDsh,
  stopDsh,
  restartDsh,
  watch,
  quitCleanup,
};
