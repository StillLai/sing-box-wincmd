@echo off
chcp 65001 >nul 2>nul

REM Check admin privilege, auto-elevate if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin privilege...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del /f /q "%temp%\getadmin.vbs" >nul 2>&1
    exit /b
)

REM Ensure we run from the script's directory (VBS elevation changes CWD to system32)
cd /d "%~dp0"

setlocal EnableDelayedExpansion

REM ============================================================================
REM Sing-Box Manager for Windows (Scheduled Task Edition)
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
if not defined PROXY_PREFIX set "PROXY_PREFIX=https://gh-proxy.org/"

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

REM VBS launchers
set "VBS_MIXED=%~dp0service\start_mixed.vbs"
set "VBS_TUN=%~dp0service\start_tun.vbs"

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
REM Check if sing-box is running with a specific config
REM   %1 = config keyword (e.g. "config_notun" or "config_tun")
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
REM Update kernel
REM ============================================================================
:updateKernel
set "SINGBOX_EXE=service\core\sing-box.exe"
set "API_URL=https://api.github.com/repos/reF1nd/sing-box-releases/releases"
set "GITHUB_BASE=https://github.com/reF1nd/sing-box-releases/releases/download"
set "TEMP_DIR=service\temp"
set "RESTORE_NEEDED=0"

call :echoInfo "正在检查最新版本..."

if not exist "service\core" mkdir "service\core" >nul 2>nul
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>nul

REM Force TLS 1.2, direct connection for API (via temp .ps1 to avoid cmd special char issues)
set "PS_SCRIPT=%temp%\sb_check_version.ps1"
(
    echo [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    echo try { $r = Invoke-RestMethod -Uri '%API_URL%/latest' -UseBasicParsing -TimeoutSec 15; Write-Output $r.tag_name }
    echo catch { Write-Output 'API_ERROR' }
) > "%PS_SCRIPT%"
for /f "usebackq delims=" %%v in (`powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" 2^>nul`) do (
    set "VERSION=%%v"
)
del /f /q "%PS_SCRIPT%" >nul 2>nul

echo !VERSION! | findstr /b /c:"v" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "获取版本失败，返回值: !VERSION!"
    exit /b 1
)
call :echoSuccess "最新版本: !VERSION!"

if exist "%SINGBOX_EXE%" (
    copy /y "%SINGBOX_EXE%" "%SINGBOX_EXE%.bak" >nul 2>nul
    call :echoInfo "已备份旧内核到 %SINGBOX_EXE%.bak"
    set "RESTORE_NEEDED=1"
)

set "VERSION_NUM=!VERSION:~1!"
set "TEMP_ZIP=%TEMP_DIR%\sing-box-!VERSION_NUM!-windows-amd64v3.zip"

REM Build download URL: prepend PROXY_PREFIX for the actual file download
set "RAW_DOWNLOAD_URL=%GITHUB_BASE%/!VERSION!/sing-box-!VERSION_NUM!-windows-amd64v3.zip"
set "PROXY_DOWNLOAD_URL=%PROXY_PREFIX%%RAW_DOWNLOAD_URL%"

call :echoInfo "正在下载 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --connect-timeout 15 --max-time 300 -o "!TEMP_ZIP!" "!PROXY_DOWNLOAD_URL!" >nul 2>nul

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

set "EXE_NEW=%SINGBOX_EXE%.new"

call :echoInfo "正在解压..."
powershell -c "Expand-Archive -Path '!TEMP_ZIP!' -DestinationPath '%TEMP_DIR%' -Force" >nul 2>nul

if !errorlevel! neq 0 (
    call :echoError "解压失败"
    goto :restoreKernel
)

set "NEW_EXE="
for /r "%TEMP_DIR%" %%f in (*.exe) do (
    echo %%~nxf | findstr /i "sing-box" >nul && (
        set "NEW_EXE=%%f"
    )
)

if not defined NEW_EXE (
    call :echoError "解压后未找到 sing-box.exe"
    goto :restoreKernel
)

if exist "%EXE_NEW%" del /f /q "%EXE_NEW%" >nul 2>nul
copy /y "!NEW_EXE!" "%EXE_NEW%" >nul 2>nul

if !errorlevel! neq 0 (
    call :echoError "保存新内核失败"
    goto :restoreKernel
)

for %%e in ("%EXE_NEW%") do set "ESIZE=%%~ze"
if !ESIZE! lss 1000000 (
    call :echoError "新内核文件异常 (!ESIZE! 字节)"
    goto :restoreKernel
)

REM Check if any sing-box process is running
call :sbRunning "config"
if !errorlevel! equ 0 (
    REM Process running — stop first, replace, then restart
    call :echoInfo "检测到 sing-box 正在运行，正在停止..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
    move /y "%EXE_NEW%" "%SINGBOX_EXE%" >nul 2>nul
    call :echoSuccess "内核已替换 (!ESIZE! 字节)"
    call :echoInfo "正在重新启动 sing-box..."
    call :restartRunningMode
) else (
    REM No process running — replace directly
    move /y "%EXE_NEW%" "%SINGBOX_EXE%" >nul 2>nul
    call :echoSuccess "内核已替换 (!ESIZE! 字节)"
)

del /f /q "%SINGBOX_EXE%.bak" >nul 2>nul
if /i "!TEMP_DIR!"=="service\temp" if exist "!TEMP_DIR!" rd /s /q "!TEMP_DIR!" >nul 2>nul
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
if /i "!TEMP_DIR!"=="service\temp" if exist "!TEMP_DIR!" rd /s /q "!TEMP_DIR!" >nul 2>nul
exit /b 1

REM ============================================================================
REM Restart whichever mode was running (mixed or tun)
REM ============================================================================
:restartRunningMode
call :sbRunning "config_notun"
if !errorlevel! equ 0 (
    wscript.exe "%VBS_MIXED%" >nul 2>nul
    call :echoSuccess "Mixed 模式已重启"
    goto :eof
)
call :sbRunning "config_tun"
if !errorlevel! equ 0 (
    wscript.exe "%VBS_TUN%" >nul 2>nul
    call :echoSuccess "TUN 模式已重启"
    goto :eof
)
call :echoInfo "无运行中的实例"
goto :eof

REM ============================================================================
REM Update subscription
REM ============================================================================
:updateSub
set "CONFIG_DIR=service\core"

set "NO_TUN_FILE=%CONFIG_DIR%\config_noTun.json"
set "TUN_FILE=%CONFIG_DIR%\config_tun.json"

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" >nul 2>nul

REM Backup existing configs before downloading
if exist "%NO_TUN_FILE%" (
    copy /y "%NO_TUN_FILE%" "%NO_TUN_FILE%.bak" >nul 2>nul
    call :echoInfo "已备份 Mixed 配置到 %NO_TUN_FILE%.bak"
)
if exist "%TUN_FILE%" (
    copy /y "%TUN_FILE%" "%TUN_FILE%.bak" >nul 2>nul
    call :echoInfo "已备份 TUN 配置到 %TUN_FILE%.bak"
)

REM Download Mixed config
call :echoInfo "正在下载 Mixed 配置 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --connect-timeout 15 --max-time 300 -o "%NO_TUN_FILE%" "%PROXY_PREFIX%%MIXED_SUB_URL%" >nul 2>nul
call :validateDownload "%NO_TUN_FILE%" "Mixed"
if !errorlevel! neq 0 (
    if exist "%NO_TUN_FILE%.bak" (
        copy /y "%NO_TUN_FILE%.bak" "%NO_TUN_FILE%" >nul 2>nul
        call :echoWarn "Mixed 配置已从备份恢复"
    )
    exit /b 1
)

REM Download Tun config
call :echoInfo "正在下载 Tun 配置 (代理: %PROXY_PREFIX%)..."
curl -f -L --retry 3 --connect-timeout 15 --max-time 300 -o "%TUN_FILE%" "%PROXY_PREFIX%%TUN_SUB_URL%" >nul 2>nul
call :validateDownload "%TUN_FILE%" "Tun"
if !errorlevel! neq 0 (
    if exist "%TUN_FILE%.bak" (
        copy /y "%TUN_FILE%.bak" "%TUN_FILE%" >nul 2>nul
        call :echoWarn "TUN 配置已从备份恢复"
    )
    exit /b 1
)

call :echoSuccess "订阅配置已更新: %NO_TUN_FILE% 和 %TUN_FILE%"

REM Restart running instance to apply new config
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "检测到 sing-box 正在运行，正在重启以应用新配置..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
    call :restartRunningMode
) else (
    call :echoInfo "无运行中的实例，新配置将在下次启动时生效"
)
exit /b 0

REM Validate downloaded file size
:validateDownload
if exist "%~1" (
    for %%f in ("%~1") do set "VSIZE=%%~zf"
    if !VSIZE! lss 1024 (
        call :echoError "%~2 配置文件异常 (!VSIZE! 字节)"
        del /f /q "%~1" >nul 2>nul
        exit /b 1
    )
    call :echoInfo "  %~2 配置文件: !VSIZE! 字节"
    exit /b 0
) else (
    call :echoError "%~2 配置文件下载失败"
    exit /b 1
)

REM ============================================================================
REM Install scheduled tasks (Mixed=auto on logon + TUN=exists but no auto)
REM ============================================================================
:installTask
if not exist "%VBS_MIXED%" (
    call :echoError "未找到 %VBS_MIXED%"
    exit /b 1
)
if not exist "%VBS_TUN%" (
    call :echoError "未找到 %VBS_TUN%"
    exit /b 1
)

REM Stop any running sing-box first
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "正在停止运行中的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

REM Delete old tasks if present
call :taskExists "%TASK_MIXED%" && (
    call :echoInfo "删除旧的 %TASK_MIXED% 任务..."
    schtasks /delete /tn "%TASK_MIXED%" /f >nul 2>nul
)
call :taskExists "%TASK_TUN%" && (
    call :echoInfo "删除旧的 %TASK_TUN% 任务..."
    schtasks /delete /tn "%TASK_TUN%" /f >nul 2>nul
)

REM Get absolute path to VBS scripts
set "VBS_MIXED_ABS=%~dp0service\start_mixed.vbs"
set "VBS_TUN_ABS=%~dp0service\start_tun.vbs"

REM Install Mixed task (runs on every user logon, with highest privilege)
call :echoInfo "创建 %TASK_MIXED% 计划任务 (登录时自动启动, 最高权限)..."
schtasks /create /tn "%TASK_MIXED%" /tr "wscript.exe \"%VBS_MIXED_ABS%\"" /sc onlogon /rl highest /f >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "%TASK_MIXED% 任务创建失败"
    exit /b 1
)
call :echoSuccess "%TASK_MIXED% 任务创建成功"

REM Install TUN task (exists but no auto-trigger — manual start only)
call :echoInfo "创建 %TASK_TUN% 计划任务 (手动启动, 最高权限)..."
schtasks /create /tn "%TASK_TUN%" /tr "wscript.exe \"%VBS_TUN_ABS%\"" /sc onlogon /rl highest /f >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "%TASK_TUN% 任务创建失败"
    exit /b 1
)
schtasks /change /tn "%TASK_TUN%" /disable >nul 2>nul
call :echoSuccess "%TASK_TUN% 任务创建成功 (已禁用自动触发，可通过脚本手动启动)"

REM Start Mixed mode
call :echoInfo "启动 sing-box (Mixed 模式)..."
wscript.exe "%VBS_MIXED%" >nul 2>nul
timeout /t 3 /nobreak >nul 2>nul
call :sbRunning "config_notun"
if !errorlevel! equ 0 (
    call :echoSuccess "sing-box (Mixed 模式) 已启动"
) else (
    call :echoWarn "sing-box 启动可能失败，请手动检查"
)
exit /b 0

REM ============================================================================
REM Start Mixed mode
REM ============================================================================
:startMixed
call :taskExists "%TASK_MIXED%"
if !errorlevel! neq 0 (
    call :echoError "%TASK_MIXED% 任务尚未安装，请先安装"
    exit /b 1
)
call :echoInfo "启动 sing-box (Mixed 模式)..."

REM Stop any running sing-box first
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止当前运行的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

wscript.exe "%VBS_MIXED%" >nul 2>nul
timeout /t 3 /nobreak >nul 2>nul
call :sbRunning "config_notun"
if !errorlevel! equ 0 (
    call :echoSuccess "sing-box (Mixed 模式) 已启动"
) else (
    call :echoError "启动失败"
)
exit /b 0

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
REM Restart Mixed mode
REM ============================================================================
:restartMixed
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止当前运行的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)
call :echoInfo "启动 sing-box (Mixed 模式)..."
wscript.exe "%VBS_MIXED%" >nul 2>nul
timeout /t 3 /nobreak >nul 2>nul
call :sbRunning "config_notun"
if !errorlevel! equ 0 (
    call :echoSuccess "sing-box (Mixed 模式) 已重启"
) else (
    call :echoError "启动失败"
)
exit /b !errorlevel!

REM ============================================================================
REM Switch to TUN mode: stop current, start TUN
REM ============================================================================
:switchToTun
if not exist "service\core\config_tun.json" (
    call :echoError "未找到 config_tun.json，请先更新订阅"
    exit /b 1
)
call :taskExists "%TASK_TUN%"
if !errorlevel! neq 0 (
    call :echoError "%TASK_TUN% 任务尚未安装，请先安装"
    exit /b 1
)

call :echoInfo "切换到 TUN 模式..."

REM Stop any running sing-box
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止当前运行的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

REM Start TUN mode
call :echoInfo "启动 sing-box (TUN 模式)..."
wscript.exe "%VBS_TUN%" >nul 2>nul
timeout /t 3 /nobreak >nul 2>nul
call :sbRunning "config_tun"
if !errorlevel! equ 0 (
    call :echoSuccess "已切换到 TUN 模式"
) else (
    call :echoError "TUN 模式启动失败，尝试恢复 Mixed..."
    wscript.exe "%VBS_MIXED%" >nul 2>nul
)
exit /b !errorlevel!

REM ============================================================================
REM Switch back to Mixed mode: stop TUN, start Mixed
REM ============================================================================
:switchToMixed
call :echoInfo "切换回 Mixed 模式..."

REM Stop any running sing-box
call :sbRunning "config"
if !errorlevel! equ 0 (
    call :echoInfo "停止当前运行的 sing-box..."
    taskkill /f /im sing-box.exe >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
)

call :echoInfo "启动 sing-box (Mixed 模式)..."
wscript.exe "%VBS_MIXED%" >nul 2>nul
timeout /t 3 /nobreak >nul 2>nul
call :sbRunning "config_notun"
if !errorlevel! equ 0 (
    call :echoSuccess "已切换回 Mixed 模式"
) else (
    call :echoError "Mixed 模式启动失败"
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
call :taskExists "%TASK_MIXED%"
set "MIXED_TASK=!errorlevel!"
call :taskExists "%TASK_TUN%"
set "TUN_TASK=!errorlevel!"

call :sbRunning "config_notun"
set "MIXED_RUN=!errorlevel!"
call :sbRunning "config_tun"
set "TUN_RUN=!errorlevel!"

if !MIXED_TASK! equ 0 (
    if !MIXED_RUN! equ 0 (
        call :echoColor 92 "Mixed 模式: 运行中 [任务已注册]"
    ) else (
        call :echoColor 93 "Mixed 模式: 已停止 [任务已注册]"
    )
) else (
    call :echoColor 90 "Mixed 模式: 未注册"
)

if !TUN_TASK! equ 0 (
    if !TUN_RUN! equ 0 (
        call :echoColor 92 "TUN 模式:   运行中 [任务已注册]"
    ) else (
        call :echoColor 93 "TUN 模式:   已停止 [任务已注册]"
    )
) else (
    call :echoColor 90 "TUN 模式:   未注册"
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
) else if /i "%ACT%"=="install" (
    call :installTask
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="start" (
    call :startMixed
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="stop" (
    call :stopSingbox
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="restart" (
    call :restartMixed
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="tun" (
    call :switchToTun
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="mixed" (
    call :switchToMixed
    set "SUCCESS=!errorlevel!"
) else if /i "%ACT%"=="uninstall" (
    call :uninstallTask
    set "SUCCESS=!errorlevel!"
) else (
    call :echoError "未知操作: %ACT%"
    call :echoInfo "用法: kernel / sub / install / start / stop / restart / tun / mixed / uninstall"
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
REM Print banner
REM ============================================================================
:showBanner
call :echoColor 96 "========================================"
call :echoColor 92 "  Sing-Box Manager"
call :echoColor 96 "========================================"
echo.
goto :eof


REM ============================================================================
REM Main
REM ============================================================================
:main
call :setESC

call :showBanner

call :showStatus
echo.

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
set "ML=%ESC%[96m  1 - 启动 (Mixed 模式)%ESC%[0m"                                     & call echo %%ML%%
set "ML=%ESC%[96m  2 - 停止 sing-box%ESC%[0m"                                         & call echo %%ML%%
set "ML=%ESC%[96m  3 - 重启 (Mixed 模式)%ESC%[0m"                                     & call echo %%ML%%
set "ML=%ESC%[96m  4 - 切换到 TUN 模式%ESC%[0m"                                       & call echo %%ML%%
set "ML=%ESC%[96m  5 - 切换回 Mixed 模式%ESC%[0m"                                     & call echo %%ML%%
echo.
call :echoColor 90 "  ── 维护 ──"
set "ML=%ESC%[96m  6 - 更新内核%ESC%[0m"                                              & call echo %%ML%%
set "ML=%ESC%[96m  7 - 更新订阅%ESC%[0m"                                              & call echo %%ML%%
echo.
call :echoColor 90 "  ── 设置 ──"
set "ML=%ESC%[96m  8 - 安装/重装计划任务 (Mixed登录自启 + TUN手动)%ESC%[0m"             & call echo %%ML%%
set "ML=%ESC%[96m  9 - 卸载所有计划任务%ESC%[0m"                                       & call echo %%ML%%
echo.
choice /c 123456789 /n /m "请选择操作: "
set "CHOICE=!errorlevel!"

if "!CHOICE!"=="1" (
    call :runAction "start"
    goto :menu
) else if "!CHOICE!"=="2" (
    call :runAction "stop"
    goto :menu
) else if "!CHOICE!"=="3" (
    call :runAction "restart"
    goto :menu
) else if "!CHOICE!"=="4" (
    call :runAction "tun"
    goto :menu
) else if "!CHOICE!"=="5" (
    call :runAction "mixed"
    goto :menu
) else if "!CHOICE!"=="6" (
    call :runAction "kernel"
    goto :menu
) else if "!CHOICE!"=="7" (
    call :runAction "sub"
    goto :menu
) else if "!CHOICE!"=="8" (
    call :runAction "install"
    goto :menu
) else if "!CHOICE!"=="9" (
    call :runAction "uninstall"
    goto :menu
) else (
    call :echoError "无效选项"
    goto :menu
)