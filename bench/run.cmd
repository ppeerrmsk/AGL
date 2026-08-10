@echo off
REM AGL crash-safe Godot bench launcher for Windows.
REM Usage: bench\run.cmd [scenario] [duration_seconds] [timeout_seconds] [shadow^|inplace] [headless^|visual]

setlocal EnableExtensions
set "PROJECT_DIR=%~dp0.."
if not defined GODOT set "GODOT=D:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "SCENARIO=%~1"
if "%SCENARIO%"=="" set "SCENARIO=stress_40"
set "DURATION=%~2"
if "%DURATION%"=="" set "DURATION=30"
set "TIMEOUT=%~3"
if "%TIMEOUT%"=="" set "TIMEOUT=0"
set "RUN_MODE=%~4"
if "%RUN_MODE%"=="" set "RUN_MODE=%AGL_BENCH_MODE%"
if "%RUN_MODE%"=="" set "RUN_MODE=Shadow"
set "DISPLAY_MODE=%~5"
if "%DISPLAY_MODE%"=="" set "DISPLAY_MODE=%AGL_BENCH_DISPLAY_MODE%"
if "%DISPLAY_MODE%"=="" set "DISPLAY_MODE=Headless"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0invoke_godot.ps1" ^
  -GodotExe "%GODOT%" ^
  -ProjectDir "%PROJECT_DIR%" ^
  -Scenario "%SCENARIO%" ^
  -DurationSeconds "%DURATION%" ^
  -TimeoutSeconds "%TIMEOUT%" ^
  -ProcDumpExe "%AGL_PROCDUMP%" ^
  -RunMode "%RUN_MODE%" ^
  -DisplayMode "%DISPLAY_MODE%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo [bench] godot exited with code %EXIT_CODE%
echo [bench] check bench\results\ for output
dir /B /O:-D "%PROJECT_DIR%\bench\results\%SCENARIO%_*.txt" 2>nul
echo.
exit /b %EXIT_CODE%
