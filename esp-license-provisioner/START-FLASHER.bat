@echo off
cd /d "%~dp0"
rem Prefer packaged suite, then legacy names, then Python
if exist "%~dp0dist\CEBJ-License-Tools\CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe" (
  start "" "%~dp0dist\CEBJ-License-Tools\CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe"
  exit /b 0
)
if exist "%~dp0dist\KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe" (
  start "" "%~dp0dist\KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe"
  exit /b 0
)
if exist "%~dp0dist\KonekSik-ESP-Flasher\CEBJ-ESP-Flasher.exe" (
  start "" "%~dp0dist\KonekSik-ESP-Flasher\CEBJ-ESP-Flasher.exe"
  exit /b 0
)
if exist "%~dp0KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe" (
  start "" "%~dp0KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe"
  exit /b 0
)
call "%~dp0run.bat"
