@echo off
rem Start DSH + gateway
set "VENV_PY=%~dp0.venv\Scripts\pythonw.exe"
if not exist "%VENV_PY%" set "VENV_PY=%~dp0.venv\Scripts\python.exe"
start "" "%VENV_PY%" "%~dp0start_all.py"
exit /b 0