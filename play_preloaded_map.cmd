@echo off
REM Optional resident-map trial; normal gameplay, no bench or time limit.
setlocal
set "AGL_TOKYO_RESIDENT_MIDDLE=1"
set "AGL_TOKYO_RESIDENCY_POOL_ONLY="
call "%~dp0play_installed.cmd"
exit /b %errorlevel%
