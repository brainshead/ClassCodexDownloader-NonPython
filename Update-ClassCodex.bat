@echo off
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%~dp0Update-ClassCodex.ps1" (
    echo.
    echo ERROR: Update-ClassCodex.ps1 was not found.
    echo Please extract the ZIP to a normal folder before running it.
    echo.
    pause
    exit /b 1
)
"%PS%" -NoProfile -Command "Unblock-File -LiteralPath '%~dp0Update-ClassCodex.ps1' -ErrorAction SilentlyContinue"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-ClassCodex.ps1"
if errorlevel 1 echo Update failed with exit code %errorlevel%
pause
