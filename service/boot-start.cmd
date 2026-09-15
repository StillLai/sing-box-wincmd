@echo off
REM Boot-time launcher for sing-box
REM Usage: boot-start.cmd <mode>
REM   mode = mixed | tun
REM Uses cmd /c start "" to launch sing-box in a new console,
REM independent of the Task Scheduler Job Object.

setlocal EnableDelayedExpansion

set "MODE=%~1"
if "!MODE!"=="" set "MODE=mixed"

REM Validate mode
if /i not "!MODE!"=="mixed" if /i not "!MODE!"=="tun" (
    echo [boot-start] ERROR: invalid mode "!MODE!" >&2
    exit /b 1
)

set "CORE_DIR=%~dp0core"
set "EXE=%CORE_DIR%\sing-box.exe"
set "CONFIG=%CORE_DIR%\config-!MODE!.json"
set "LOG=%CORE_DIR%\boot-start.log"

if not exist "!EXE!" (
    echo [boot-start] ERROR: sing-box.exe not found: "!EXE!" >> "!LOG!" 2>&1
    exit /b 1
)
if not exist "!CONFIG!" (
    echo [boot-start] ERROR: config not found: "!CONFIG!" >> "!LOG!" 2>&1
    exit /b 1
)

REM Launch sing-box in a new console (independent of Task Scheduler Job Object)
REM Critical: cd to CORE_DIR first so sing-box inherits the correct CWD.
REM Without this, SYSTEM's CWD defaults to C:\Windows\System32, breaking
REM relative paths in config (e.g. "path": "dashboard", log file names).
cmd /c cd /d "!CORE_DIR!" && start "" "!EXE!" run -c "!CONFIG!" -D "!CORE_DIR!"
exit /b 0
