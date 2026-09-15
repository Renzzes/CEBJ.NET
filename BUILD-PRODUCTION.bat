@echo off
setlocal EnableExtensions EnableDelayedExpansion
title KonekSik-fi Piso Wifi Production Builder
cd /d "%~dp0"

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "OUT=%ROOT%\KonekSik-fi Piso Wifi Production"
set "RUIJIE_SRC=%ROOT%\EXTRACTED-OPENWRT-FASTFI-V2.5.1\rootfs"
set "ESP_SRC=%ROOT%\esp-coinslot"
set "FLASH_SRC=%ROOT%\esp-license-provisioner"
set "APP_SRC=%ROOT%\gcash-companion"

echo.
echo ============================================================
echo   KonekSik-fi Piso Wifi — Production packager
echo ============================================================
echo   Output folder:
echo   %OUT%
echo.

if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OUT%\01-RUIJIE-OPENWRT" mkdir "%OUT%\01-RUIJIE-OPENWRT"
if not exist "%OUT%\02-ESP-COINSLOT" mkdir "%OUT%\02-ESP-COINSLOT"
if not exist "%OUT%\02-ESP-COINSLOT\firmware" mkdir "%OUT%\02-ESP-COINSLOT\firmware"
if not exist "%OUT%\02-ESP-COINSLOT\Flasher-and-License" mkdir "%OUT%\02-ESP-COINSLOT\Flasher-and-License"
if not exist "%OUT%\03-GCASH-COMPANION" mkdir "%OUT%\03-GCASH-COMPANION"
if not exist "%OUT%\logs" mkdir "%OUT%\logs"

call :write_guides

echo [1/4] Ruijie OpenWrt sysupgrade .bin
call :build_ruijie
echo.
echo [2/4] ESP coinslot firmware .bin
call :build_esp
echo.
echo [3/4] ESP Flasher + License tool
call :pack_flasher_license
echo.
echo [4/4] GCash companion APK
call :build_apk
echo.
call :write_summary

echo.
echo ============================================================
echo   DONE — open this folder:
echo   %OUT%
echo ============================================================
echo.
explorer "%OUT%"
pause
exit /b 0

:: ------------------------------------------------------------
:build_ruijie
if not exist "%RUIJIE_SRC%\build-image.sh" (
  echo   SKIP: missing rootfs\build-image.sh
  echo SKIPPED - missing build-image.sh> "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt"
  exit /b 0
)
where wsl >nul 2>&1
if errorlevel 1 (
  echo   SKIP: WSL not found.
  echo   Install Ubuntu WSL, then re-run this bat.
  echo   Command: wsl --install -d Ubuntu
  echo SKIPPED - WSL required> "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt"
  exit /b 0
)

echo   Building via WSL ImageBuilder ^(first run downloads toolchain — slow^)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\build-ruijie-wsl.ps1" -OverlayPath "%RUIJIE_SRC%" -LogPath "%OUT%\logs\ruijie-build.log" -Suffix koneksik > "%OUT%\logs\ruijie-ps.log" 2>&1
if errorlevel 1 (
  echo   FAIL: see logs\ruijie-build.log and logs\ruijie-ps.log
  echo FAILED - see logs> "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt"
  exit /b 0
)

set "FOUND="
for /f "delims=" %%F in ('dir /b /a-d /o-d "%RUIJIE_SRC%\fastfi-v6-*.bin" 2^>nul') do (
  if not defined FOUND set "FOUND=%%F"
)
if not defined FOUND (
  for /f "delims=" %%F in ('dir /b /a-d /o-d "%RUIJIE_SRC%\*.bin" 2^>nul') do (
    if /I not "%%F"=="kernel.bin" if not defined FOUND set "FOUND=%%F"
  )
)
if not defined FOUND (
  echo   FAIL: no sysupgrade .bin in rootfs after build
  echo FAILED - no bin output> "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt"
  exit /b 0
)

copy /Y "%RUIJIE_SRC%\!FOUND!" "%OUT%\01-RUIJIE-OPENWRT\KonekSik-fi-EW1200G-PRO-sysupgrade.bin" >nul
if exist "%RUIJIE_SRC%\!FOUND!.sha256" copy /Y "%RUIJIE_SRC%\!FOUND!.sha256" "%OUT%\01-RUIJIE-OPENWRT\KonekSik-fi-EW1200G-PRO-sysupgrade.bin.sha256" >nul
echo OK - !FOUND!> "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt"
echo   OK: 01-RUIJIE-OPENWRT\KonekSik-fi-EW1200G-PRO-sysupgrade.bin
exit /b 0

:: ------------------------------------------------------------
:build_esp
if not exist "%ESP_SRC%\platformio.ini" (
  echo   SKIP: missing esp-coinslot
  echo SKIPPED> "%OUT%\02-ESP-COINSLOT\STATUS.txt"
  exit /b 0
)

set "PIO="
where pio >nul 2>&1 && set "PIO=pio"
if not defined PIO where platformio >nul 2>&1 && set "PIO=platformio"
if not defined PIO if exist "%USERPROFILE%\.platformio\penv\Scripts\pio.exe" set "PIO=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if not defined PIO (
  echo   SKIP: PlatformIO CLI not found.
  echo   Install: pip install platformio
  echo SKIPPED - install PlatformIO> "%OUT%\02-ESP-COINSLOT\STATUS.txt"
  exit /b 0
)

echo   Building all ESP board envs...
pushd "%ESP_SRC%"
"%PIO%" run > "%OUT%\logs\esp-build.log" 2>&1
popd

set "COPIED=0"
for %%E in (esp8266_lanbase_w5500 esp8266_wifi esp32_w5500 esp32s3_w5500 esp32_eth) do (
  if exist "%ESP_SRC%\.pio\build\%%E\firmware.bin" (
    copy /Y "%ESP_SRC%\.pio\build\%%E\firmware.bin" "%OUT%\02-ESP-COINSLOT\firmware\%%E-firmware.bin" >nul
    echo   OK: firmware\%%E-firmware.bin
    set /a COPIED+=1
  )
)
if "!COPIED!"=="0" (
  echo   FAIL: no firmware.bin — see logs\esp-build.log
  echo FAILED - see logs\esp-build.log> "%OUT%\02-ESP-COINSLOT\STATUS.txt"
) else (
  echo OK - !COPIED! board bin(s^)> "%OUT%\02-ESP-COINSLOT\STATUS.txt"
)
exit /b 0

:: ------------------------------------------------------------
:pack_flasher_license
if not exist "%FLASH_SRC%\run.bat" (
  echo   SKIP: missing esp-license-provisioner
  echo SKIPPED - missing esp-license-provisioner> "%OUT%\02-ESP-COINSLOT\Flasher-and-License\STATUS.txt"
  exit /b 0
)

set "DEST=%OUT%\02-ESP-COINSLOT\Flasher-and-License"
echo   Packaging flasher + license tool into Production...

rem Clean previous pack (keep structure)
if exist "%DEST%" rd /s /q "%DEST%"
mkdir "%DEST%"
mkdir "%DEST%\firmware"

rem Copy app without heavy .venv / caches
robocopy "%FLASH_SRC%" "%DEST%" /E /NFL /NDL /NJH /NJS /nc /ns /np ^
  /XD .venv __pycache__ .git logs ^
  /XF *.pyc > "%OUT%\logs\flasher-robocopy.log" 2>&1

rem Ensure firmware folder exists for Browse in UI
if not exist "%DEST%\firmware" mkdir "%DEST%\firmware"

rem Drop freshly built ESP bins into flasher firmware\ for one-click browse
set "FW_IN=0"
for %%F in ("%OUT%\02-ESP-COINSLOT\firmware\*-firmware.bin") do (
  if exist "%%~fF" (
    copy /Y "%%~fF" "%DEST%\firmware\%%~nxF" >nul
    set /a FW_IN+=1
  )
)

> "%DEST%\HOW-TO-USE.txt" (
  echo ESP Flasher + License ^(included in Production^)
  echo ==============================================
  echo.
  echo This is the Windows tool that:
  echo   1. Flashes coinslot firmware to the ESP
  echo   2. Generates an offline license
  echo   3. Writes the license to the ESP ^(no cloud^)
  echo.
  echo First time on this PC:
  echo   1. Install Python 3 if needed
  echo   2. Double-click run.bat  ^(creates .venv + installs deps^)
  echo.
  echo Every ESP unit:
  echo   1. Plug ESP USB
  echo   2. run.bat
  echo   3. Select board + COM port
  echo   4. Browse firmware\*-firmware.bin ^(already copied here^)
  echo   5. Flash + License ^(full provision^)
  echo.
  echo Keep keys\ private — that is your signing key.
)

> "%DEST%\START-FLASHER.bat" (
  echo @echo off
  echo cd /d "%%~dp0"
  echo call run.bat
)

if exist "%DEST%\run.bat" (
  echo OK - flasher+license packed, firmware bins linked: !FW_IN!> "%DEST%\STATUS.txt"
  echo   OK: 02-ESP-COINSLOT\Flasher-and-License\  ^(run START-FLASHER.bat^)
) else (
  echo FAILED - pack incomplete> "%DEST%\STATUS.txt"
  echo   FAIL: flasher pack incomplete — see logs\flasher-robocopy.log
)
exit /b 0

:: ------------------------------------------------------------
:build_apk
if not exist "%APP_SRC%\app\build.gradle.kts" (
  echo   SKIP: missing gcash-companion
  echo SKIPPED> "%OUT%\03-GCASH-COMPANION\STATUS.txt"
  exit /b 0
)

copy /Y "%APP_SRC%\pool-sample.json" "%OUT%\03-GCASH-COMPANION\pool-sample.json" >nul 2>&1
copy /Y "%APP_SRC%\README.md" "%OUT%\03-GCASH-COMPANION\README-SOURCE.md" >nul 2>&1

if exist "%APP_SRC%\gradlew.bat" (
  echo   Building APK with Gradle wrapper...
  pushd "%APP_SRC%"
  call gradlew.bat assembleDebug --no-daemon > "%OUT%\logs\apk-build.log" 2>&1
  set "APK_ERR=!errorlevel!"
  popd
  if "!APK_ERR!"=="0" if exist "%APP_SRC%\app\build\outputs\apk\debug\app-debug.apk" (
    copy /Y "%APP_SRC%\app\build\outputs\apk\debug\app-debug.apk" "%OUT%\03-GCASH-COMPANION\KonekSik-GCash-Companion.apk" >nul
    echo OK - APK built> "%OUT%\03-GCASH-COMPANION\STATUS.txt"
    echo   OK: KonekSik-GCash-Companion.apk
    exit /b 0
  )
)

if exist "%APP_SRC%\app\build\outputs\apk\debug\app-debug.apk" (
  copy /Y "%APP_SRC%\app\build\outputs\apk\debug\app-debug.apk" "%OUT%\03-GCASH-COMPANION\KonekSik-GCash-Companion.apk" >nul
  echo OK - copied existing APK> "%OUT%\03-GCASH-COMPANION\STATUS.txt"
  echo   OK: copied existing app-debug.apk
  exit /b 0
)

echo   SKIP: APK not built yet.
echo   Open gcash-companion in Android Studio → Build → Build APK^(s^),
echo   then re-run this bat.
echo SKIPPED - build APK in Android Studio then re-run> "%OUT%\03-GCASH-COMPANION\STATUS.txt"
exit /b 0

:: ------------------------------------------------------------
:write_guides
> "%OUT%\README-INSTALL-ORDER.txt" (
  echo KonekSik-fi Piso Wifi — Production package
  echo ==========================================
  echo.
  echo Install in this order:
  echo.
  echo 1^) 01-RUIJIE-OPENWRT
  echo    Flash KonekSik-fi-EW1200G-PRO-sysupgrade.bin to the Ruijie.
  echo.
  echo 2^) 02-ESP-COINSLOT
  echo    a. firmware\  = coinslot .bin files
  echo    b. Flasher-and-License\  = Windows flasher + offline license tool
  echo       Double-click Flasher-and-License\START-FLASHER.bat
  echo       Select board, COM port, browse firmware\*.bin
  echo       Use Flash + License ^(full provision^)
  echo.
  echo 3^) 03-GCASH-COMPANION
  echo    Install APK on YOUR operator phone ^(not customers^).
  echo.
  echo Each folder has STATUS.txt ^(OK / SKIPPED / FAILED^).
  echo Rebuild anytime: double-click BUILD-PRODUCTION.bat
)

> "%OUT%\01-RUIJIE-OPENWRT\HOW-TO-FLASH.txt" (
  echo Ruijie EW1200G Pro
  echo ------------------
  echo Upload KonekSik-fi-EW1200G-PRO-sysupgrade.bin via Admin OTA / sysupgrade.
  echo Wait for reboot. Do not power off mid-flash.
)

> "%OUT%\02-ESP-COINSLOT\HOW-TO-FLASH.txt" (
  echo ESP coinslot + license
  echo ----------------------
  echo firmware\              = board firmware bins
  echo Flasher-and-License\   = flash tool + license signer
  echo.
  echo 1. Open Flasher-and-License\START-FLASHER.bat
  echo 2. Choose your board + COM port
  echo 3. Browse a file from firmware\
  echo 4. Flash + License ^(full provision^)
  echo.
  echo Do NOT skip the license step — coinslot needs it.
)

> "%OUT%\03-GCASH-COMPANION\HOW-TO-INSTALL.txt" (
  echo GCash Companion — OPERATOR PHONE ONLY
  echo -------------------------------------
  echo Customers do NOT install this.
  echo.
  echo 1. Install the APK on the phone that receives GCash.
  echo 2. Admin → GCash → secret + export pool.
  echo 3. App Setup → secret, router URL, import JSON.
  echo 4. Enable notification + SMS permissions.
  echo 5. Status → listening ON.
)
exit /b 0

:: ------------------------------------------------------------
:write_summary
> "%OUT%\BUILD-SUMMARY.txt" (
  echo Built: %DATE% %TIME%
  echo.
  echo [1 Ruijie]
)
type "%OUT%\01-RUIJIE-OPENWRT\STATUS.txt" >> "%OUT%\BUILD-SUMMARY.txt" 2>nul
>> "%OUT%\BUILD-SUMMARY.txt" echo.
>> "%OUT%\BUILD-SUMMARY.txt" echo [2 ESP firmware]
type "%OUT%\02-ESP-COINSLOT\STATUS.txt" >> "%OUT%\BUILD-SUMMARY.txt" 2>nul
>> "%OUT%\BUILD-SUMMARY.txt" echo.
>> "%OUT%\BUILD-SUMMARY.txt" echo [3 Flasher + License]
type "%OUT%\02-ESP-COINSLOT\Flasher-and-License\STATUS.txt" >> "%OUT%\BUILD-SUMMARY.txt" 2>nul
>> "%OUT%\BUILD-SUMMARY.txt" echo.
>> "%OUT%\BUILD-SUMMARY.txt" echo [4 GCash APK]
type "%OUT%\03-GCASH-COMPANION\STATUS.txt" >> "%OUT%\BUILD-SUMMARY.txt" 2>nul
exit /b 0
