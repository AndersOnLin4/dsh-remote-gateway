@echo off
rem One-click shutdown: gateway + DSH + Tailscale serve
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-everything.ps1"
echo.
pause