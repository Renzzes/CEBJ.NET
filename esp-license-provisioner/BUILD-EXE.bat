@echo off
rem Legacy single-app build — prefer BUILD-ALL-EXES.bat for all 3 apps
setlocal EnableExtensions
cd /d "%~dp0"
echo Building all 3 apps via BUILD-ALL-EXES.bat ...
echo.
set "NO_PAUSE=1"
call "%~dp0BUILD-ALL-EXES.bat"
exit /b %ERRORLEVEL%
