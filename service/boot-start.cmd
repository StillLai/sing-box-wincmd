@echo off
REM Boot-time launcher for sing-box
REM Launches sing-box outside Task Scheduler Job Object with no visible window.
REM Uses launch-hidden.ps1 (Win32 CreateProcess) for reliable Job Object escape.

setlocal EnableDelayedExpansion

set "MODE=%~1"
if "!MODE!"=="" set "MODE=mixed"

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

REM NOTE: exit 0 means spawn succeeded (async). Caller must verify sing-box is running.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$exe='!EXE!'; $argStr='run -c \"!CONFIG!\" -D \"!CORE_DIR!\"'; $dir='!CORE_DIR!'; & '%~dp0launch-hidden.ps1' -Exe $exe -CmdArgs $argStr -Dir $dir" >> "!LOG!" 2>&1
set "RET=!errorlevel!"

if !RET! neq 0 (
    echo [boot-start] ERROR: launch-hidden.ps1 failed, exit code !RET! >> "!LOG!" 2>&1
)
exit /b !RET!
