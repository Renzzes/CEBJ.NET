@echo off
cd /d "%~dp0"
echo.
echo  1 = ESP Flasher + License   (seller)
echo  2 = License Generator       (seller)
echo  3 = Buyer Replacement Flasher
echo.
set /p C=Choose 1-3:
if "%C%"=="1" start "" "CEBJ-ESP-Flasher\CEBJ-ESP-Flasher.exe"
if "%C%"=="2" start "" "CEBJ-License-Generator\CEBJ-License-Generator.exe"
if "%C%"=="3" start "" "CEBJ-Buyer-Replacement-Flasher\CEBJ-Buyer-Replacement-Flasher.exe"
