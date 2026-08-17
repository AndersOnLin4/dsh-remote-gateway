'use strict';
// 路径探测与配置解析：找到网关目录 / .env / DSH 安装位置。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { app } = require('electron');

const REPO_ROOT = path.resolve(__dirname, '..', '..'); // desktop/electron -> desktop -> 仓库根

// 网关目录候选（按优先级）：真实安装目录优先（里面有 .env 与 venv），仓库副本兜底。
const GATEWAY_DIR_CANDIDATES = [
  'G:\\Andersonlin4-design 手机远控项目\\gateway',
  path.join(REPO_ROOT, 'gateway'),
];

function parseEnvFile(file) {
  const out = {};
  try {
    const text = fs.readFileSync(file, 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const s = line.trim();
      if (!s || s.startsWith('#') || !s.includes('=')) continue;
      const i = s.indexOf('=');
      out[s.slice(0, i).trim()] = s.slice(i + 1).trim();
    }
  } catch (_) {
    /* 无 .env 属正常（网关未安装） */
  }
  return out;
}

function detectHarnessRoot() {
  const candidates = [];
  for (const d of ['C', 'D', 'E', 'F', 'G', 'H']) {
    for (const n of ['harness', 'dsh', 'deepseek-harness']) candidates.push(`${d}:\\${n}`);
  }
  candidates.push(path.join(os.homedir(), 'harness'));
  for (const c of candidates) {
    if (fs.existsSync(path.join(c, 'dsh-home', 'sessions'))) return c;
  }
  return null;
}

function detectGatewayDir(settings) {
  if (settings && settings.gatewayDir && fs.existsSync(path.join(settings.gatewayDir, 'run.py'))) {
    return settings.gatewayDir;
  }
  if (process.env.DSH_GATEWAY_DIR && fs.existsSync(path.join(process.env.DSH_GATEWAY_DIR, 'run.py'))) {
    return process.env.DSH_GATEWAY_DIR;
  }
  for (const c of GATEWAY_DIR_CANDIDATES) {
    if (fs.existsSync(path.join(c, 'run.py'))) return c;
  }
  return GATEWAY_DIR_CANDIDATES[0]; // 都不存在时仍返回真实安装路径，方便报错提示
}

function findPython(gatewayDir) {
  const venvW = path.join(gatewayDir, '.venv', 'Scripts', 'pythonw.exe');
  const venv = path.join(gatewayDir, '.venv', 'Scripts', 'python.exe');
  if (fs.existsSync(venvW)) return { exe: venvW, args: [] };
  if (fs.existsSync(venv)) return { exe: venv, args: [] };
  return { exe: 'py', args: ['-3'] };
}

function loadConfig() {
  const userData = app.getPath('userData');
  const settingsFile = path.join(userData, 'settings.json');
  let settings = {};
  try {
    settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
  } catch (_) {
    /* 首次运行 */
  }

  const gatewayDir = detectGatewayDir(settings);
  const env = parseEnvFile(path.join(gatewayDir, '.env'));
  const harnessRoot = env.HARNESS_ROOT || process.env.HARNESS_ROOT || detectHarnessRoot() || null;
  const dshHome = env.DSH_HOME || process.env.DSH_HOME || (harnessRoot ? path.join(harnessRoot, 'dsh-home') : null);

  const nodeExe = harnessRoot ? path.join(harnessRoot, 'nodejs', 'node.exe') : null;
  const dshBin = harnessRoot
    ? path.join(harnessRoot, 'npm', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
    : null;

  return {
    repoRoot: REPO_ROOT,
    gatewayDir,
    settingsFile,
    settings,
    env,
    harnessRoot,
    dshHome,
    gatewayPort: Number(env.GATEWAY_PORT || (settings.gatewayPort ?? 8080)),
    dshPort: Number(settings.dshPort || 3080),
    password: env.GATEWAY_PASSWORD || '',
    pythonExe: findPython(gatewayDir),
    nodeExe,
    dshBin,
  };
}

function saveSettings(cfg, partial) {
  const next = Object.assign({}, cfg.settings, partial);
  try {
    fs.mkdirSync(path.dirname(cfg.settingsFile), { recursive: true });
    fs.writeFileSync(cfg.settingsFile, JSON.stringify(next, null, 2), 'utf8');
    cfg.settings = next;
    return { ok: true };
  } catch (e) {
    return { ok: false, detail: String(e.message || e) };
  }
}

module.exports = { loadConfig, saveSettings, parseEnvFile, detectGatewayDir, detectHarnessRoot, REPO_ROOT };
