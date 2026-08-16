@echo off
rem One-click launcher: Tailscale + DSH + gateway
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-everything.ps1"
echo.
pause