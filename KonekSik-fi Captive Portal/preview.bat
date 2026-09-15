@echo off
setlocal EnableExtensions

REM KonekSik-fi Captive Portal — UI demo with working buttons
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  echo ERROR: Node.js is not on PATH. Install Node.js, then retry.
  pause
  exit /b 1
)

if not exist "%~dp0demo-server.mjs" (
  echo ERROR: demo-server.mjs missing in this folder.
  pause
  exit /b 1
)
if not exist "%~dp0login.html" (
  echo ERROR: login.html missing.
  pause
  exit /b 1
)

echo.
echo Starting KonekSik-fi Captive Portal preview...
echo Close this window or press Ctrl+C to stop.
echo.

node "%~dp0demo-server.mjs"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Preview failed ^(exit %ERR%^).
  pause
)
exit /b %ERR%
