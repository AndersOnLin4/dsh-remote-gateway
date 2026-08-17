# DSH Remote Gateway

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 打造的远程控制套件：一个网关、三种形态——网页、Windows 桌面端、Android App。在家、在办公室、出门在外，都能监控 DSH 会话、回复消息、处理 agent 提问。

DSH 官方没有鉴权层，直接远程暴露等于把电脑交给网络。本项目在最前面加一道登录墙，并提供数据过滤与多端界面，远程体验与本地一致。

## 组件

| 组件 | 目录 | 说明 |
|---|---|---|
| 远程网关 | `gateway/` | FastAPI 服务：登录鉴权、监控控制、数据过滤、反向代理、SSE 推送，所有 DSH 交互的唯一入口 |
| Windows 桌面端 | `desktop/` | Electron 托盘程序：一键启停、进程守护、开机自启、Tailscale 唤醒、自动登录面板 |
| Android App | `app/` | Flutter 原生客户端：监控/会话/回复/答题/日志 + 实时推送 + 备用地址自动切换 |

## 亮点

**安全第一**：DSH 永远只监听 127.0.0.1，公网可达的只有网关。每机随机 24 位密码、HMAC 签名会话、登录限速、操作审计；外网默认走 Tailscale 私有组网，公网零端口暴露。

**数据最小化**：思考过程与工具细节在网关侧源头剔除，手机收到的只有"提问 + 最终回答"，单次请求 KB 级；会话内容点击才加载，只解压尾部一小段。

**实时推送**：SSE 事件流覆盖状态变化、agent 提问、会话新写入三类事件，App 秒级同步并弹本地通知，不再依赖轮询节奏。

**弱网友好**：接口 gzip 压缩（体积约 -80%）、尾段增量协议 + 结果缓存（重复轮询毫秒级）、断线指数退避自动重连、备用地址自动切换（外网与局域网线路无缝切换）。

**桌面零运维**：托盘状态灯、进程崩溃自动拉起（只补位不抢占）、启动自动拉起缺失服务、Tailscale 自动唤醒与 HTTPS 转发、一键开机自启，替代全部 cmd 脚本。

**状态判真**：探活区分"端口拒绝"与"连接超时"——DSH 繁忙时绝不误报"未运行"，控制操作用强制探测一次定生死。

## 快速上手

### 网页版

1. 双击 `install.cmd` 安装（自动建虚拟环境、装依赖、探测 DSH 目录）
2. 双击 `start-everything.cmd` 启动（Tailscale → DSH → 网关，终端打印访问地址与密码）
3. 浏览器打开打印的局域网或 HTTPS 地址，输入密码登录

前置条件：Windows + Python 3.10+，已安装 DeepSeek Harness（`dsh web` 可用）。

### Windows 桌面端

从 Release 下载 `DSH-Gateway-Desktop-*-portable.exe`，双击即用：托盘常驻、窗口自动登录仪表盘、首次运行弹出手机访问信息（地址与密码一键复制）。详见 [desktop/README.md](desktop/README.md)。

### Android App

从 Release 下载 `DSH-Gateway-Android-*-arm64.apk` 侧载安装。登录建议：主地址填 Tailscale HTTPS 域名，备用地址填局域网地址（如 `http://192.168.1.100:8080`），App 会自动选择可用线路。详见 [app/README.md](app/README.md)。

## 目录结构

```
gateway/       FastAPI 网关（登录 / 监控 / 控制 / 代理 / SSE）
desktop/       Windows 桌面端（Electron）
app/           Android App（Flutter）
install.cmd / start-everything.cmd / stop-everything.cmd   网页版三键脚本
DSH网关-App化方案.md    App 化方案文档
```

## 版本记录

### v1.3.0（2026-08-17）

- 新增 Windows 桌面端（`desktop/`）：托盘守护、一键启停、崩溃自动拉起、启动自动补位、Tailscale 唤醒与 HTTPS 转发、自动登录面板、访问信息窗口
- 新增 Android App（`app/`）：监控/会话/回复/答题/日志、SSE 推送通知、内嵌完整控制台、备用地址自动切换
- 网关新增 `/gw/events` SSE 推送（状态/提问/会话更新三类事件）、JSON gzip 压缩、尾段增量协议与结果缓存
- 探活防抖 + 拒绝/超时区分，DSH 繁忙期不再误报"未运行"
- README 重写

### v1.1.0（2026-08-16）

- 通用化安装、一键启动/关闭、Tailscale 外网访问、MIT 开源

### v1.0.0（2026-08-16）

- 首个版本：移动端监控/会话/日志、轻量会话浏览、直接回复、选择题交互、登录鉴权

## 许可

MIT License，© 2026 AndersOnLin4，联系邮箱 andersonlin1107@gmail.com
