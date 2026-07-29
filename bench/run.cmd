@echo off
REM AGL headless perf bench launcher (Windows cmd)
REM
REM Usage:
REM   bench\run.cmd                  - default stress_40 / 30s
REM   bench\run.cmd stress_40 60     - run for 60 seconds
REM
REM Output: bench\results\<scenario>_<UTC>.txt

setlocal
if not defined GODOT set "GODOT=D:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not exist "%GODOT%" goto GODOT_MISSING
set "VERSION_FILE=%TEMP%\agl_godot_version_%RANDOM%.txt"
"%GODOT%" --headless --version > "%VERSION_FILE%"
set /p GODOT_VERSION=<"%VERSION_FILE%"
del /q "%VERSION_FILE%" >nul 2>&1
echo %GODOT_VERSION%| findstr /b /c:"4.7" >nul
if errorlevel 1 goto GODOT_WRONG_VERSION
goto GODOT_OK

:GODOT_MISSING
echo [bench] ERROR: GODOT does not exist: %GODOT%
exit /b 2

:GODOT_WRONG_VERSION
echo [bench] ERROR: project.godot requires Godot 4.7; found %GODOT_VERSION%.
exit /b 2

:GODOT_OK
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
exit /b %EXIT_CODE%
