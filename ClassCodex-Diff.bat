@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ClassCodex-Diff.ps1" %*
if errorlevel 1 (
  echo.
  echo ClassCodex diff failed.
  pause
  exit /b %errorlevel%
)
pause
