@echo off
cd /d "%~dp0"
if exist "%~dp0dist\CEBJ-License-Tools\CEBJ-License-Generator\CEBJ-License-Generator.exe" (
  start "" "%~dp0dist\CEBJ-License-Tools\CEBJ-License-Generator\CEBJ-License-Generator.exe"
  exit /b 0
)
if not exist .venv\Scripts\python.exe (
  py -3 -m venv .venv
  .venv\Scripts\pip install -r requirements.txt
)
.venv\Scripts\python.exe -m app.license_generator_app
pause
