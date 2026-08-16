# 一键关闭：停止 网关 + DSH + Tailscale HTTPS 转发
# 用法：双击 stop-everything.cmd，或在 PowerShell 中执行本脚本

$ErrorActionPreference = 'SilentlyContinue'
$TS = $env:TAILSCALE_EXE
if (-not $TS) { $TS = 'C:\Program Files\Tailscale\tailscale.exe' }
if (-not (Test-Path $TS)) { $TS = (Get-Command tailscale -ErrorAction SilentlyContinue).Source }
if ($TS -and -not (Test-Path $TS)) { $TS = $null }

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '  DSH 远程网关 一键关闭' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

# ---------- 1/3 网关 ----------
$gw = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($gw) {
    Write-Host '[1/3] 停止网关 (8080)...' -ForegroundColor Yellow
    Stop-Process -Id $gw.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host '      已停止' -ForegroundColor Green
} else {
    Write-Host '[1/3] 网关未在运行' -ForegroundColor Green
}

# ---------- 2/3 DSH ----------
$dsh = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
if ($dsh) {
    Write-Host '[2/3] 停止 DSH (3080)...' -ForegroundColor Yellow
    Stop-Process -Id $dsh.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host '      已停止' -ForegroundColor Green
} else {
    Write-Host '[2/3] DSH 未在运行' -ForegroundColor Green
}

# ---------- 3/3 Tailscale HTTPS 转发 ----------
if (Test-Path $TS) {
    Write-Host '[3/3] 关闭 Tailscale HTTPS 转发...' -ForegroundColor Yellow
    & $TS serve reset 2>&1 | Out-Null
    Write-Host '      （Tailscale 本身保持连接，下次启动会自动重新配置）' -ForegroundColor DarkGray
} else {
    Write-Host '[3/3] 未找到 Tailscale，跳过' -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
$gw2 = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
$dsh2 = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
if (-not $gw2 -and -not $dsh2) {
    Write-Host '  已全部关闭 ✓（重启请双击 start-everything.cmd）' -ForegroundColor Green
} else {
    Write-Host '  部分进程仍在运行，请稍后重试或手动结束' -ForegroundColor Yellow
}
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
