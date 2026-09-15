@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Build ALL CEBJ License Tools (.exe)

echo.
echo ============================================================
echo   Build 3 apps as .exe into one folder
echo   dist\CEBJ-License-Tools\
echo ============================================================
echo.

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo ERROR: Python 3 not found.
  pause
  exit /b 1
)

if not exist "%~dp0.venv\Scripts\python.exe" (
  echo Creating .venv...
  %PY% -m venv "%~dp0.venv"
)

set "VPY=%~dp0.venv\Scripts\python.exe"
echo Installing dependencies + PyInstaller...
"%VPY%" -m pip install -q -r requirements.txt pyinstaller
if errorlevel 1 (
  echo ERROR: pip install failed
  pause
  exit /b 1
)

echo.
echo --- Smoke-test Python apps before packaging ---
"%VPY%" "%~dp0tools_verify_apps.py"
if errorlevel 1 (
  echo VERIFY FAILED — fix before building .exe
  pause
  exit /b 1
)

set "OUT=%~dp0dist\CEBJ-License-Tools"
if exist "%OUT%" rd /s /q "%OUT%"
mkdir "%OUT%" 2>nul

echo.
echo --- Building CEBJ-ESP-Flasher ---
"%VPY%" -m PyInstaller --noconfirm --clean --distpath "%OUT%" "%~dp0CEBJ-ESP-Flasher.spec"
if errorlevel 1 goto :fail

echo.
echo --- Building CEBJ-License-Generator ---
"%VPY%" -m PyInstaller --noconfirm --clean --distpath "%OUT%" "%~dp0CEBJ-License-Generator.spec"
if errorlevel 1 goto :fail

echo.
echo --- Building CEBJ-Buyer-Replacement-Flasher ---
"%VPY%" -m PyInstaller --noconfirm --clean --distpath "%OUT%" "%~dp0CEBJ-Buyer-Replacement-Flasher.spec"
if errorlevel 1 goto :fail

rem Shared folders next to each app + root shortcuts
for %%A in (CEBJ-ESP-Flasher CEBJ-License-Generator CEBJ-Buyer-Replacement-Flasher) do (
  mkdir "%OUT%\%%A\firmware" 2>nul
  mkdir "%OUT%\%%A\keys" 2>nul
  mkdir "%OUT%\%%A\logs" 2>nul
  mkdir "%OUT%\%%A\bundles" 2>nul
  if exist "%~dp0keys" xcopy /E /I /Y "%~dp0keys\*" "%OUT%\%%A\keys\" >nul
  if exist "%~dp0firmware" xcopy /E /I /Y "%~dp0firmware\*" "%OUT%\%%A\firmware\" >nul
  if exist "%~dp0config.json" copy /Y "%~dp0config.json" "%OUT%\%%A\config.json" >nul
  if exist "%~dp0board_profiles" xcopy /E /I /Y "%~dp0board_profiles\*" "%OUT%\%%A\board_profiles\" >nul
)

copy /Y "%~dp0HOW-TO-APPS.txt" "%OUT%\HOW-TO-APPS.txt" >nul 2>nul
(
  echo @echo off
  echo cd /d "%%~dp0"
  echo echo.
  echo echo  1 = ESP Flasher + License   ^(seller^)
  echo echo  2 = License Generator       ^(seller^)
  echo echo  3 = Buyer Replacement Flasher
  echo echo.
  echo set /p C=Choose 1-3:
  echo if "%%C%%"=="1" start "" "CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe"
  echo if "%%C%%"=="2" start "" "CEBJ-License-Generator\CEBJ-License-Generator.exe"
  echo if "%%C%%"=="3" start "" "CEBJ-Buyer-Replacement-Flasher\CEBJ-Buyer-Replacement-Flasher.exe"
) > "%OUT%\START-MENU.bat"

rem Keep legacy name folder for START-FLASHER.bat compatibility
if exist "%~dp0dist\KonekSik-ESP-Flasher" rd /s /q "%~dp0dist\KonekSik-ESP-Flasher"
xcopy /E /I /Y "%OUT%\CEBJ-ESP-Flasher\*" "%~dp0dist\KonekSik-ESP-Flasher\" >nul
copy /Y "%OUT%\CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe" "%~dp0dist\KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe" >nul

set "PROD=%~dp0..\KonekSik-fi Piso Wifi Production\02-ESP-COINSLOT\Flasher-and-License"
if exist "%PROD%" (
  echo Copying into Production Flasher-and-License\CEBJ-License-Tools\...
  if exist "%PROD%\CEBJ-License-Tools" rd /s /q "%PROD%\CEBJ-License-Tools"
  xcopy /E /I /Y "%OUT%\*" "%PROD%\CEBJ-License-Tools\" >nul
)

echo.
echo ============================================================
echo   DONE — all 3 apps are here:
echo   %OUT%
echo.
echo   CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe
echo   CEBJ-License-Generator\CEBJ-License-Generator.exe
echo   CEBJ-Buyer-Replacement-Flasher\CEBJ-Buyer-Replacement-Flasher.exe
echo   START-MENU.bat
echo ============================================================
echo.
if not defined NO_PAUSE pause
exit /b 0

:fail
echo.
echo BUILD FAILED
if not defined NO_PAUSE pause
exit /b 1
