# 🖥️ DSH 手机远程网关

> 为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 量身打造的轻量远程网关：手机浏览器即可**监控、回复、答题**，全程无需打开完整控制台。

[![Release](https://img.shields.io/badge/Release-v1.1.0-brightgreen)](https://github.com/AndersOnLin4/dsh-remote-gateway/releases/latest)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)
![License](https://img.shields.io/badge/License-MIT-blue)

DSH 本身没有鉴权层，直接远程暴露等于把电脑交给网络。本网关在最前面加一道**登录墙 + 数据过滤 + 移动端界面**：会话状态一眼可见、历史只留"提问与最终回答"、想回复随时发消息、agent 提问直接点选作答。

---

## ✨ 产品特点

- **每台机器独一无二的随机密码**：安装时用加密级随机数自动生成 24 位登录密码，免去"默认密码人人知道"的隐患，可随时自行更换
- **隐私零暴露**：外网走 Tailscale 私有隧道（tailnet only），公网端口零开放；登录限速 + 审计日志双保险
- **数据最小化**：思考/工具细节在网关侧源头剔除，手机收到的永远是"提问 + 最终回答"，单次请求 KB 级
- **手机流量友好**：gzip 压缩（体积 -80%）、静态资源永久缓存、并行预加载、仪表盘预热，首次打开后基本秒开
- **三键开箱**：`install.cmd` 安装 → `start-everything.cmd` 启动 → `stop-everything.cmd` 关闭，全流程自动化

## 🧭 功能一览

| 📱 监控 | 💬 会话 | 🎯 交互 | 🛡 安全与体验 |
| --- | --- | --- | --- |
| 运行状态实时显示 | 标题/工作区/轮数/token 一览 | 直接回复消息 | 登录鉴权（HMAC 会话） |
| 工作中的会话高亮 | 过滤后对话预览（KB 级秒开） | agent 选择题点选作答 | 登录限速 + 审计日志 |
| 会话总数与 token 统计 | 每轮只留最终回答 | 完整控制台直达 | 每机独立随机密码 |
| DSH 实时日志 | 长文完整显示（4000 字） | 完整控制台移动端适配 | 局域网 + 私有隧道双通道 |

---

## 📖 功能详情

### 📱 移动端仪表盘

- 底部三 Tab：**监控 / 会话 / 日志**
- 监控页：DSH 运行状态灯、工作中会话数、会话总数、总 token 用量、最后活动时间、启动/重启/停止按钮
- 会话页：列表直接显示标题、工作区、轮数、token、最后活动；工作中的会话带橙色呼吸徽标
- 日志页：DSH 进程实时日志（自动滚动）

### 💬 轻量会话浏览

- 会话内容**点击才加载**，只解压会话文件尾部一小段（zstd 多帧流），KB 级秒开
- 数据层过滤：思考（reasoning）、工具调用（edit/pwsh 等）、上下文注入在源头剔除，只保留"用户提问 + 每轮最终中文回复 + 选择题"
- 连续回复自动合并为气泡对话；单条文本上限 4000 字
- 会话列表本身读取 DSH 索引缓存，不碰大文件

### ✍️ 直接回复

- 预览页底部输入框，回车即发，自动轮询等待 agent 回复并刷新
- 复刻 DSH 的 `session.prompt` RPC，回复正常进入 DSH 会话流程，电脑上打开 DSH 同样可见
- 全程无需打开完整控制台，流量友好

### 🎯 选择题交互

- 网关常驻监听 DSH 事件流，捕获 agent 的 `ask_user_question` 提问（含选项与 rpcId）
- 预览页自动弹出选项卡片：单选/多选、点选高亮、一键提交
- 提交后 agent 继续执行，回复自动刷新

### 🖥️ 完整控制台

- 反向代理 DSH 原版 Web UI（HTTP + WebSocket，通过其浏览器信任栅栏）
- 移动端适配注入：输入框贴底固定、16px 防 iOS 聚焦缩放、侧栏整屏展开、点击会话自动收起、抑制输入法误弹
- 历史响应数据层过滤（剔除流式碎片等），加载从 MB 级降到 KB 级

### 🔒 安全设计

- 登录密码：加密级随机生成（每机不同），HMAC-SHA256 签名会话 Cookie（7 天）
- 登录限速：5 次失败锁定 5 分钟；关键操作写审计日志
- DSH 永远只监听 127.0.0.1，公网可达的只有网关
- 外网推荐 Tailscale（tailnet only），公网端口零开放

---

## 🏃 快速上手

1. **安装**：双击 `install.cmd`——自动检测 Python → 建虚拟环境 → 装依赖 → 探测 DSH 安装目录
2. **启动**：双击 `start-everything.cmd`——自动唤醒 Tailscale → 拉起 DSH → 启动网关 → 打印全部访问地址与登录密码
3. **访问**：浏览器打开终端显示的局域网或外网地址，输入终端显示的登录密码
4. **关闭**：双击 `stop-everything.cmd`——停止网关 + DSH + HTTPS 转发

> 前置条件：Windows + Python 3.10+（勾选 Add to PATH）+ 已安装 DeepSeek Harness（`dsh web` 可用）。
> 未自动探测到 DSH 时，按提示在 `gateway\.env` 手动配置 `HARNESS_ROOT` / `DSH_HOME`。

## 📲 外网访问（Tailscale）

1. 电脑系统托盘开启并登录 Tailscale（本项目只自动唤醒与连接，登录需你完成一次）
2. 手机安装 Tailscale App，登录同一账号
3. 手机浏览器打开 `https://<电脑名>.<你的tailnet>.ts.net/dashboard`

> 手机流量下若偶尔走中继变慢，换网络或稍等片刻即会恢复直连。

## ❓ 常见问题

**登录密码在哪？**
启动器终端会直接打印；也可查看 `gateway\.env` 的 `GATEWAY_PASSWORD=`。每台机器安装时自动生成，各不相同；修改该行后重启网关即可换密码。

**Tailscale 显示未连接？**
本项目不代登录：先在系统托盘开启 Tailscale 并登录一次，再双击 `start-everything.cmd`。

**手机打不开页面？**
确认电脑上 `start-everything.cmd` 显示"网关 运行中 ✓"；局域网访问需同一 Wi-Fi，外网访问需 Tailscale 已登录。

**历史会话看不到思考过程？**
这是刻意设计：思考/工具细节在网关侧过滤，手机只保留"提问 + 最终回答"，既省流量也保护上下文。

**如何更新到新版本？**
`git pull` 后重启网关即可；`gateway\.env` 与 DSH 数据不受影响。

## 📜 版本记录

### v1.1.0（2026-08-16）
- 通用化：`install.cmd` 一键安装、DSH 目录自动探测、任意主机开箱即用
- 一键启动/关闭：Tailscale 自动唤醒与连接、一键关闭（网关 + DSH + HTTPS 转发）
- 启动器美化：作者横幅与落款、终端直印访问地址与登录密码
- 完善开源信息：MIT 许可证、README 重写

### v1.0.0（2026-08-16）
- 首个版本：移动端监控/会话/日志、轻量会话浏览、直接回复、选择题交互、完整控制台移动端适配、数据层过滤、登录鉴权、Tailscale 外网

## 🔨 技术栈与构建

<details>
<summary>点击展开</summary>

- 后端：Python 3.10+ / FastAPI / uvicorn / httpx / zstandard
- 前端：原生 HTML/JS/CSS（移动优先，无构建步骤）
- 外网：Tailscale（私有隧道 + HTTPS Serve）
- 安装：`install.cmd` 自动完成 venv + 依赖 + DSH 探测

```text
gateway/
├── app/
│   ├── main.py        # 路由 / 鉴权中间件 / 控制接口
│   ├── config.py      # 配置与密钥（DSH 目录自动探测）
│   ├── auth.py        # HMAC 会话、登录限速
│   ├── monitor.py     # 状态探测 / 日志
│   ├── dsh_manager.py # DSH 进程托管
│   ├── sessions.py    # 会话索引 / zstd 尾段读取 / 发消息
│   └── proxy.py       # 反向代理 / 注入 / 压缩 / 缓存 / 数据过滤 / 问题监听
└── static/            # 移动端前端
```

</details>

## 🗺 规划中的功能

- **token 用量统计面板**：按会话/日期的成本与用量图表
- **告警推送**：DSH 崩溃或长时间无输出时推送通知到手机
- **断线自动重连**：弱网下 WebSocket 自适应

## 📄 许可与联系

- 代码采用 [MIT License](LICENSE) 开源许可
- © 2026 AndersOnLin4
- 联系邮箱：andersonlin1107@gmail.com
- 更多项目：[github.com/AndersOnLin4/moneybook](https://github.com/AndersOnLin4/moneybook)
