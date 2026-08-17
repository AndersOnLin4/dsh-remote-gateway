'use strict';
// 系统托盘：状态灯图标 + 右键菜单（状态概览 / 控制 / 自启 / 退出）。
const { Tray, Menu, nativeImage, shell } = require('electron');
const { dotIcon } = require('./png');

const COLORS = {
  green: { r: 46, g: 204, b: 113 },
  orange: { r: 243, g: 156, b: 18 },
  red: { r: 231, g: 76, b: 60 },
  gray: { r: 149, g: 165, b: 166 },
};

let tray = null;
let currentColor = '';
let trayHandlers = null;

function colorFor(state) {
  if (!state.gw.listening) return 'red'; // 网关挂 → 红
  if (!state.dsh.listening) return 'orange'; // DSH 异常 → 橙
  return 'green';
}

function createTray(handlers) {
  tray = new Tray(nativeImage.createFromBuffer(dotIcon(COLORS.gray)));
  tray.setToolTip('DSH 网关桌面端');
  tray.on('click', () => handlers.showWindow());
  tray.on('double-click', () => handlers.showWindow());
  return tray;
}

function updateTray(state, extra = {}) {
  if (!tray) return;
  const color = colorFor(state);
  if (color !== currentColor) {
    currentColor = color;
    tray.setImage(nativeImage.createFromBuffer(dotIcon(COLORS[color])));
  }
  const dshTxt = state.dsh.listening ? '运行中' : '已停止';
  const gwTxt = state.gw.listening ? '运行中' : '未运行';
  const gwOwn = state.gw.listening ? (state.gw.owned ? '（本程序托管）' : '（外部）') : '';
  const working = extra.workingCount != null ? ` · 工作中 ${extra.workingCount}` : '';
  tray.setToolTip(`DSH: ${dshTxt} · 网关: ${gwTxt}${gwOwn}${working}`);

  const a = extra.access || {};
  const handlers = trayHandlers.handlers;
  const menu = Menu.buildFromTemplate([
    { label: `DSH: ${dshTxt}${state.dsh.owned ? '（本程序托管）' : '（外部）'}`, enabled: false },
    { label: `网关: ${gwTxt}${gwOwn}`, enabled: false },
    { type: 'separator' },
    { label: '打开面板', click: () => handlers.showWindow() },
    { label: '打开完整控制台 (DSH 3080)', click: () => shell.openExternal('http://127.0.0.1:3080') },
    { type: 'separator' },
    { label: '启动 DSH', enabled: !state.dsh.listening, click: () => handlers.action('dsh', 'start') },
    { label: '重启 DSH', enabled: state.dsh.listening, click: () => handlers.action('dsh', 'restart') },
    { label: '停止 DSH', enabled: state.dsh.listening, click: () => handlers.action('dsh', 'stop') },
    { type: 'separator' },
    { label: '启动网关', enabled: !state.gw.listening, click: () => handlers.action('gw', 'start') },
    {
      label: '停止网关',
      enabled: state.gw.listening && state.gw.owned,
      click: () => handlers.action('gw', 'stop'),
    },
    { type: 'separator' },
    {
      label: `📱 ${a.lanUrl || '局域网地址: 未检测到'}`,
      enabled: false,
    },
    {
      label: a.tsOnline && a.httpsUrl
        ? `🔒 ${a.httpsUrl}`
        : 'Tailscale: 未连接（需在托盘手动登录一次）',
      enabled: false,
    },
    { label: '复制局域网地址', enabled: !!a.lanUrl, click: () => handlers.copyText(a.lanUrl) },
    { label: '复制 HTTPS 地址', enabled: !!a.httpsUrl, click: () => handlers.copyText(a.httpsUrl) },
    { label: '复制登录密码', enabled: !!a.passwordSet, click: () => handlers.copyText(a.password) },
    { label: '手机访问信息窗口', click: () => handlers.openInfo() },
    { type: 'separator' },
    {
      label: '开机自启',
      type: 'checkbox',
      checked: !!extra.autostart,
      enabled: extra.autostartAvailable !== false,
      click: (item) => handlers.setAutostart(item.checked),
    },
    { type: 'separator' },
    { label: '退出（保留 DSH/网关运行）', click: () => handlers.quit(false) },
    { label: '退出并停止本程序托管的进程', click: () => handlers.quit(true) },
  ]);
  tray.setContextMenu(menu);
}

function setTrayHandlers(handlers) {
  trayHandlers = { handlers };
}

module.exports = { createTray, updateTray, setTrayHandlers, COLORS };
