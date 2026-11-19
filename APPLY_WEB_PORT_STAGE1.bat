@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY_WEB_PORT_STAGE1.ps1"
if errorlevel 1 (
  echo.
  echo The Stage 1 script stopped. No source files were changed unless it reported success.
  pause
)
