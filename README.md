# DSH 手机远程网关

在 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 前面加一层轻量网关：登录鉴权、手机端监控/回复、反向代理与数据过滤。手机浏览器即可查看会话状态、阅读过滤后的对话、直接回复，并处理 agent 的选择题——全程无需打开完整控制台。

> 安全提示：DSH 本身无鉴权且通常以高权限运行。本项目的一切远程访问都依赖网关的登录墙，请务必：使用强密码、选择私有隧道（如 Tailscale，tailnet only）、不要暴露到公网。

## 功能

- **移动端仪表盘**：三 Tab（监控 / 会话 / 日志），会话列表直接显示标题、工作区、轮数、token 用量、活跃状态
- **轻量会话浏览**：只解压会话文件尾部，返回"用户提问 + 每轮最终中文回复 + 选择题"，KB 级秒开
- **直接回复**：复刻 DSH 的 `session.prompt` RPC，仪表盘内即可回消息，自动轮询等待回复
- **选择题交互**：常驻监听 DSH 事件流，捕获 agent 提问，选项卡片点选提交
- **完整控制台**：反向代理 DSH 原版 UI（HTTP + WebSocket，通过其浏览器信任栅栏），并注入移动端适配（输入框贴底、侧栏整屏、防 iOS 缩放）
- **数据层过滤**：代理改写 `session.history` 响应，剔除流式碎片/思考/工具调用/上下文注入，历史加载从 MB 级降到 KB 级
- **安全**：HMAC 会话 Cookie、登录限速、操作审计日志

## 架构

```
手机浏览器 → Tailscale(私有隧道/HTTPS) → 网关(FastAPI :8080) → DSH(仅 127.0.0.1:3080)
```

- 网关承担：登录鉴权、静态仪表盘、`/gw/*` API、反向代理（Host/Origin 重写过 DSH 信任栅栏）、gzip 压缩、静态资源 immutable 缓存、HTML 注入、数据过滤、问题监听
- 外网推荐 Tailscale + Serve（tailnet only，公网零暴露）；`归档/技术链路.md` 有完整说明

## 快速开始

```bash
# 1. 安装依赖（建议虚拟环境）
pip install -r gateway/requirements.txt

# 2. 修改配置
#    编辑 gateway/app/config.py 中的路径，或设置环境变量；
#    首次启动会自动生成 gateway/.env（登录密码 + 签名密钥），请妥善保管

# 3. 启动
python gateway/run.py          # 网关（默认 0.0.0.0:8080）
# 或 gateway/start_all.py      # 先拉起 DSH（若未运行）再启动网关

# 4. 访问
#    浏览器打开 http://<电脑IP>:8080/dashboard ，输入 gateway/.env 中的密码
```

配置项（环境变量或 `gateway/.env`）：

| 变量 | 说明 | 默认 |
|---|---|---|
| `GATEWAY_PORT` | 网关端口 | 8080 |
| `GATEWAY_PASSWORD` | 登录密码（自动生成） | - |
| `GATEWAY_SECRET_KEY` | 会话签名密钥（自动生成） | - |
| `DSH_WEB_PORT` | DSH Web 端口 | 3080 |
| `HARNESS_ROOT` / `DSH_HOME` | DSH 安装目录 | `G:\harness` 等 |

## 目录结构

```
gateway/
├─ app/
│  ├─ main.py        # 路由 / 鉴权中间件 / 控制接口
│  ├─ config.py      # 配置与密钥
│  ├─ auth.py        # HMAC 会话、登录限速
│  ├─ monitor.py     # 状态探测 / 日志
│  ├─ dsh_manager.py # DSH 进程托管
│  ├─ sessions.py    # 会话索引 / zstd 尾段读取 / 发消息
│  └─ proxy.py       # 反向代理 / 注入 / 压缩 / 缓存 / 数据过滤 / 问题监听
├─ static/           # 移动端前端（原生 HTML/JS/CSS）
└─ requirements.txt
归档/                 # 工程档案：进展记录 / 项目组成 / 技术链路 / 技术分享
```

## 文档

- `归档/工程进展记录.md` — 开发时间线
- `归档/项目组成.md` — 结构、接口、部署
- `归档/技术链路.md` — 端到端链路与协议细节
- `归档/技术分享.md` — 踩坑记录与经验

## 免责声明

本项目用于管理你自己的 DeepSeek Harness 实例。远程控制 = 远程执行代码，请自行评估风险；不要把网关暴露到公网，不要共享登录凭据。
