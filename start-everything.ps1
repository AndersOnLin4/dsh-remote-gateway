# 一键启动：Tailscale + DSH + 远程网关
# 用法：双击 start-everything.cmd，或在 PowerShell 中执行本脚本

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TS = $env:TAILSCALE_EXE
if (-not $TS) { $TS = 'C:\Program Files\Tailscale\tailscale.exe' }
if (-not (Test-Path $TS)) { $TS = (Get-Command tailscale -ErrorAction SilentlyContinue).Source }
if ($TS -and -not (Test-Path $TS)) { $TS = $null }
$script:TSInfo = $null

# 读取 Tailscale 状态（UTF-8 安全，避免中文主机名导致 JSON 解析失败）
function Get-TailscaleInfo($exe) {
    $tmp = Join-Path $env:TEMP ("ts-status-" + [guid]::NewGuid().ToString('N') + '.json')
    & $exe status --json 2>$null | Out-File -FilePath $tmp -Encoding utf8
    $st = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $info = [pscustomobject]@{ Online = $false; DNSName = ''; IP = ''; Relay = '' }
    if ($st -and $st.Self) {
        $info.Online = [bool]$st.Self.Online
        $info.DNSName = ([string]$st.Self.DNSName).TrimEnd('.')
        $ips = @($st.Self.TailscaleIPs)
        if ($ips.Count -gt 0) { $info.IP = [string]$ips[0] }
        if ($st.Self.Relay) { $info.Relay = [string]$st.Self.Relay }
    }
    return $info
}

Write-Host ''
Write-Host '  ==================================================' -ForegroundColor Cyan
Write-Host '    DSH 远程网关  ★  AndersOnLin4' -ForegroundColor Cyan
Write-Host '    联系邮箱 : andersonlin1107@gmail.com' -ForegroundColor DarkCyan
Write-Host '    项目主页 : https://github.com/AndersOnLin4/' -ForegroundColor DarkCyan
Write-Host '  ==================================================' -ForegroundColor Cyan
Write-Host ''

# ---------- 1/3 Tailscale：自动识别 + 唤醒 ----------
if (Test-Path $TS) {
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host '[1/3] 未检测到 Tailscale 服务（可到 tailscale.com/download 安装，免费）' -ForegroundColor Yellow
    } else {
        if ($svc.Status -ne 'Running') {
            Write-Host '[1/3] 唤醒 Tailscale 服务...' -ForegroundColor Yellow
            Start-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 500
                if ((Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue).Status -eq 'Running') { break }
            }
        }
        Write-Host '[1/3] 连接 Tailscale...' -ForegroundColor Yellow
        $upOut = & $TS up --timeout 25s 2>&1
        $upOut | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            $script:TSInfo = Get-TailscaleInfo $TS
            if ($script:TSInfo.Online) { break }
        }
        if ($script:TSInfo.Online) {
            Write-Host '      已连接 ✓' -ForegroundColor Green
        } else {
            Write-Host '      !! 仍未连接' -ForegroundColor Red
            Write-Host '      Tailscale 需要你先自行开启并登录一次（本项目只负责唤醒服务与连接，不代登录）：' -ForegroundColor Yellow
            Write-Host '        方式1: 点击系统托盘 Tailscale 图标 → 登录（浏览器完成认证）' -ForegroundColor White
            Write-Host '        方式2: 命令行执行 tailscale up 并按提示打开链接登录' -ForegroundColor White
            Write-Host '        登录完成后，再双击本脚本即可显示外网地址' -ForegroundColor White
        }
        $serve = (& $TS serve status 2>&1 | Out-String)
        if ($serve -match 'proxy http://127\.0\.0\.1:8080') {
            Write-Host '      HTTPS 转发已就绪 ✓' -ForegroundColor Green
        } else {
            Write-Host '      配置 HTTPS 转发（tailscale serve）...' -ForegroundColor Yellow
            & $TS serve --bg 8080 2>&1 | Out-Null
            Start-Sleep -Seconds 1
        }
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
        Write-Host '      !! 未找到虚拟环境，请先运行 install.cmd' -ForegroundColor Red
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
        $gwScript = '"' + (Join-Path $Root 'gateway\start_all.py') + '"'
        Start-Process -FilePath $pythonw -ArgumentList $gwScript -WorkingDirectory (Join-Path $Root 'gateway') -WindowStyle Hidden
    } else {
        Write-Host '      !! 未找到虚拟环境，请先运行 install.cmd' -ForegroundColor Red
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
$envFile = Join-Path $Root 'gateway\.env'

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
if ($dshOk) { Write-Host '  DSH    : 运行中 ✓' -ForegroundColor Green } else { Write-Host '  DSH    : 未运行 ✗（查看日志）' -ForegroundColor Red }
if ($gwOk) { Write-Host '  网关   : 运行中 ✓' -ForegroundColor Green } else { Write-Host '  网关   : 未运行 ✗' -ForegroundColor Red }

$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254*' -and $_.InterfaceAlias -notlike 'VMware*' -and $_.InterfaceAlias -notlike 'vEthernet*' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if ($lanIp) { Write-Host "  局域网 : http://$lanIp`:8080/dashboard" -ForegroundColor White }

if ($script:TSInfo -and $script:TSInfo.Online) {
    if ($script:TSInfo.DNSName) { Write-Host "  HTTPS  : https://$($script:TSInfo.DNSName)" -ForegroundColor White }
    if ($script:TSInfo.IP) { Write-Host "  WireGuard: $($script:TSInfo.IP):8080" -ForegroundColor White }
    Write-Host '  （手机装 Tailscale 登录同账号后即可访问上面两个地址）' -ForegroundColor DarkGray
} elseif (Test-Path $TS) {
    Write-Host '  Tailscale: 未连接。请先在系统托盘手动开启并登录 Tailscale（本项目不代登录），再重跑本脚本' -ForegroundColor Yellow
}

if (Test-Path $envFile) {
    $pwLine = Get-Content -LiteralPath $envFile | Where-Object { $_ -like 'GATEWAY_PASSWORD=*' } | Select-Object -First 1
    if ($pwLine) {
        $pw = $pwLine.Substring('GATEWAY_PASSWORD='.Length)
        Write-Host "  登录密码: $pw" -ForegroundColor White
        Write-Host '  （每台机器安装时自动生成，各不相同；存在 gateway\.env）' -ForegroundColor DarkGray
    }
}
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '提示：手机可直接打开上方"HTTPS"地址；日志在 DSH 安装目录的 logs\ 下'
Write-Host 'Tailscale 外网访问需你先在系统托盘开启并登录一次（脚本只做自动唤醒与连接）'
Write-Host ''
Write-Host '  --------------------------------------------------' -ForegroundColor DarkCyan
Write-Host '  DSH 远程网关 · AndersOnLin4 · andersonlin1107@gmail.com' -ForegroundColor DarkCyan
Write-Host '  项目主页: https://github.com/AndersOnLin4/' -ForegroundColor DarkCyan
Write-Host '  --------------------------------------------------' -ForegroundColor DarkCyan
Write-Host ''
