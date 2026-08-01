@echo off
REM AGL crash-safe Godot bench launcher for Windows.
REM Usage: bench\run.cmd [scenario] [duration_seconds] [timeout_seconds]

setlocal EnableExtensions
set "PROJECT_DIR=%~dp0.."
if not defined GODOT set "GODOT=D:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "SCENARIO=%~1"
if "%SCENARIO%"=="" set "SCENARIO=stress_40"
set "DURATION=%~2"
if "%DURATION%"=="" set "DURATION=30"
set "TIMEOUT=%~3"
if "%TIMEOUT%"=="" set "TIMEOUT=0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0invoke_godot.ps1" ^
  -GodotExe "%GODOT%" ^
  -ProjectDir "%PROJECT_DIR%" ^
  -Scenario "%SCENARIO%" ^
  -DurationSeconds "%DURATION%" ^
  -TimeoutSeconds "%TIMEOUT%" ^
  -ProcDumpExe "%AGL_PROCDUMP%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo [bench] godot exited with code %EXIT_CODE%
echo [bench] check bench\results\ for output
dir /B /O:-D "%PROJECT_DIR%\bench\results\%SCENARIO%_*.txt" 2>nul
echo.
exit /b %EXIT_CODE%
