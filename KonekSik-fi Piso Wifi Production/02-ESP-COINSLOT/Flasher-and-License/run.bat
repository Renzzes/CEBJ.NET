@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title KonekSik-fi ESP Flasher + License

echo.
echo ============================================================
echo   KonekSik-fi ESP License Provisioner
echo ============================================================
echo.

rem Prefer real Python (not the Windows Store stub)
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo ERROR: Python 3 not found.
  echo Install from https://www.python.org/downloads/
  echo During setup, check "Add python.exe to PATH".
  echo.
  pause
  exit /b 1
)

rem Valid venv must have Scripts\python.exe (folder alone is not enough)
if not exist "%~dp0.venv\Scripts\python.exe" (
  echo Creating virtual environment...
  if exist "%~dp0.venv" rd /s /q "%~dp0.venv" 2>nul
  %PY% -m venv "%~dp0.venv"
  if not exist "%~dp0.venv\Scripts\python.exe" (
    echo ERROR: failed to create .venv
    echo Try: %PY% -m venv .venv
    pause
    exit /b 1
  )
)

set "VPY=%~dp0.venv\Scripts\python.exe"

echo Installing / updating dependencies...
"%VPY%" -m pip install --upgrade pip >nul 2>&1
"%VPY%" -m pip install -r "%~dp0requirements.txt"
if errorlevel 1 (
  echo ERROR: pip install failed.
  pause
  exit /b 1
)

echo.
echo Starting app...
echo.
"%VPY%" -m app.main
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo App exited with code %ERR%.
  pause
)
exit /b %ERR%
