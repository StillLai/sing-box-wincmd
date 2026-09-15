@echo off
REM Boot-time launcher for sing-box
REM Launches sing-box outside Task Scheduler Job Object with no visible window.
REM Uses launch-hidden.ps1 (Win32 CreateProcess) for reliable Job Object escape.

REM NOTE: EnableDelayedExpansion -- paths must NOT contain '!' character.
setlocal EnableDelayedExpansion

set "MODE=%~1"
if "!MODE!"=="" set "MODE=mixed"

set "CORE_DIR=%~dp0core"
set "LOG=%CORE_DIR%\boot-start.log"

if /i not "!MODE!"=="mixed" if /i not "!MODE!"=="tun" (
    echo [boot-start] ERROR: invalid mode "!MODE!" >> "!LOG!" 2>&1
    exit /b 1
)

set "EXE=%CORE_DIR%\sing-box.exe"
set "CONFIG=%CORE_DIR%\config-!MODE!.json"

if not exist "!EXE!" (
    echo [boot-start] ERROR: sing-box.exe not found: "!EXE!" >> "!LOG!" 2>&1
    exit /b 1
)
if not exist "!CONFIG!" (
    echo [boot-start] ERROR: config not found: "!CONFIG!" >> "!LOG!" 2>&1
    exit /b 1
)

REM NOTE: exit 0 means spawn succeeded (async). Caller must verify sing-box is running.
REM Pass paths as separate parameters -- launch-hidden.ps1 builds the arg string
REM internally to avoid cmd.exe quote escaping issues.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-hidden.ps1" -Exe "!EXE!" -Config "!CONFIG!" -Dir "!CORE_DIR!"
set "RET=!errorlevel!"

if !RET! neq 0 (
    echo [boot-start] ERROR: launch-hidden.ps1 failed, exit code !RET! >> "!LOG!" 2>&1
)
exit /b !RET!
