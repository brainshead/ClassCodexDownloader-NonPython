@echo off
setlocal
cd /d "%~dp0"

set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" (
  echo ERROR: Windows PowerShell could not be found at:
  echo %POWERSHELL%
  echo.
  echo ClassCodex diff failed.
  pause
  exit /b 1
)

rem Remove the downloaded-file mark before launching the trusted local script.
rem This only unblocks this one script; it does not weaken system-wide policy.
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0ClassCodex-Diff.ps1' -ErrorAction SilentlyContinue; & '%~dp0ClassCodex-Diff.ps1' %*"
if errorlevel 1 (
  echo.
  echo ClassCodex diff failed.
  pause
  exit /b %errorlevel%
)
pause
