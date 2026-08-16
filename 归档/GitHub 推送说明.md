# GitHub 推送说明

> 仓库：`github.com/AndersOnLin4/dsh-remote-gateway`
> 本文档说明如何安全地推送/更新代码，以及推送前的脱敏检查清单。

## 推送前必做：脱敏检查

仓库是**公开**的，推送前确认以下内容绝不在其中：

| 内容 | 位置 | 状态 |
|---|---|---|
| 登录密码 / 签名密钥 | `gateway\.env` | `.gitignore` 已排除 |
| 虚拟环境 | `gateway\.venv\` | `.gitignore` 已排除 |
| 运行 PID | `gateway\gateway.pid` | `.gitignore` 已排除 |
| 本机真实地址 | `DEPLOY.md`（局域网 IP / tailnet 名称） | `.gitignore` 已排除 |
| 日志 / 审计 | `G:\harness\logs\` | 在仓库外 |
| API 密钥 | `dsh-home\.credentials.yaml` | 在仓库外 |

自查命令（提交前执行）：

```bash
git status --short          # 确认暂存文件清单
git ls-files | grep -iE "env|secret|credential|token|\.pid$|\.log$"   # 应无输出
```

## 更新推送流程

```bash
git add -A
git commit -m "描述本次改动"
git push origin main
```

## 凭据说明（通用做法）

推送需要 GitHub 凭据，任选其一：

1. **个人访问令牌（PAT）**：GitHub → Settings → Developer settings → Personal access tokens → 生成（勾选 `repo` 权限）→ 推送时作为密码输入（用户名填账号名）。
2. **gh CLI**：`gh auth login` 后 `gh repo create` / `git push` 自动带凭据。
3. **SSH 密钥**：生成密钥并添加到 GitHub → 改用 `git@github.com:...` 地址。

> 注意：令牌等同于账号权限，**不要**写进任何文件、不要提交到仓库；本机网络受限时，给 git 配置代理（如 `git -c http.proxy=http://127.0.0.1:7893 push ...`）。

## 仓库内容

- `gateway/` — 网关代码（无任何密钥）
- `归档/` — 工程档案（已用占位符脱敏）
- `PLAN.md` / `README.md` — 方案与说明
