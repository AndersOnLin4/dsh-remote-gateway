# 通用安装脚本：DSH 远程网关
# 适用于任意 Windows 主机（已安装 Python 3.10+ 与 DeepSeek Harness）
# 用法：双击 install.cmd，或在 PowerShell 中执行本脚本

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '  DSH 远程网关 - 通用安装' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

# ---------- 1/4 检测 Python ----------
$py = $null
# 优先 py 启动器（真正的安装版）
try { $py = (& py -3 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1) } catch {}
if (-not $py -or -not (Test-Path $py)) {
    $cand = (Get-Command python -ErrorAction SilentlyContinue).Source
    # 排除 Windows 商店占位程序（WindowsApps）
    if ($cand -and (Test-Path $cand) -and $cand -notmatch 'WindowsApps') { $py = $cand }
}
if (-not $py -or -not (Test-Path $py)) {
    Write-Host '[1/4] 未找到 Python。请先安装 Python 3.10+（勾选 Add to PATH）后重试。' -ForegroundColor Red
    exit 1
}
Write-Host "[1/4] Python: $py" -ForegroundColor Green

# ---------- 2/4 虚拟环境 ----------
$venv = Join-Path $Root 'gateway\.venv'
$venvPy = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    Write-Host '[2/4] 创建虚拟环境...' -ForegroundColor Yellow
    & $py -m venv $venv
    if (-not (Test-Path $venvPy)) { Write-Host '      创建失败' -ForegroundColor Red; exit 1 }
}
Write-Host '[2/4] 虚拟环境就绪' -ForegroundColor Green

# ---------- 3/4 安装依赖 ----------
Write-Host '[3/4] 安装依赖（首次较慢）...' -ForegroundColor Yellow
& $venvPy -m pip install --upgrade pip -q 2>$null
& $venvPy -m pip install -r (Join-Path $Root 'gateway\requirements.txt') -q --timeout 30
if ($LASTEXITCODE -ne 0) {
    # 网络受限时尝试常见本地代理（如 Clash/V2Ray 默认端口）
    $proxyPort = 7893
    $proxyOk = Test-NetConnection -ComputerName 127.0.0.1 -Port $proxyPort -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($proxyOk) {
        Write-Host '      直连超时，改用本地代理重试...' -ForegroundColor Yellow
        & $venvPy -m pip install -r (Join-Path $Root 'gateway\requirements.txt') -q --timeout 60 --proxy "http://127.0.0.1:$proxyPort"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host '      依赖安装失败：请检查网络（如使用代理，可先开启再重试）' -ForegroundColor Red
        exit 1
    }
}
Write-Host '[3/4] 依赖安装完成' -ForegroundColor Green

# ---------- 4/4 探测 DSH ----------
Write-Host '[4/4] 探测 DeepSeek Harness 安装目录...' -ForegroundColor Yellow
$detect = $null
try {
    $detect = & $venvPy -c "import sys; sys.path.insert(0, r'$Root\gateway'); from app import config; print(str(config.DSH_HOME))" 2>$null | Select-Object -First 1
} catch {}
if ($detect -and (Test-Path $detect)) {
    Write-Host "      DSH 目录: $detect" -ForegroundColor Green
} else {
    Write-Host '      未自动探测到 DSH。' -ForegroundColor Yellow
    Write-Host '      手动方式：编辑 gateway\.env，加入：' -ForegroundColor Yellow
    Write-Host '        HARNESS_ROOT=<Harness安装目录，如 C:\harness>' -ForegroundColor White
    Write-Host '        DSH_HOME=<其下的 dsh-home 目录>' -ForegroundColor White
}

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '  安装完成！' -ForegroundColor Green
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '  1. 启动：双击 start-everything.cmd（自动拉起 DSH + 网关 + Tailscale）'
Write-Host '  2. 局域网访问：http://<本机IP>:8080/dashboard'
Write-Host '  3. 登录密码：gateway\.env 的 GATEWAY_PASSWORD=（首次启动自动生成）'
Write-Host '  4. 手机外网访问：电脑与手机装 Tailscale 并登录同账号，'
Write-Host '     启动后手机会话中打开 https://<电脑名>.<你的tailnet>.ts.net'
Write-Host ''
