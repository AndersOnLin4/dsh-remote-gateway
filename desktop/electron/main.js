'use strict';
// 主进程入口：生命周期 / 单实例 / 窗口 / 托盘 / IPC / 轮询 / Tailscale / 访问信息。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { app, BrowserWindow, clipboard, ipcMain, session, shell } = require('electron');

const paths = require('./paths');
const supervisor = require('./supervisor');
const api = require('./api');
const trayMod = require('./tray');
const tailscaleMod = require('./tailscale');

// 统一 userData（开发与打包一致），保证设置落盘位置稳定
app.setPath('userData', path.join(app.getPath('appData'), 'dsh-gateway-desktop'));
app.setAppUserModelId('com.andersonlin.dshgateway');

const SMOKE = process.argv.includes('--smoke-test');
const HIDDEN = process.argv.includes('--hidden');

let cfg = null;
let win = null;
let infoWin = null;
let isQuitting = false;
let quitStopOwned = false;
let autostartEnabled = false;
let workingCount = null;
let tsExe = null;
let tsInfo = null;
let lanIp = '';

function log(...args) {
  console.log(`[desktop ${new Date().toISOString()}]`, ...args);
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => showWindow());
}

// ---------------- 窗口 ----------------

function createWindow() {
  win = new BrowserWindow({
    width: 480,
    height: 860,
    minWidth: 400,
    minHeight: 600,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: '#111827',
    title: 'DSH 网关',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault();
      win.hide();
    }
  });
  win.once('ready-to-show', () => {
    if (!HIDDEN && !SMOKE) win.show();
  });
  loadMain();
}

function showWindow() {
  if (!win || win.isDestroyed()) createWindow();
  else {
    win.show();
    win.focus();
  }
}

function currentUrl() {
  try {
    return win && !win.isDestroyed() ? win.webContents.getURL() : '';
  } catch (_) {
    return '';
  }
}

function loadShell(reason) {
  if (!win || win.isDestroyed()) return;
  win
    .loadFile(path.join(__dirname, '..', 'renderer', 'shell.html'), { query: { reason: reason || '' } })
    .catch(() => {});
}

async function ensureLogin(port, password) {
  if (!password) return { ok: false, detail: '未读到网关密码（gateway/.env 缺失 GATEWAY_PASSWORD）' };
  const s = await api.getSession(port);
  if (s.data && s.data.authed === true) return { ok: true };
  const r = await api.login(port, password);
  if (!r.ok) return { ok: false, status: r.status, detail: '登录失败' };
  try {
    await session.defaultSession.cookies.set({
      url: `http://127.0.0.1:${port}`,
      name: 'gw_session',
      value: r.token,
      path: '/',
      secure: false,
      httpOnly: false,
      sameSite: 'lax',
      expirationDate: Math.floor(Date.now() / 1000) + 6 * 86400,
    });
  } catch (e) {
    log('cookie 注入失败', e);
  }
  return { ok: true };
}

async function loadMain() {
  if (!win || win.isDestroyed()) return;
  const port = cfg.gatewayPort;
  const gwUp = await supervisor.checkPort('127.0.0.1', port);
  if (!gwUp) {
    loadShell('gw-down');
    return;
  }
  const r = await ensureLogin(port, cfg.password);
  if (!r.ok) {
    loadShell(r.status === 401 ? 'login-fail' : 'load-fail');
    return;
  }
  try {
    await win.loadURL(`http://127.0.0.1:${port}/dashboard`);
    log('窗口已加载仪表盘（自动登录）', `http://127.0.0.1:${port}/dashboard`);
  } catch (e) {
    log('loadURL 失败', e);
    loadShell('load-fail');
  }
}

// ---------------- 动作 ----------------

async function runAction(kind, act) {
  let r;
  if (kind === 'gw') {
    if (act === 'start') r = await supervisor.startGateway(cfg);
    else if (act === 'stop') r = await supervisor.stopGateway();
  } else if (kind === 'dsh') {
    if (act === 'start') r = await supervisor.startDsh(cfg);
    else if (act === 'stop') r = await supervisor.stopDsh(cfg);
    else if (act === 'restart') r = await supervisor.restartDsh(cfg);
  }
  if (!r) r = { ok: false, detail: '未知操作' };
  log('action', kind, act, JSON.stringify(r));
  if (kind === 'gw' && act === 'start' && r.ok && win && !win.isDestroyed()) loadMain();
  pushState();
  return r;
}

function setAutostart(v) {
  if (!app.isPackaged) return { ok: false, detail: '开发模式不可用，打包后生效' };
  autostartEnabled = !!v;
  app.setLoginItemSettings({ openAtLogin: autostartEnabled, path: process.execPath, args: ['--hidden'] });
  paths.saveSettings(cfg, { autostart: autostartEnabled });
  pushState();
  return { ok: true };
}

const handlers = {
  showWindow,
  action: (kind, act) => runAction(kind, act),
  setAutostart: (v) => setAutostart(v),
  openInfo,
  copyText: (text) => {
    try {
      clipboard.writeText(String(text || ''));
      return { ok: true };
    } catch (e) {
      return { ok: false, detail: String(e) };
    }
  },
  quit: (stopOwned) => {
    quitStopOwned = !!stopOwned;
    isQuitting = true;
    app.quit();
  },
};

// ---------------- 状态推送 ----------------

function sanitizeProc(p) {
  return {
    listening: !!p.listening,
    owned: !!p.owned,
    pid: p.pid || null,
    lastError: p.lastError || '',
    restarts: p.restarts.length,
  };
}

function pushState() {
  if (!cfg) return;
  const s = {
    dsh: sanitizeProc(supervisor.state.dsh),
    gw: sanitizeProc(supervisor.state.gw),
    gatewayPort: cfg.gatewayPort,
    dshPort: cfg.dshPort,
    autostart: autostartEnabled,
    autostartAvailable: app.isPackaged,
    passwordSet: !!cfg.password,
    gatewayDir: cfg.gatewayDir,
    workingCount,
  };
  if (win && !win.isDestroyed()) {
    win.webContents.send('state', s);
    // 网关恢复上线且窗口正停在离线页 → 自动切回仪表盘
    if (s.gw.listening && currentUrl().startsWith('file://')) loadMain();
  }
  trayMod.updateTray(supervisor.state, {
    autostart: autostartEnabled,
    autostartAvailable: app.isPackaged,
    workingCount,
    access: computeAccessInfo(),
  });
  return s;
}

async function pollWorking() {
  if (!cfg || !supervisor.state.gw.listening) {
    workingCount = null;
    return;
  }
  try {
    const st = await api.getStatus(cfg.gatewayPort);
    if (st.data && typeof st.data.working === 'number') workingCount = st.data.working;
  } catch (_) {
    workingCount = null;
  }
}

// ---------------- 访问信息（局域网 / Tailscale / 密码） ----------------

function getLanIp() {
  const ifs = os.networkInterfaces();
  const cands = [];
  for (const name of Object.keys(ifs)) {
    if (/vmware|vethernet|virtualbox|loopback|bluetooth/i.test(name)) continue;
    for (const it of ifs[name] || []) {
      if (it.family === 'IPv4' && !it.internal && !it.address.startsWith('169.254')) {
        cands.push(it.address);
      }
    }
  }
  return cands[0] || '';
}

function computeAccessInfo() {
  const port = cfg ? cfg.gatewayPort : 8080;
  const ts = tsInfo || {};
  return {
    lanUrl: lanIp ? `http://${lanIp}:${port}/dashboard` : '',
    httpsUrl: ts.online && ts.dnsName ? `https://${ts.dnsName}` : '',
    tsUrl: ts.online && ts.ip ? `${ts.ip}:${port}` : '',
    tsInstalled: !!tsExe,
    tsOnline: !!ts.online,
    tsRelay: ts.relay || '',
    tsError: ts.error || '',
    password: cfg ? cfg.password : '',
    passwordSet: !!(cfg && cfg.password),
    dshUp: supervisor.state.dsh.listening,
    gwUp: supervisor.state.gw.listening,
  };
}

function openInfo() {
  if (infoWin && !infoWin.isDestroyed()) {
    infoWin.show();
    infoWin.focus();
    return;
  }
  infoWin = new BrowserWindow({
    width: 420,
    height: 640,
    minWidth: 360,
    minHeight: 520,
    autoHideMenuBar: true,
    backgroundColor: '#111827',
    title: '手机访问信息',
    parent: win && !win.isDestroyed() ? win : undefined,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  infoWin.loadFile(path.join(__dirname, '..', 'renderer', 'info.html')).catch(() => {});
  infoWin.on('closed', () => {
    infoWin = null;
  });
}

function pushInfo() {
  if (infoWin && !infoWin.isDestroyed()) {
    infoWin.webContents.send('accessinfo', computeAccessInfo());
  }
}

async function refreshTs() {
  tsExe = tailscaleMod.findTailscale();
  if (!tsExe) {
    tsInfo = { installed: false, online: false, dnsName: '', ip: '', relay: '' };
  } else {
    tsInfo = await tailscaleMod.getInfo(tsExe);
  }
  pushInfo();
}

async function tailscaleStartup() {
  // 对齐 start-everything.ps1 的 1/3：唤醒服务 → up → 轮询上线 → 配置 HTTPS 转发
  tsExe = tailscaleMod.findTailscale();
  if (!tsExe) {
    log('Tailscale 未安装，跳过（局域网访问不受影响）');
    tsInfo = { installed: false, online: false, dnsName: '', ip: '', relay: '' };
    pushInfo();
    return;
  }
  log('Tailscale 唤醒与连接…');
  const r = await tailscaleMod.connect(tsExe);
  tsInfo = r.info || (await tailscaleMod.getInfo(tsExe));
  if (tsInfo.online) {
    log('Tailscale 已连接 ✓', tsInfo.dnsName || tsInfo.ip || '');
  } else {
    log('Tailscale 仍未连接（需你手动登录一次：托盘 Tailscale 图标 → 登录，本项目不代登录）');
  }
  const serve = await tailscaleMod.ensureServe(tsExe, cfg.gatewayPort);
  log('Tailscale HTTPS 转发', serve.already ? '已就绪 ✓' : serve.ok ? '已配置 ✓' : '配置失败：' + (serve.detail || ''));
  pushInfo();
}

// ---------------- IPC ----------------

function readTail(file, n) {
  try {
    const fd = fs.openSync(file, 'r');
    const size = fs.fstatSync(fd).size;
    const len = Math.min(size, 256 * 1024);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    fs.closeSync(fd);
    return buf.toString('utf8').split(/\r?\n/).slice(-n).join('\n');
  } catch (_) {
    return '';
  }
}

function registerIpc() {
  ipcMain.handle('state:get', () => pushState());
  ipcMain.handle('action', (_e, kind, act) => runAction(kind, act));
  ipcMain.handle('autostart:get', () => ({ ok: true, value: autostartEnabled, available: app.isPackaged }));
  ipcMain.handle('autostart:set', (_e, v) => setAutostart(!!v));
  ipcMain.handle('open:dashboard', async () => {
    showWindow();
    await loadMain();
    return { ok: true };
  });
  ipcMain.handle('open:console', () => {
    shell.openExternal(`http://127.0.0.1:${cfg.dshPort}`);
    return { ok: true };
  });
  ipcMain.handle('accessinfo:get', () => computeAccessInfo());
  ipcMain.handle('copy:text', (_e, text) => handlers.copyText(text));
  ipcMain.handle('open:info', () => {
    openInfo();
    return { ok: true };
  });
  ipcMain.handle('app:quit', (_e, stopOwned) => {
    quitStopOwned = !!stopOwned;
    isQuitting = true;
    app.quit();
    return { ok: true };
  });
  ipcMain.handle('log:get', () => {
    if (!cfg) return '';
    const files = [
      cfg.harnessRoot ? path.join(cfg.harnessRoot, 'logs', 'gateway.out.log') : null,
      cfg.harnessRoot ? path.join(cfg.harnessRoot, 'logs', 'dsh.log') : null,
    ].filter(Boolean);
    for (const f of files) {
      const t = readTail(f, 120);
      if (t) return `${f}\n${'─'.repeat(48)}\n${t}`;
    }
    return '（暂无日志文件）';
  });
}

// ---------------- 冒烟测试 ----------------

async function smokeTest() {
  const results = [];
  const check = (name, ok, detail = '') => {
    results.push({ name, ok, detail });
    log(`[SMOKE] ${ok ? 'PASS' : 'FAIL'} ${name} ${detail ? '— ' + detail : ''}`);
  };
  try {
    cfg = paths.loadConfig();
    check('配置加载', !!cfg.gatewayDir, `gatewayDir=${cfg.gatewayDir}`);
    check('Python 解释器', !!cfg.pythonExe && fs.existsSync(cfg.pythonExe.exe), cfg.pythonExe && cfg.pythonExe.exe);
    check('DSH bin.js', !!cfg.dshBin && fs.existsSync(cfg.dshBin), cfg.dshBin || '(未探测到)');
    check('Node 运行时', !!cfg.nodeExe && fs.existsSync(cfg.nodeExe), cfg.nodeExe || '');

    const dshUp = await supervisor.checkPort('127.0.0.1', cfg.dshPort);
    const gwUp = await supervisor.checkPort('127.0.0.1', cfg.gatewayPort);
    check('DSH 端口已运行', dshUp, `127.0.0.1:${cfg.dshPort}`);
    check('网关端口已运行', gwUp, `127.0.0.1:${cfg.gatewayPort}`);

    // Tailscale：只读探测，不在冒烟测试中变更任何状态
    const tse = tailscaleMod.findTailscale();
    if (tse) {
      const ti = await tailscaleMod.getInfo(tse);
      check('Tailscale 探测', !!ti, `exe=${tse}`);
      check('Tailscale 状态读取', !!ti, `online=${ti.online} dns=${ti.dnsName || '(无)'} ip=${ti.ip || '(无)'}`);
    } else {
      check('Tailscale 探测（跳过：未安装）', true, 'skip');
    }

    if (gwUp && cfg.password) {
      const r = await api.login(cfg.gatewayPort, cfg.password);
      check('网关登录', r.ok, r.ok ? '' : `HTTP ${r.status}`);
      if (r.ok) {
        const s = await api.getSession(cfg.gatewayPort);
        check('会话鉴权', !!(s.data && s.data.authed === true));
        const st = await api.getStatus(cfg.gatewayPort);
        check('网关状态接口', !!(st.data && st.data.running === true), JSON.stringify(st.data || {}).slice(0, 160));
      }
    } else {
      check('网关 API（跳过：未运行或无密码）', true, 'skip');
    }

    // 独立测试实例的生命周期：端口 8090，绝不触碰 3080/8080
    supervisor.setSettings({ supervise: false });
    const testCfg = Object.assign({}, cfg, { gatewayPort: 8090 });
    const r1 = await supervisor.startGateway(testCfg, { GATEWAY_HOST: '127.0.0.1', GATEWAY_PORT: '8090' });
    check('测试网关启动(8090)', r1.ok, r1.detail || '');
    if (r1.ok && !r1.adopted) {
      const up = await supervisor.checkPort('127.0.0.1', 8090);
      check('8090 已监听', up);
      const s2 = await supervisor.stopGateway();
      check('测试网关停止', s2.ok, s2.detail || '');
      await new Promise((r) => setTimeout(r, 800));
      const freed = !(await supervisor.checkPort('127.0.0.1', 8090));
      check('8090 已释放', freed);
    } else if (r1.ok && r1.adopted) {
      check('测试网关启动(8090 已被占用?)', false, '端口被外部占用，跳过启停验证');
    }
  } catch (e) {
    check('异常', false, String((e && e.stack) || e));
  }
  const fails = results.filter((r) => !r.ok);
  log(`[SMOKE] 结果: ${results.length - fails.length}/${results.length} 通过`);
  // 结果落盘（打包版是 GUI 程序，stdout 不可见，验证靠此文件）
  try {
    fs.writeFileSync(
      path.join(app.getPath('userData'), 'smoke-result.json'),
      JSON.stringify({ time: new Date().toISOString(), results, pass: results.length - fails.length, total: results.length }, null, 2),
      'utf8'
    );
  } catch (_) {}
  app.exit(fails.length ? 1 : 0);
}

// ---------------- 生命周期 ----------------

app.whenReady().then(async () => {
  cfg = paths.loadConfig();
  log('配置', JSON.stringify({
    gatewayDir: cfg.gatewayDir,
    pythonExe: cfg.pythonExe && cfg.pythonExe.exe,
    harnessRoot: cfg.harnessRoot,
    dshHome: cfg.dshHome,
    gatewayPort: cfg.gatewayPort,
    dshPort: cfg.dshPort,
    passwordSet: !!cfg.password,
  }));
  supervisor.setSettings({ supervise: cfg.settings.supervise !== false });
  supervisor.setOnChange(() => pushState());
  registerIpc();

  if (SMOKE) {
    await smokeTest();
    return;
  }

  trayMod.setTrayHandlers(handlers);
  trayMod.createTray(handlers);
  autostartEnabled = app.isPackaged
    ? app.getLoginItemSettings().openAtLogin
    : !!cfg.settings.autostart;
  lanIp = getLanIp();

  createWindow();
  setInterval(async () => {
    try {
      await supervisor.watch(cfg);
      pushState();
    } catch (e) {
      log('watch 异常', e);
    }
  }, 5000);
  setInterval(pollWorking, 15000);
  setInterval(() => refreshTs().catch(() => {}), 60000);
  pushState();

  // 一键启动语义（对齐 start-everything.cmd）：DSH/网关未运行则自动拉起。
  // 网关优先（start_all.py 会连带拉起 DSH）；网关在跑而 DSH 没跑则直接拉起 DSH。
  setTimeout(async () => {
    try {
      const gwUp = await supervisor.checkPort('127.0.0.1', cfg.gatewayPort);
      if (!gwUp) {
        log('网关未运行，自动启动…');
        const r = await supervisor.startGateway(cfg);
        log('自动启动网关:', JSON.stringify(r));
      } else {
        const dshUp = await supervisor.checkPort('127.0.0.1', cfg.dshPort);
        if (!dshUp) {
          log('DSH 未运行，自动启动…');
          const r = await supervisor.startDsh(cfg);
          log('自动启动 DSH:', JSON.stringify(r));
        }
      }
    } catch (e) {
      log('自动启动检查异常', e);
    }
  }, 3000);

  // Tailscale 唤醒 + HTTPS 转发（不阻塞主流程）
  tailscaleStartup().catch((e) => log('Tailscale 启动异常', e));

  // 首次运行：弹"手机访问信息"窗口，展示访问地址与密码
  if (!HIDDEN && !cfg.settings.infoShown) {
    setTimeout(() => {
      openInfo();
      paths.saveSettings(cfg, { infoShown: true });
    }, 2500);
  }
});

app.on('window-all-closed', () => {
  if (!isQuitting) {
    // 托盘常驻：关闭窗口不退出
  } else {
    app.quit();
  }
});

app.on('before-quit', () => {
  isQuitting = true;
  if (quitStopOwned) {
    supervisor.quitCleanup();
    // 对齐 stop-everything.ps1：完整关闭时重置 Tailscale HTTPS 转发（保持 Tailscale 连接）
    if (tsExe) tailscaleMod.resetServe(tsExe).catch(() => {});
  }
});
