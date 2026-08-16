# 一键启动：Tailscale + DSH + 远程网关
# 用法：双击 start-everything.cmd，或在 PowerShell 中执行本脚本

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TS = $env:TAILSCALE_EXE
if (-not $TS) { $TS = 'C:\Program Files\Tailscale\tailscale.exe' }
if (-not (Test-Path $TS)) { $TS = (Get-Command tailscale -ErrorAction SilentlyContinue).Source }
if ($TS -and -not (Test-Path $TS)) { $TS = $null }

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '  DSH 远程网关 一键启动' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

# ---------- 1/3 Tailscale ----------
if (Test-Path $TS) {
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Host '[1/3] 启动 Tailscale 服务...' -ForegroundColor Yellow
        Start-Service -Name 'Tailscale'
        Start-Sleep -Seconds 4
    }
    Write-Host '[1/3] 连接 Tailscale...' -ForegroundColor Yellow
    & $TS up --timeout 20s 2>$null | Out-Null
    Start-Sleep -Seconds 2
    $serve = (& $TS serve status 2>&1 | Out-String)
    if ($serve -match 'proxy http://127\.0\.0\.1:8080') {
        Write-Host '      HTTPS 转发已就绪' -ForegroundColor Green
    } else {
        Write-Host '      配置 HTTPS 转发（tailscale serve）...' -ForegroundColor Yellow
        & $TS serve --bg 8080 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }
} else {
    Write-Host '[1/3] 未找到 Tailscale，跳过（局域网访问不受影响）' -ForegroundColor Yellow
}

# ---------- 2/3 DSH ----------
$dsh = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
$py = Join-Path $Root 'gateway\.venv\Scripts\python.exe'
if ($dsh) {
    Write-Host '[2/3] DSH 已在运行' -ForegroundColor Green
} else {
    Write-Host '[2/3] DSH 未运行，正在拉起...' -ForegroundColor Yellow
    if (Test-Path $py) {
        & $py -c "import sys; sys.path.insert(0, r'$Root\gateway'); from app import dsh_manager; print(dsh_manager.start())"
    } else {
        Write-Host '      !! 未找到虚拟环境，请先安装依赖' -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}

# ---------- 3/3 网关 ----------
$gw = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
$pythonw = Join-Path $Root 'gateway\.venv\Scripts\pythonw.exe'
if ($gw) {
    Write-Host '[3/3] 网关已在运行' -ForegroundColor Green
} else {
    Write-Host '[3/3] 启动网关（自动拉起 DSH）...' -ForegroundColor Yellow
    if (Test-Path $pythonw) {
        Start-Process -FilePath $pythonw -ArgumentList (Join-Path $Root 'gateway\start_all.py') -WindowStyle Hidden
    } else {
        Write-Host '      !! 未找到虚拟环境，请先安装依赖' -ForegroundColor Red
    }
}

# ---------- 等待就绪 ----------
Write-Host '等待服务就绪...' -ForegroundColor Yellow
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $dsh2 = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
    $gw2 = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if ($dsh2 -and $gw2) { break }
}

# ---------- 结果 ----------
$dshOk = [bool](Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue)
$gwOk = [bool](Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue)

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
if ($dshOk) { Write-Host '  DSH    : 运行中 ✓' -ForegroundColor Green } else { Write-Host '  DSH    : 未运行 ✗（查看 gateway 日志）' -ForegroundColor Red }
if ($gwOk) { Write-Host '  网关   : 运行中 ✓' -ForegroundColor Green } else { Write-Host '  网关   : 未运行 ✗' -ForegroundColor Red }

$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254*' -and $_.InterfaceAlias -notlike 'VMware*' -and $_.InterfaceAlias -notlike 'vEthernet*' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if ($lanIp) { Write-Host "  局域网 : http://$lanIp`:8080/dashboard" -ForegroundColor White }
if (Test-Path $TS) {
    $st = (& $TS status --json 2>$null | ConvertFrom-Json)
    if ($st -and $st.Self.DNSName) {
        Write-Host "  外网   : https://$($st.Self.DNSName)" -ForegroundColor White
    }
}
Write-Host '  登录密码: 见 gateway\.env 的 GATEWAY_PASSWORD=' -ForegroundColor White
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '提示：手机可直接打开上方"外网"地址；日志在 DSH 安装目录的 logs\ 下（见 gateway\.env 的 LOG_DIR）'
Write-Host ''
