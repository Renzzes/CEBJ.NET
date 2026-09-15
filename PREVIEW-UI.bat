@echo off
setlocal EnableExtensions
title KonekSik-fi LIVE Dev Preview

cd /d "%~dp0"

set "PORT=8777"

echo.
echo ============================================================
echo   KonekSik-fi LIVE Dev Preview ^(no-cache^)
echo ============================================================
echo.
echo   IMPORTANT: Use THIS hub URL only ^(port %PORT%^).
echo   An old Python server on 8765 may still show the OLD page
echo   without Live Preview — ignore 8765.
echo.
echo   Admin dashboard  = live from rootfs\www\admin.html
echo   Captive portal   = live from KonekSik-fi Captive Portal\
echo   Edit files, then hard-refresh ^(Ctrl+F5^).
echo.
echo   Hub:    http://127.0.0.1:%PORT%/
echo   Admin:  http://127.0.0.1:%PORT%/admin-preview.html#captive-portal
echo   Guest:  http://127.0.0.1:%PORT%/guest/login.html
echo.
echo   Captive Portal page = two columns:
echo     LEFT  Portal Configuration
echo     RIGHT Live Preview ^(guest portal mock^)
echo.
echo   Keep this window open. Press Ctrl+C to stop.
echo ============================================================
echo.

where node >nul 2>&1
if errorlevel 1 (
  echo ERROR: Node.js is required for live no-cache preview.
  echo Install Node.js, then re-run PREVIEW-UI.bat
  pause
  exit /b 1
)

if not exist "%~dp0tools\preview-ui-server.mjs" (
  echo ERROR: tools\preview-ui-server.mjs missing.
  pause
  exit /b 1
)

REM Free this preview port if anything is still listening
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%PORT%" ^| findstr "LISTENING"') do (
  echo Stopping previous process on port %PORT% ^(PID %%P^) ...
  taskkill /F /PID %%P >nul 2>&1
)

set "KONEKSIK_PREVIEW_PORT=%PORT%"
node "%~dp0tools\sync-admin-preview.mjs"
node "%~dp0tools\preview-ui-server.mjs"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Preview failed ^(exit %ERR%^).
  pause
)
exit /b %ERR%
