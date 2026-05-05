@echo off
REM AGL headless perf bench launcher (Windows cmd)
REM
REM Usage:
REM   bench\run.cmd                  - default stress_40 / 30s
REM   bench\run.cmd stress_40 60     - run for 60 seconds
REM
REM Output: bench\results\<scenario>_<UTC>.txt

setlocal
set "GODOT=C:\Users\noelu\Downloads\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64_console.exe"
set "SCENARIO=%~1"
if "%SCENARIO%"=="" set "SCENARIO=stress_40"
set "DURATION=%~2"
if "%DURATION%"=="" set "DURATION=30"

set "PROJECT_DIR=%~dp0.."
pushd "%PROJECT_DIR%"

echo [bench] scenario=%SCENARIO% duration=%DURATION%s
echo [bench] godot=%GODOT%
echo [bench] launching... (may take 10-20s before more output appears)
"%GODOT%" --headless --path . -- --bench=%SCENARIO% --duration=%DURATION%
set EXIT_CODE=%ERRORLEVEL%

echo.
echo [bench] godot exited with code %EXIT_CODE%
echo [bench] check bench\results\ for output
dir /B /O:-D bench\results\%SCENARIO%_*.txt 2>nul

popd
echo.
pause
exit /b %EXIT_CODE%
