# DSH 网关桌面端（desktop）

B 线产物：Windows 托盘守护程序。一个程序搞定"启动 / 守护 / 看面板 / 打开控制台"，替代 `start-everything.cmd` 的黑窗操作。

## 能力

- **托盘状态灯**：绿色=全部正常 · 橙色=DSH 异常 · 红色=网关未运行（悬停可见详情与工作中会话数）
- **进程守护**：本程序拉起的 DSH/网关崩溃后自动重启（2 分钟内最多 3 次，超限停止并提示）；外部启动的进程一律"只补位不抢占"
- **一键控制**：启动/重启/停止 DSH、启动/停止网关（外部启动的网关不会被强杀）
- **自动登录面板**：窗口直接载入网关仪表盘——本机读 `gateway/.env` 密码自动登录，免输密码
- **开机自启**：托盘菜单或面板页一键开关（注册表 Run，仅打包版可用）
- **完整控制台**：一键用系统浏览器打开 DSH 原版 UI（127.0.0.1:3080）
- **Tailscale 自动唤醒**：启动时自动唤醒 Tailscale 服务 → `tailscale up` → 检查/配置 `tailscale serve --bg 8080` HTTPS 转发（对齐 `start-everything.ps1` 的 1/3 步骤；登录仍需你手动完成一次）
- **手机访问信息**：首次运行自动弹出（之后托盘菜单随时可开）——局域网地址、Tailscale HTTPS 地址、WireGuard 地址、登录密码（可显示/一键复制），再也不用开终端找地址和密码

## 开发

```bash
cd desktop
npm install
npm start          # 启动桌面端（窗口 + 托盘）
npm run smoke      # 无界面冒烟测试：探测/登录/独立实例启停生命周期（8090 测试端口，不碰 3080/8080）
```

## 打包

```bash
npm run dist       # 产出 dist/DSH-Gateway-Desktop-<版本>-portable.exe（单文件免安装）
```

> 受限网络环境（无法从 github 下载 Electron 二进制）时，可在 `package.json` 的 build 配置中临时加入
> `"electronDist": "dist-cache/electron-v<版本>-win32-x64.zip"`，并自行放置对应 zip 到 `desktop/dist-cache/`。

## 配置

- 设置文件：`%APPDATA%\dsh-gateway-desktop\settings.json`（`gatewayDir` / `dshPort` / `autostart` / `supervise`）
- 网关目录识别顺序：`settings.gatewayDir` → 环境变量 `DSH_GATEWAY_DIR` → `G:\Andersonlin4-design 手机远控项目\gateway` → 仓库内 `gateway/`
- 密码读自 `gateway/.env` 的 `GATEWAY_PASSWORD`（无则面板要求手动登录）

## 安全说明

- 桌面端只访问回环 `127.0.0.1:8080/3080`，不新增任何对外端口
- 退出默认保留 DSH/网关继续运行；"退出并停止托管进程"仅回收本程序拉起的子进程，并按 `stop-everything.ps1` 语义重置 Tailscale HTTPS 转发（Tailscale 连接本身保持）
- 停止 DSH 的语义与网关 Web 面板一致（按端口结束监听进程）
- Tailscale 只做唤醒与连接，**不代登录**：首次需在系统托盘 Tailscale 图标手动登录一次
