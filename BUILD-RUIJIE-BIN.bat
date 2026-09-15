@echo off
chcp 437 >nul
title KonekSik-fi - Build Ruijie .bin (one-click)
cd /d "%~dp0"

echo.
echo ============================================================
echo   KonekSik-fi - Build Ruijie EW1200G Pro firmware (.bin)
echo ============================================================
echo.
echo   This script will:
echo     1. Install WSL + Ubuntu if missing (may need reboot)
echo     2. Build the OpenWrt sysupgrade .bin
echo     3. Put it in:
echo        KonekSik-fi Piso Wifi Production\01-RUIJIE-OPENWRT\
echo.
echo   First build can take 15-45+ minutes (downloads toolchain).
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup-and-build-ruijie.ps1"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo FAILED (exit %ERR%). See:
  echo   KonekSik-fi Piso Wifi Production\logs\ruijie-build.log
  echo.
  pause
)
exit /b %ERR%
