'use strict';
// 生成应用图标：256x256 PNG（圆角深底 + 绿色状态点）+ Windows ICO（内嵌 PNG）。
// 用法：node scripts/gen-icon.js → build/icon.png + build/icon.ico
const fs = require('fs');
const path = require('path');
const { encodePNG } = require('../electron/png');

const SIZE = 256;
const rgba = Buffer.alloc(SIZE * SIZE * 4);

function setPx(x, y, r, g, b, a) {
  const i = (y * SIZE + x) * 4;
  rgba[i] = r;
  rgba[i + 1] = g;
  rgba[i + 2] = b;
  rgba[i + 3] = a;
}

function roundedRectAlpha(x, y, r) {
  const half = (SIZE - 1) / 2;
  const qx = Math.abs(x - half) - (half - r);
  const qy = Math.abs(y - half) - (half - r);
  const dx = Math.max(qx, 0);
  const dy = Math.max(qy, 0);
  const d = Math.hypot(dx, dy) + Math.min(Math.max(qx, qy), 0) - r;
  return Math.max(0, Math.min(1, 0.5 - d));
}

const BG_R = 56;
const DOT_R = 84;
const center = SIZE / 2;

for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const a = roundedRectAlpha(x, y, BG_R);
    if (a > 0) setPx(x, y, 17, 24, 39, Math.round(a * 255));
    const d = Math.hypot(x - center, y - center);
    const da = Math.max(0, Math.min(1, DOT_R - d + 0.5));
    if (da > 0) setPx(x, y, 46, 204, 113, Math.round(da * 255));
  }
}

const png = encodePNG(SIZE, SIZE, rgba);
const buildDir = path.join(__dirname, '..', 'build');
fs.mkdirSync(buildDir, { recursive: true });
fs.writeFileSync(path.join(buildDir, 'icon.png'), png);

// ICO 容器：6 字节头 + 16 字节目录项 + PNG 数据（Vista+ 支持 PNG 压缩 ICO）
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(1, 4);
const entry = Buffer.alloc(16);
entry[0] = 0; // 宽 0 = 256
entry[1] = 0; // 高 0 = 256
entry[2] = 0; // 调色板
entry[3] = 0; // 保留
entry.writeUInt16LE(1, 4); // 平面数
entry.writeUInt16LE(32, 6); // 位深
entry.writeUInt32LE(png.length, 8);
entry.writeUInt32LE(22, 12); // 数据偏移
fs.writeFileSync(path.join(buildDir, 'icon.ico'), Buffer.concat([header, entry, png]));
console.log('icons generated:', path.join(buildDir, 'icon.png'), path.join(buildDir, 'icon.ico'));
