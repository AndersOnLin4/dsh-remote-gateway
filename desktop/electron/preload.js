'use strict';
// 渲染进程桥：只暴露最小 API 面（状态查询 / 控制 / 打开 / 自启 / 日志）。
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dshDesktop', {
  getState: () => ipcRenderer.invoke('state:get'),
  action: (kind, act) => ipcRenderer.invoke('action', kind, act),
  getAutostart: () => ipcRenderer.invoke('autostart:get'),
  setAutostart: (v) => ipcRenderer.invoke('autostart:set', !!v),
  openDashboard: () => ipcRenderer.invoke('open:dashboard'),
  openConsole: () => ipcRenderer.invoke('open:console'),
  quit: (stopOwned) => ipcRenderer.invoke('app:quit', !!stopOwned),
  getLog: () => ipcRenderer.invoke('log:get'),
  getAccessInfo: () => ipcRenderer.invoke('accessinfo:get'),
  copyText: (text) => ipcRenderer.invoke('copy:text', text),
  openInfo: () => ipcRenderer.invoke('open:info'),
  onState: (cb) => ipcRenderer.on('state', (_e, s) => cb(s)),
  onAccessInfo: (cb) => ipcRenderer.on('accessinfo', (_e, a) => cb(a)),
});
