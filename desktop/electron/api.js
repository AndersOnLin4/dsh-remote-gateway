'use strict';
// 网关 REST 客户端：登录、状态、控制。与 static/app.js 使用同一套 /gw/* 接口。
let token = '';

function baseUrl(port) {
  return `http://127.0.0.1:${port}`;
}

async function login(port, password) {
  const r = await fetch(`${baseUrl(port)}/gw/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password }),
  });
  if (!r.ok) return { ok: false, status: r.status };
  let tok = '';
  try {
    const cookies = typeof r.headers.getSetCookie === 'function' ? r.headers.getSetCookie() : [];
    const c = cookies.map((x) => x.split(';')[0]).find((x) => x.startsWith('gw_session='));
    if (c) tok = c.split('=').slice(1).join('=');
  } catch (_) {}
  if (tok) token = tok;
  return { ok: true, token: tok };
}

function setToken(tok) {
  token = tok || '';
}

async function req(port, pathname, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  if (token) headers.Cookie = `gw_session=${token}`;
  const r = await fetch(`${baseUrl(port)}${pathname}`, Object.assign({}, opts, { headers }));
  let data = null;
  try {
    data = await r.json();
  } catch (_) {}
  return { status: r.status, data };
}

async function getSession(port) {
  return req(port, '/gw/session');
}

async function getStatus(port) {
  return req(port, '/gw/status');
}

async function getSessions(port) {
  return req(port, '/gw/sessions');
}

async function getLog(port, n = 300) {
  return req(port, `/gw/log?n=${n}`);
}

async function control(port, action) {
  return req(port, `/gw/control/${action}`, { method: 'POST' });
}

module.exports = { login, setToken, getSession, getStatus, getSessions, getLog, control };
