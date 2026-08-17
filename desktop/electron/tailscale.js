'use strict';
// Tailscale 集成：探测 / 状态 / 唤醒连接 / HTTPS 转发（对齐 start-everything.ps1 的 1/3 步骤）。
const fs = require('fs');
const { execFile } = require('child_process');

function findTailscale() {
  const candidates = [
    process.env.TAILSCALE_EXE,
    'C:\\Program Files\\Tailscale\\tailscale.exe',
    'C:\\Program Files (x86)\\Tailscale\\tailscale.exe',
  ].filter(Boolean);
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

function run(exe, args, timeoutMs = 30000) {
  return new Promise((resolve) => {
    execFile(
      exe,
      args,
      { timeout: timeoutMs, windowsHide: true, maxBuffer: 16 * 1024 * 1024 },
      (err, stdout) => {
        resolve({ ok: !err, stdout: stdout || '', err: err ? String(err.message || err) : '' });
      }
    );
  });
}

async function getInfo(exe) {
  if (!exe) return { installed: false, online: false, dnsName: '', ip: '', relay: '' };
  const r = await run(exe, ['status', '--json'], 15000);
  if (!r.ok) {
    return { installed: true, online: false, dnsName: '', ip: '', relay: '', error: r.err };
  }
  try {
    const j = JSON.parse(r.stdout);
    const self = j.Self || {};
    const ips = self.TailscaleIPs || [];
    return {
      installed: true,
      online: !!self.Online,
      dnsName: String(self.DNSName || '').replace(/\.$/, ''),
      ip: ips.length ? String(ips[0]) : '',
      relay: String(self.Relay || ''),
    };
  } catch (_) {
    return { installed: true, online: false, dnsName: '', ip: '', relay: '', error: 'status json 解析失败' };
  }
}

async function wakeService() {
  // Tailscale Windows 服务未运行时启动它（对齐 ps1：Start-Service Tailscale）
  const r = await run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', 'Start-Service -Name Tailscale -ErrorAction SilentlyContinue'],
    20000
  );
  return r.ok;
}

async function connect(exe) {
  if (!exe) return { ok: false, detail: '未找到 Tailscale' };
  await wakeService();
  const up = await run(exe, ['up', '--timeout', '25s'], 40000);
  // 轮询上线状态（最多 20 秒）
  for (let i = 0; i < 20; i++) {
    const info = await getInfo(exe);
    if (info.online) return { ok: true, online: true, info, detail: up.stdout || '' };
    await new Promise((r) => setTimeout(r, 1000));
  }
  const info = await getInfo(exe);
  return { ok: !!info.online, online: !!info.online, info, detail: up.stdout || up.err };
}

async function ensureServe(exe, port) {
  if (!exe) return { ok: false, detail: '未找到 Tailscale' };
  const st = await run(exe, ['serve', 'status'], 15000);
  if (st.stdout.includes(`http://127.0.0.1:${port}`)) {
    return { ok: true, already: true };
  }
  const r = await run(exe, ['serve', '--bg', String(port)], 30000);
  return { ok: r.ok, already: false, detail: r.err };
}

async function resetServe(exe) {
  if (!exe) return { ok: false };
  const r = await run(exe, ['serve', 'reset'], 20000);
  return { ok: r.ok };
}

module.exports = { findTailscale, getInfo, connect, ensureServe, resetServe, wakeService, run };
