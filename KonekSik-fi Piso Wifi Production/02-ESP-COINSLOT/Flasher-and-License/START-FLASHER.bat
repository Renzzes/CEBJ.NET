@echo off
cd /d "%~dp0"
if exist "%~dp0KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe" (
  start "" "%~dp0KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe"
  exit /b 0
)
if exist "%~dp0KonekSik-ESP-Flasher.exe" (
  start "" "%~dp0KonekSik-ESP-Flasher.exe"
  exit /b 0
)
call "%~dp0run.bat"
