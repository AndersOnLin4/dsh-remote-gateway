@echo off
rem Stop DSH gateway + DSH (by port)
powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { Stop-Process -Id $c.OwningProcess -Force; Write-Host 'gateway stopped' } else { Write-Host 'gateway not running' }; $d = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($d) { Stop-Process -Id $d.OwningProcess -Force; Write-Host 'DSH stopped' } else { Write-Host 'DSH not running' }"
pause