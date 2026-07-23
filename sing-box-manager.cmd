@echo off
chcp 65001 >nul 2>nul

REM Check admin privilege, auto-elevate if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin privilege...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

REM Ensure we run from the script's directory
cd /d "%~dp0"

setlocal EnableDelayedExpansion

REM ============================================================================
REM Sing-Box Manager for Windows
REM ============================================================================

REM Load user config from config.env
set "CONFIG_FILE=%~dp0config.env"
if not exist "%CONFIG_FILE%" (
    echo [错误] 未找到 config.env，请复制 config.env.example 为 config.env 并填入你的配置。
    echo         copy config.env.example config.env
    pause >nul
    exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%a in ("%CONFIG_FILE%") do (
    set "LINE=%%a"
    if not "!LINE:~0,1!"=="#" if not "!LINE:~0,1!"=="" (
        set "%%a=%%b"
    )
)

REM Global proxy prefix for file downloads (API queries go direct)
REM If not set or empty, downloads will go directly to GitHub

REM Validate required config
if not defined MIXED_SUB_URL (
    echo [错误] config.env 中未设置 MIXED_SUB_URL，请检查配置。
    pause >nul
    exit /b 1
)
if not defined TUN_SUB_URL (
    echo [错误] config.env 中未设置 TUN_SUB_URL，请检查配置。
    pause >nul
    exit /b 1
)

REM Scheduled task names
set "TASK_MIXED=sing-box-mixed"
set "TASK_TUN=sing-box-tun"

REM sing-box paths
set "SINGBOX_EXE=%~dp0service\core\sing-box.exe"
set "MIXED_CONFIG_ABS=%~dp0service\core\config-mixed.json"
set "TUN_CONFIG_ABS=%~dp0service\core\config-tun.json"

goto :main

REM ============================================================================
REM Color output helpers
REM ============================================================================

:setESC
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$E# & echo on & for %%b in (1) do rem"') do (
    set "ESC=%%a"
)
goto :eof

:echoInfo
echo %ESC%[96m[信息] %~1%ESC%[0m
goto :eof

:echoSuccess
echo %ESC%[92m[成功] %~1%ESC%[0m
goto :eof

:echoWarn
echo %ESC%[93m[警告] %~1%ESC%[0m
goto :eof

:echoError
echo %ESC%[91m[错误] %~1%ESC%[0m
goto :eof

:echoColor
echo %ESC%[%~1m%~2%ESC%[0m
goto :eof

REM ============================================================================
REM Check if a scheduled task exists
REM   %1 = task name
REM   exit /b 0 if exists, 1 otherwise
REM ============================================================================
:taskExists
schtasks /query /tn "%~1" >nul 2>nul
if !errorlevel! equ 0 exit /b 0
exit /b 1

REM ============================================================================
REM Check if a scheduled task is enabled
REM   %1 = task name
REM   exit /b 0 if enabled, 1 if disabled or not exists
REM ============================================================================
:taskEnabled
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $t = Get-ScheduledTask -TaskName '%~1'; if ($t.State -eq 'Disabled') { exit 1 } else { exit 0 } } catch { exit 1 }" >nul 2>nul
exit /b !errorlevel!

REM ============================================================================
REM Check if sing-box is running with a specific config
REM   %1 = config keyword (e.g. "config-mixed" or "config-tun")
REM   exit /b 0 if running, 1 otherwise
REM ============================================================================
:sbRunning
set "PS_SB=%temp%\sb_running.ps1"
echo $p = Get-CimInstance Win32_Process -Filter "Name='sing-box.exe'" 2^>$null; if ($p -and ($p.CommandLine -match '%~1')) { exit 0 } else { exit 1 } > "%PS_SB%"
powershell -ExecutionPolicy Bypass -File "%PS_SB%" >nul 2>nul
set "SB_RET=!errorlevel!"
del /f /q "%PS_SB%" >nul 2>nul
exit /b !SB_RET!

REM ============================================================================
REM Start sing-box via scheduled task (runs as SYSTEM)
REM   %1 = config file absolute path
REM ============================================================================
:startSb
REM Launch sing-box via scheduled task (runs as SYSTEM)
REM Temporarily enable task if disabled, run it, then restore state
if /i "%~1"=="!MIXED_CONFIG_ABS!" (
    set "TARGET_TASK=%TASK_MIXED%"
) else (
    set "TARGET_TASK=%TASK_TUN%"
)
call :taskEnabled "!TARGET_TASK!"
set "WAS_DISABLED=!errorlevel!"
if !WAS_DISABLED! equ 1 (
    schtasks /change /tn "!TARGET_TASK!" /enable >nul 2>nul
)
schtasks /run /tn "!TARGET_TASK!" >nul 2>nul
if !WAS_DISABLED! equ 1 (
    timeout /t 1 /nobreak >nul 2>nul
    schtasks /change /tn "!TARGET_TASK!" /disable >nul 2>nul
)
goto :eof

REM ============================================================================
REM Update kernel
REM ============================================================================
:updateKernel
set "SINGBOX_EXE=service\core\sing-box.exe"
set "API_URL=https://api.github.com/repos/reF1nd/sing-box-releases/releases"
set "GITHUB_BASE=https://github.com/reF1nd/sing-box-releases/releases/download"
call :echoInfo "正在检查最新版本..."

if not exist "service\core" mkdir "service\core" >nul 2>nul

REM Query GitHub API: curl downloads JSON, PowerShell parses tag_name to a text file, then set /p reads it
REM (avoids chcp 65001 temp-PS1 encoding issue and for/f backtick pipe issue)
curl -s --connect-timeout 15 --max-time 15 -o "%temp%\sb_ver.json" "%API_URL%/latest" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$j = Get-Content '%temp%\sb_ver.json' -Raw | ConvertFrom-Json; $j.tag_name | Out-File '%temp%\sb_ver.txt' -Encoding ascii" >nul 2>nul
set "VERSION="
if exist "%temp%\sb_ver.txt" set /p VERSION=<"%temp%\sb_ver.txt"
del /f /q "%temp%\sb_ver.json" "%temp%\sb_ver.txt" >nul 2>nul

echo !VERSION! | findstr /b /c:"v" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "获取版本失败，返回值: !VERSION!"
    exit /b 1
)
call :echoSuccess "最新版本: !VERSION!"

if exist "%SINGBOX_EXE%" copy /y "%SINGBOX_EXE%" "%SINGBOX_EXE%.bak" >nul 2>nul

set "VERSION_NUM=!VERSION:~1!"
set "TEMP_ZIP=%temp%\sb_update.zip"

REM Build download URL: prepend PROXY_PREFIX for the actual file download
set "RAW_DOWNLOAD_URL=%GITHUB_BASE%/!VERSION!/sing-box-!VERSION_NUM!-windows-amd64v3.zip"
set "PROXY_DOWNLOAD_URL=%PROXY_PREFIX%%RAW_DOWNLOAD_URL%"

call :echoInfo "正在下载 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --retry-delay 5 --retry-all-errors --connect-timeout 30 --max-time 300 -o "!TEMP_ZIP!" "!PROXY_DOWNLOAD_URL!" >nul 2>nul

if !errorlevel! neq 0 (
    call :echoError "下载失败，请检查网络连接或代理设置"
    goto :restoreKernel
)

for %%z in ("!TEMP_ZIP!") do set "ZSIZE=%%~zz"
if !ZSIZE! lss 1000000 (
    call :echoError "下载文件过小 (!ZSIZE! 字节)，可能下载了错误页面"
    goto :restoreKernel
)

call :echoSuccess "下载完成 (!ZSIZE! 字节)"

REM Detect mode BEFORE killing so we know what to restart
set "RUNNING_MODE="
call :sbRunning "config-mixed"
if !errorlevel! equ 0 set "RUNNING_MODE=mixed"
call :sbRunning "config-tun"
if !errorlevel! equ 0 set "RUNNING_MODE=tun"
if defined RUNNING_MODE (
    call :echoInfo "检测到 sing-box 正在运行 (%RUNNING_MODE%)，正在停止..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

REM Extract sing-box.exe directly from ZIP to final location
call :echoInfo "正在解压..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead('!TEMP_ZIP!'); $e = $z.Entries | Where-Object { $_.Name -eq 'sing-box.exe' }; if ($e) { $s = $e.Open(); $f = [IO.File]::Create('%SINGBOX_EXE%'); $s.CopyTo($f); $f.Dispose(); $s.Dispose() }; $z.Dispose()" >nul 2>nul
del /f /q "!TEMP_ZIP!" >nul 2>nul

if !errorlevel! neq 0 (
    call :echoError "解压失败"
    goto :restoreKernel
)

call :echoSuccess "内核已更新"

if defined RUNNING_MODE (
    call :echoInfo "正在重新启动 sing-box..."
    call :restartRunningMode !RUNNING_MODE!
)

del /f /q "%SINGBOX_EXE%.bak" >nul 2>nul
exit /b 0

:restoreKernel
call :echoWarn "正在从备份恢复..."
if exist "%SINGBOX_EXE%.bak" (
    copy /y "%SINGBOX_EXE%.bak" "%SINGBOX_EXE%" >nul 2>nul
    if !errorlevel! equ 0 (
        call :echoInfo "已恢复旧内核"
    ) else (
        call :echoError "恢复旧内核失败"
    )
) else (
    call :echoWarn "未找到备份文件，无法恢复"
)
del /f /q "%temp%\sb_update.zip" >nul 2>nul
exit /b 1

REM ============================================================================
REM Wait for TUN network readiness after (re)start
REM ============================================================================
:waitTunReady
set /a "WAIT_COUNT=0"
:waitTunLoop
curl -s --max-time 3 -o nul "https://cp.cloudflare.com" >nul 2>nul
if !errorlevel! equ 0 (
    call :echoSuccess "TUN 网络已就绪"
    goto :eof
)
set /a "WAIT_COUNT+=1"
if !WAIT_COUNT! geq 10 (
    call :echoWarn "TUN 网络就绪检测超时 (30s)"
    goto :eof
)
timeout /t 3 /nobreak >nul 2>nul
goto :waitTunLoop

REM ============================================================================
REM Restart whichever mode was running (mixed or tun)
REM ============================================================================
:restartRunningMode
REM %1 = "mixed" or "tun" (auto-detect if not provided)
if not "%~1"=="" (
    call :startMode "%~1"
    goto :eof
)
call :sbRunning "config-mixed"
if !errorlevel! equ 0 (
    call :startMode "mixed"
    goto :eof
)
call :sbRunning "config-tun"
if !errorlevel! equ 0 (
    call :startMode "tun"
    goto :eof
)
call :echoInfo "无运行中的实例"
goto :eof

REM ============================================================================
REM Update subscription
REM ============================================================================
:updateSub
set "CONFIG_DIR=service\core"

set "MIXED_FILE=%CONFIG_DIR%\config-mixed.json"
set "TUN_FILE=%CONFIG_DIR%\config-tun.json"

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" >nul 2>nul

REM Backup existing configs before downloading
if exist "%MIXED_FILE%" copy /y "%MIXED_FILE%" "%MIXED_FILE%.bak" >nul 2>nul
if exist "%TUN_FILE%" copy /y "%TUN_FILE%" "%TUN_FILE%.bak" >nul 2>nul

REM Download Mixed config
call :echoInfo "正在下载 Mixed 配置 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 60 -o "%MIXED_FILE%" "%PROXY_PREFIX%%MIXED_SUB_URL%" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "Mixed 配置下载失败"
    if exist "%MIXED_FILE%.bak" copy /y "%MIXED_FILE%.bak" "%MIXED_FILE%" >nul 2>nul
    exit /b 1
)

REM Download Tun config
call :echoInfo "正在下载 Tun 配置 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 60 -o "%TUN_FILE%" "%PROXY_PREFIX%%TUN_SUB_URL%" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "Tun 配置下载失败"
    if exist "%TUN_FILE%.bak" copy /y "%TUN_FILE%.bak" "%TUN_FILE%" >nul 2>nul
    exit /b 1
)

REM All downloads succeeded — clean up backups
del /f /q "%MIXED_FILE%.bak" "%TUN_FILE%.bak" >nul 2>nul
call :echoSuccess "订阅配置已更新"

REM Restart running instance to apply new config
REM Detect mode BEFORE killing so we know what to restart
set "RUNNING_MODE="
call :sbRunning "config-mixed"
if !errorlevel! equ 0 set "RUNNING_MODE=mixed"
call :sbRunning "config-tun"
if !errorlevel! equ 0 set "RUNNING_MODE=tun"
if defined RUNNING_MODE (
    call :echoInfo "检测到 sing-box 正在运行 (%RUNNING_MODE%)，正在重启以应用新配置..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
    call :restartRunningMode !RUNNING_MODE!
) else (
    call :echoInfo "无运行中的实例，新配置将在下次启动时生效"
)
exit /b 0

REM ============================================================================
REM Ensure scheduled tasks exist (auto-create if missing)
REM ============================================================================
:ensureTasks
if not exist "!SINGBOX_EXE!" (
    call :echoError "未找到 sing-box.exe，请先更新内核"
    exit /b 1
)
if not exist "%~dp0service\start-singbox.vbs" (
    call :echoError "未找到 start-singbox.vbs"
    exit /b 1
)

call :taskExists "%TASK_MIXED%" || (
    call :echoInfo "创建 %TASK_MIXED% 计划任务 (SYSTEM)..."
    schtasks /create /tn "%TASK_MIXED%" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" mixed" /sc onstart /ru SYSTEM /rl highest /f >nul 2>nul
    schtasks /change /tn "%TASK_MIXED%" /disable >nul 2>nul
)
call :taskExists "%TASK_TUN%" || (
    call :echoInfo "创建 %TASK_TUN% 计划任务 (SYSTEM)..."
    schtasks /create /tn "%TASK_TUN%" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" tun" /sc onstart /ru SYSTEM /rl highest /f >nul 2>nul
    schtasks /change /tn "%TASK_TUN%" /disable >nul 2>nul
)
exit /b 0

REM ============================================================================
REM Switch boot mode: enable target task, disable the other, start target mode
REM   %1 = "mixed" or "tun"
REM ============================================================================
:switchBoot
if /i "%~1"=="tun" (
    if not exist "service\core\config-tun.json" (
        call :echoError "未找到 config-tun.json，请先更新订阅"
        exit /b 1
    )
)

call :ensureTasks
if !errorlevel! neq 0 exit /b 1

if /i "%~1"=="mixed" (
    call :echoInfo "切换开机自启为 Mixed 模式..."
    schtasks /change /tn "%TASK_MIXED%" /enable >nul 2>nul
    schtasks /change /tn "%TASK_TUN%" /disable >nul 2>nul
) else (
    call :echoInfo "切换开机自启为 TUN 模式..."
    schtasks /change /tn "%TASK_TUN%" /enable >nul 2>nul
    schtasks /change /tn "%TASK_MIXED%" /disable >nul 2>nul
)

call :startMode "%~1"
exit /b !errorlevel!

REM ============================================================================
REM Stop all sing-box processes
REM ============================================================================
:stopSingbox
call :sbRunning "config"
if !errorlevel! neq 0 (
    call :echoWarn "sing-box 未在运行"
    exit /b 0
)
call :echoInfo "停止 sing-box..."
taskkill /f /im sing-box.exe >nul 2>nul
if !errorlevel! equ 0 (
    call :echoSuccess "sing-box 已停止"
) else (
    call :echoError "停止失败"
)
exit /b !errorlevel!

REM ============================================================================
REM Start or restart sing-box in specified mode
REM   %1 = "mixed" or "tun"
REM ============================================================================
:startMode
if /i "%~1"=="tun" (
    if not exist "service\core\config-tun.json" (
        call :echoError "未找到 config-tun.json，请先更新订阅"
        exit /b 1
    )
)

call :ensureTasks
if !errorlevel! neq 0 exit /b 1

REM Stop any running sing-box
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止当前运行的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

if /i "%~1"=="mixed" (
    call :echoInfo "启动 sing-box (Mixed 模式)..."
    call :startSb "!MIXED_CONFIG_ABS!"
    timeout /t 5 /nobreak >nul 2>nul
    call :sbRunning "config-mixed"
    if !errorlevel! equ 0 (
        call :echoSuccess "sing-box (Mixed 模式) 已启动"
    ) else (
        call :echoError "启动失败"
    )
) else (
    call :echoInfo "启动 sing-box (TUN 模式)..."
    call :startSb "!TUN_CONFIG_ABS!"
    timeout /t 5 /nobreak >nul 2>nul
    call :sbRunning "config-tun"
    if !errorlevel! equ 0 (
        call :waitTunReady
        call :echoSuccess "已切换到 TUN 模式"
    ) else (
        call :echoError "TUN 模式启动失败，尝试恢复 Mixed..."
        call :startSb "!MIXED_CONFIG_ABS!"
    )
)
exit /b !errorlevel!

REM ============================================================================
REM Uninstall scheduled tasks
REM ============================================================================
:uninstallTask
set "HAD_ERROR=0"

call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止运行中的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

call :taskExists "%TASK_TUN%" && (
    call :echoInfo "删除 %TASK_TUN% 任务..."
    schtasks /delete /tn "%TASK_TUN%" /f >nul 2>nul
    if !errorlevel! equ 0 (
        call :echoSuccess "%TASK_TUN% 已删除"
    ) else (
        call :echoError "%TASK_TUN% 删除失败"
        set "HAD_ERROR=1"
    )
) || (
    call :echoWarn "%TASK_TUN% 任务不存在，跳过"
)

call :taskExists "%TASK_MIXED%" && (
    call :echoInfo "删除 %TASK_MIXED% 任务..."
    schtasks /delete /tn "%TASK_MIXED%" /f >nul 2>nul
    if !errorlevel! equ 0 (
        call :echoSuccess "%TASK_MIXED% 已删除"
    ) else (
        call :echoError "%TASK_MIXED% 删除失败"
        set "HAD_ERROR=1"
    )
) || (
    call :echoWarn "%TASK_MIXED% 任务不存在，跳过"
)
exit /b %HAD_ERROR%

REM ============================================================================
REM Display status
REM ============================================================================
:showStatus
REM Determine boot mode
set "BOOT_MODE=未注册"
call :taskExists "!TASK_MIXED!"
set "MIXED_EXISTS=!errorlevel!"
call :taskExists "!TASK_TUN!"
set "TUN_EXISTS=!errorlevel!"

REM If either task exists, default to 未设置 (will be overridden if one is enabled)
if !MIXED_EXISTS! equ 0 set "BOOT_MODE=未设置"
if !TUN_EXISTS! equ 0 set "BOOT_MODE=未设置"
if !MIXED_EXISTS! equ 0 (
    call :taskEnabled "!TASK_MIXED!"
    if !errorlevel! equ 0 set "BOOT_MODE=Mixed"
)
if !TUN_EXISTS! equ 0 (
    call :taskEnabled "!TASK_TUN!"
    if !errorlevel! equ 0 set "BOOT_MODE=TUN"
)

if "!BOOT_MODE!"=="未注册" (
    call :echoColor 90 "开机自启:   未注册"
) else if "!BOOT_MODE!"=="未设置" (
    call :echoColor 93 "开机自启:   未设置"
) else if "!BOOT_MODE!"=="Mixed" (
    call :echoColor 96 "开机自启:   Mixed 模式"
) else (
    call :echoColor 96 "开机自启:   TUN 模式"
)

REM Determine running mode
call :sbRunning "config-mixed"
if !errorlevel! equ 0 (
    call :echoColor 92 "当前运行:   Mixed 模式"
) else (
    call :sbRunning "config-tun"
    if !errorlevel! equ 0 (
        call :echoColor 92 "当前运行:   TUN 模式"
    ) else (
        call :echoColor 93 "当前运行:   已停止"
    )
)
goto :eof

REM ============================================================================
REM Execute specified action
REM ============================================================================
:runAction
set "ACT=%~1"
set "SUCCESS=1"

if /i "%ACT%"=="kernel" (
    call :updateKernel
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="sub" (
    call :updateSub
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="start-mixed" (
    call :startMode "mixed"
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="start-tun" (
    call :startMode "tun"
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="stop" (
    call :stopSingbox
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="boot-mixed" (
    call :switchBoot "mixed"
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="boot-tun" (
    call :switchBoot "tun"
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="uninstall" (
    call :uninstallTask
    set "SUCCESS=!errorlevel!"
) else (
    call :echoError "未知操作: %ACT%"
    call :echoInfo "用法: kernel / sub / start-mixed / start-tun / stop / boot-mixed / boot-tun / uninstall"
    set "SUCCESS=1"
)

echo.
if !SUCCESS!==0 (
    call :echoColor 92 "========================================"
    call :echoColor 92 "  操作成功"
    call :echoColor 92 "========================================"
) else (
    call :echoColor 91 "========================================"
    call :echoColor 91 "  操作失败"
    call :echoColor 91 "========================================"
)
echo.
pause >nul
goto :eof

REM ============================================================================
REM Main
REM ============================================================================
:main
call :setESC

set "ACTION=%~1"

if not "%ACTION%"=="" (
    call :runAction "%ACTION%"
    exit /b !errorlevel!
)

:menu
cls
call :echoColor 96 "========================================"
call :echoColor 92 "  Sing-Box Windows Cmd"
call :echoColor 96 "========================================"
echo.
call :showStatus
echo.
echo.
call :echoColor 90 "  ── 日常操作 ──"
set "ML=%ESC%[96m  1 - 启动/重启 (Mixed 模式)%ESC%[0m"                                & call echo %%ML%%
set "ML=%ESC%[96m  2 - 启动/重启 (TUN 模式)%ESC%[0m"                                  & call echo %%ML%%
set "ML=%ESC%[96m  3 - 停止 sing-box%ESC%[0m"                                         & call echo %%ML%%
echo.
call :echoColor 90 "  ── 设置 ──"
set "ML=%ESC%[96m  4 - 设置开机自启为 Mixed 模式%ESC%[0m"                                & call echo %%ML%%
set "ML=%ESC%[96m  5 - 设置开机自启为 TUN 模式%ESC%[0m"                                  & call echo %%ML%%
set "ML=%ESC%[96m  6 - 关闭开机自启 (卸载所有计划任务)%ESC%[0m"                          & call echo %%ML%%
echo.
call :echoColor 90 "  ── 维护 ──"
set "ML=%ESC%[96m  7 - 更新内核%ESC%[0m"                                              & call echo %%ML%%
set "ML=%ESC%[96m  8 - 更新订阅%ESC%[0m"                                              & call echo %%ML%%
echo.
set "ML=%ESC%[90m  0 - 刷新状态%ESC%[0m"                                              & call echo %%ML%%
echo.
choice /c 123456780 /n /m "请选择操作: "
set "CHOICE=!errorlevel!"

if "!CHOICE!"=="1" (
    call :runAction "start-mixed"
    goto :menu
) else if "!CHOICE!"=="2" (
    call :runAction "start-tun"
    goto :menu
) else if "!CHOICE!"=="3" (
    call :runAction "stop"
    goto :menu
) else if "!CHOICE!"=="4" (
    call :runAction "boot-mixed"
    goto :menu
) else if "!CHOICE!"=="5" (
    call :runAction "boot-tun"
    goto :menu
) else if "!CHOICE!"=="6" (
    call :runAction "uninstall"
    goto :menu
) else if "!CHOICE!"=="7" (
    call :runAction "kernel"
    goto :menu
) else if "!CHOICE!"=="8" (
    call :runAction "sub"
    goto :menu
) else if "!CHOICE!"=="0" (
    goto :menu
) else (
    call :echoError "无效选项"
    goto :menu
)
