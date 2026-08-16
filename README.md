# DSH 手机远程网关

在 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 前面加一层轻量网关：登录鉴权、手机端监控/回复、反向代理与数据过滤。手机浏览器即可查看会话状态、阅读过滤后的对话、直接回复，并处理 agent 的选择题——**全程无需打开完整控制台**。

> 安全提示：DSH 本身无鉴权且通常以高权限运行。本项目的一切远程访问都依赖网关的登录墙，请务必：使用强密码、选择私有隧道（如 Tailscale，tailnet only）、不要暴露到公网。

## 项目亮点 ✨

- **开箱即用、三键完成**：`install.cmd` 安装 → `start-everything.cmd` 启动 → `stop-everything.cmd` 关闭。全流程自动化：自动探测 Python / DSH 安装目录、自动唤醒并连接 Tailscale、自动配置 HTTPS 转发、终端直接打印访问地址与登录密码。
- **每台机器独一无二的随机密码**：安装时用加密级随机数自动生成 24 位登录密码，**每台机器、每次安装都不相同**，免去"默认密码人人知道"的隐患；密码持久保存在 `gateway\.env`，可随时自行更换。
- **隐私零暴露**：外网走 Tailscale 私有隧道（tailnet only），公网端口零开放；登录限速 + 审计日志双保险。
- **数据最小化**：历史会话只在网关侧解压并过滤，思考/工具细节在源头剔除，手机收到的永远是"提问 + 最终回答"，单次请求 KB 级。
- **手机流量友好**：gzip 压缩（体积 -80%）、静态资源永久缓存、并行预加载、仪表盘预热——首次打开后基本秒开。
- **轻量即全功能**：不用开完整控制台就能发消息、答选择题；需要完整界面时一键直达（已做移动端适配）。

## 功能

- **移动端仪表盘**：三 Tab（监控 / 会话 / 日志），会话列表直接显示标题、工作区、轮数、token 用量、活跃状态（工作中的会话高亮）
- **轻量会话浏览**：只解压会话文件尾部，返回"用户提问 + 每轮最终中文回复 + 选择题"，KB 级秒开
- **直接回复**：复刻 DSH 的 `session.prompt` RPC，仪表盘内即可回消息，自动轮询等待回复
- **选择题交互**：常驻监听 DSH 事件流，捕获 agent 提问，选项卡片点选提交，agent 继续执行
- **完整控制台**：反向代理 DSH 原版 UI（HTTP + WebSocket，通过其浏览器信任栅栏），注入移动端适配（输入框贴底、侧栏整屏、防 iOS 缩放、自动收起）
- **数据层过滤**：代理改写 `session.history` 响应，剔除流式碎片/思考/工具调用/上下文注入——历史加载从 MB 级降到 KB 级，界面只留对话正文
- **安全**：HMAC 会话 Cookie、登录限速、操作审计日志、每机独立随机密码

## 架构

```
手机浏览器 → Tailscale(私有隧道/HTTPS) → 网关(FastAPI :8080) → DSH(仅 127.0.0.1:3080)
```

- 网关承担：登录鉴权、静态仪表盘、`/gw/*` API、反向代理（Host/Origin 重写过 DSH 信任栅栏）、gzip 压缩、静态资源 immutable 缓存、HTML 注入、数据过滤、问题监听
- 外网推荐 Tailscale + Serve（tailnet only，公网零暴露），启动器自动完成识别/唤醒/配置

## 快速开始（其他主机通用安装）

**前置条件**：Windows + Python 3.10+（勾选 Add to PATH）+ 已安装 DeepSeek Harness（`dsh web` 可用）。

```bash
# 1. 双击 install.cmd（或执行 install.ps1）
#    自动完成：检测 Python -> 创建虚拟环境 -> 安装依赖 -> 探测 DSH 安装目录
#    （未自动探测到时，按提示在 gateway\.env 手动配置 HARNESS_ROOT / DSH_HOME）

# 2. 双击 start-everything.cmd 一键启动
#    自动完成：识别并唤醒 Tailscale（服务/连接/HTTPS 转发）-> 拉起 DSH -> 启动网关
#    -> 终端打印：局域网地址 / HTTPS 外网地址 / WireGuard 地址 / 登录密码

# 3. 访问
#    浏览器打开 http://<本机IP>:8080/dashboard ，输入终端显示的登录密码
#    （每台机器安装时自动生成独一无二的随机密码，保存在 gateway\.env）

# 4. 关闭
#    双击 stop-everything.cmd：停止 网关 + DSH + Tailscale HTTPS 转发
```

> 手动安装（不使用 install.cmd）：
>
> ```bash
> pip install -r gateway/requirements.txt
> python gateway/run.py          # 网关（默认 0.0.0.0:8080）
> # 或 gateway/start_all.py      # 先拉起 DSH（若未运行）再启动网关
> ```
>
> 配置项（环境变量或 `gateway/.env`）：

| 变量 | 说明 | 默认 |
|---|---|---|
| `GATEWAY_PORT` | 网关端口 | 8080 |
| `GATEWAY_PASSWORD` | 登录密码（自动生成） | - |
| `GATEWAY_SECRET_KEY` | 会话签名密钥（自动生成） | - |
| `DSH_WEB_PORT` | DSH Web 端口 | 3080 |
| `HARNESS_ROOT` / `DSH_HOME` | DSH 安装目录（首次启动自动探测并写入 .env） | 自动 |

## 目录结构

```
install.cmd / install.ps1            # 通用安装（Python/venv/依赖/DSH 探测）
start-everything.cmd/.ps1            # 一键启动（唤醒 Tailscale + DSH + 网关）
stop-everything.cmd/.ps1             # 一键关闭（网关 + DSH + HTTPS 转发）
gateway/
├─ app/
│  ├─ main.py        # 路由 / 鉴权中间件 / 控制接口
│  ├─ config.py      # 配置与密钥（DSH 目录自动探测）
│  ├─ auth.py        # HMAC 会话、登录限速
│  ├─ monitor.py     # 状态探测 / 日志
│  ├─ dsh_manager.py # DSH 进程托管
│  ├─ sessions.py    # 会话索引 / zstd 尾段读取 / 发消息
│  └─ proxy.py       # 反向代理 / 注入 / 压缩 / 缓存 / 数据过滤 / 问题监听
├─ static/           # 移动端前端（原生 HTML/JS/CSS）
└─ requirements.txt
```

## 文档

- `PLAN.md` — 方案设计

## 免责声明

本项目用于管理你自己的 DeepSeek Harness 实例。远程控制 = 远程执行代码，请自行评估风险；不要把网关暴露到公网，不要共享登录凭据。
