@echo off
REM Boot-time launcher for sing-box
REM Usage: boot-start.cmd <mode>
REM   mode = mixed | tun
REM Uses cmd /c start "" to launch sing-box in a new console,
REM independent of the Task Scheduler Job Object.

setlocal EnableDelayedExpansion

set "MODE=%~1"
if "!MODE!"=="" set "MODE=mixed"

set "CORE_DIR=%~dp0core"
set "EXE=%CORE_DIR%\sing-box.exe"
set "CONFIG=%CORE_DIR%\config-!MODE!.json"

if not exist "!EXE!" exit /b 1
if not exist "!CONFIG!" exit /b 1

cmd /c start "" "!EXE!" run -c "!CONFIG!" -D "!CORE_DIR!"
exit /b !errorlevel!
