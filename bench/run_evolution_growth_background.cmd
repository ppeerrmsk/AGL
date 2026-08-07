@echo off
REM Background wrapper for the resumable 320-run evolution growth batch.
REM Launched with `cmd /c start "" /b` so no visible helper window is created.
setlocal EnableExtensions
set "PROJECT_DIR=%~dp0.."
set "OUT_DIR=%PROJECT_DIR%\bench\results\evolution_growth"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
cd /d "%PROJECT_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_evolution_growth.ps1" 1>>"%OUT_DIR%\batch.stdout.log" 2>>"%OUT_DIR%\batch.stderr.log"
exit /b %ERRORLEVEL%
