@echo off
REM Opt-in GPU weather prototype, normal gameplay. Close game to restore default.
setlocal
set "AGL_WEATHER_VOLUME=on"
call "%~dp0play_installed.cmd"
exit /b %errorlevel%
