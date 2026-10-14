@echo off
REM Normal local game entry for the installed map. No bench, mute, or time limit.
setlocal
set "AGL_ENGINE=D:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not exist "%~dp0resources\maps\tokyo_playable\package.json" (
  echo Installed Tokyo package is missing. Open project.godot for the fallback game.
  pause
  exit /b 1
)
if not exist "%AGL_ENGINE%" (
  echo Open project.godot with Godot 4.7 or newer and press F5.
  pause
  exit /b 1
)
set "AGL_TOKYO_HLOD_PACKAGE="
set "AGL_TOKYO_HLOD_PACKAGE_SHA="
set "AGL_TOKYO_VOLUME="
start "AGL" "%AGL_ENGINE%" --path "%~dp0"
exit /b 0
