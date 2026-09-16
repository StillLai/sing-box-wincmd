@echo off
chcp 65001 >nul 2>nul
REM Check admin privilege, auto-elevate if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在请求管理员权限...
    if "%*"=="" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b 0
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
    echo 请按任意键退出...
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
    echo 请按任意键退出...
    pause >nul
    exit /b 1
)
if not defined TUN_SUB_URL (
    echo [错误] config.env 中未设置 TUN_SUB_URL，请检查配置。
    echo 请按任意键退出...
    pause >nul
    exit /b 1
)
REM Ensure PROXY_PREFIX ends with / if set
if defined PROXY_PREFIX (
    if not "!PROXY_PREFIX:~-1!"=="/" set "PROXY_PREFIX=!PROXY_PREFIX!/"
)
REM Default STABLE_VERSION to true if not set
if not defined STABLE_VERSION set "STABLE_VERSION=true"
REM sing-box paths
set "SINGBOX_EXE=%~dp0service\core\sing-box.exe"
set "MIXED_CONFIG_ABS=%~dp0service\core\config-mixed.json"
set "TUN_CONFIG_ABS=%~dp0service\core\config-tun.json"
REM WinSW service wrapper paths (dual-service architecture)
set "WINSW_EXE=%~dp0service\sing-box-service.exe"
set "WINSW_XML_MIXED=%~dp0service\sing-box-service-mixed.xml"
set "WINSW_XML_TUN=%~dp0service\sing-box-service-tun.xml"
set "WINSW_API=https://api.github.com/repos/winsw/winsw/releases"
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
REM Check if any sing-box service is running
REM   Checks both sing-box-mixed and sing-box-tun
REM   exit /b 0 if running, 1 otherwise
REM ============================================================================
:sbRunning
set "SB_RUNNING=1"
sc query sing-box-mixed 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "SB_RUNNING=0"
sc query sing-box-tun 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "SB_RUNNING=0"
exit /b !SB_RUNNING!
REM ============================================================================
REM Update XML <startmode> tag for service boot configuration
REM   %1 = mode: "mixed" or "tun"
REM   Sets target mode to automatic, other to manual
REM ============================================================================
:setServiceBootMode
if /i "%~1"=="tun" (
    set "_AUTO_SVC=sing-box-tun"
    set "_MANUAL_SVC=sing-box-mixed"
    set "_AUTO_XML=!WINSW_XML_TUN!"
    set "_MANUAL_XML=!WINSW_XML_MIXED!"
) else (
    set "_AUTO_SVC=sing-box-mixed"
    set "_MANUAL_SVC=sing-box-tun"
    set "_AUTO_XML=!WINSW_XML_MIXED!"
    set "_MANUAL_XML=!WINSW_XML_TUN!"
)
REM Update XML startmode to match SCM
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content -Raw '!_AUTO_XML!') -replace '<startmode>[^<]*</startmode>','<startmode>automatic</startmode>' | Set-Content -LiteralPath '!_AUTO_XML!' -Encoding UTF8" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content -Raw '!_MANUAL_XML!') -replace '<startmode>[^<]*</startmode>','<startmode>manual</startmode>' | Set-Content -LiteralPath '!_MANUAL_XML!' -Encoding UTF8" >nul 2>nul
REM Update SCM start type
sc config !_AUTO_SVC! start= delayed-auto >nul 2>nul
sc config !_MANUAL_SVC! start= demand >nul 2>nul
goto :eof
REM ============================================================================
REM Detect running mode by checking which service is running
REM   Output: sets RUN_MODE to "mixed" or "tun"
REM   Default: "mixed" (when neither service is running)
REM ============================================================================
:detectRunMode
set "RUN_MODE=mixed"
sc query sing-box-tun 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "RUN_MODE=tun"
goto :eof
REM ============================================================================
REM Restart in the configured boot mode
REM   Detects running service and restarts accordingly
REM ============================================================================
:restartBootMode
call :detectRunMode
call :echoInfo "根据当前运行状态，按!RUN_MODE! 模式重启..."
call :startMode "!RUN_MODE!"
exit /b !errorlevel!
REM ============================================================================
REM Update kernel
REM ============================================================================
:updateKernel
set "API_URL=https://api.github.com/repos/reF1nd/sing-box-releases/releases"
set "GITHUB_BASE=https://github.com/reF1nd/sing-box-releases/releases/download"
set "CHANNEL=stable"
if /i "!STABLE_VERSION!"=="false" set "CHANNEL=alpha"
call :echoInfo "正在检查最新版本(!CHANNEL!)..."
if not exist "service\core" mkdir "service\core" >nul 2>nul
REM Query GitHub API for the latest version of the selected channel
REM Stable: latest non-prerelease; Alpha: latest prerelease with "alpha" in tag
set "PS_VER=%temp%\sb_query.ps1"
set "API_QUERY=!API_URL!?per_page=30"
set "WANT_PRE=$false"
if "!CHANNEL!"=="alpha" set "WANT_PRE=$true"
call :writePS1 "%PS_VER%"
for /f "usebackq delims=" %%v in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_VER%" 2^>nul`) do rem
set "PS_EXIT=!errorlevel!"
del /f /q "%PS_VER%" >nul 2>nul
set "VERSION="
if exist "%temp%\sb_ver.txt" set /p VERSION=<"%temp%\sb_ver.txt"
del /f /q "%temp%\sb_ver.txt" >nul 2>nul
if !PS_EXIT! neq 0 call :echoError "GitHub API 请求失败，请检查网络连接或代理设置" & del /f /q "%temp%\sb_asset.txt" >nul 2>nul & exit /b 1
echo !VERSION! | findstr /b /c:"v" >nul 2>nul
if !errorlevel! neq 0 call :echoError "获取版本失败，请检查网络连接或代理设置" & del /f /q "%temp%\sb_asset.txt" >nul 2>nul & exit /b 1
call :echoSuccess "最新版本 !VERSION!"
REM Check if already at latest version
set "CURRENT_VERSION="
if exist "!SINGBOX_EXE!" (
    for /f "tokens=3" %%v in ('"!SINGBOX_EXE!" version 2^>nul') do (
        if not defined CURRENT_VERSION set "CURRENT_VERSION=%%v"
    )
)
set "VERSION_NUM=!VERSION:~1!"
if not defined CURRENT_VERSION goto :updateKernel_fresh
if not "!CURRENT_VERSION!"=="!VERSION_NUM!" goto :updateKernel_newer
call :echoSuccess "当前已是最新版本(!VERSION!)，无需更新"
del /f /q "%temp%\sb_asset.txt" >nul 2>nul
exit /b 0
:updateKernel_newer
call :echoInfo "当前版本: !CURRENT_VERSION!，准备更新.."
goto :updateKernel_continue
:updateKernel_fresh
call :echoInfo "未检测到已安装的核心，将全新安装..."
:updateKernel_continue
if exist "!SINGBOX_EXE!" copy /y "!SINGBOX_EXE!" "!SINGBOX_EXE!.bak" >nul 2>nul
set "TEMP_ZIP=%temp%\sb_update.zip"
REM Build download URL: use asset URL from API, prepend PROXY_PREFIX
set "ASSET_URL="
if exist "%temp%\sb_asset.txt" set /p ASSET_URL=<"%temp%\sb_asset.txt"
del /f /q "%temp%\sb_asset.txt" >nul 2>nul
if not defined ASSET_URL (
    call :echoError "未找到 Windows amd64v3 资产文件"
    goto :restoreKernel
)
set "PROXY_DOWNLOAD_URL=%PROXY_PREFIX%%ASSET_URL%"
if defined PROXY_PREFIX (
    call :echoInfo "正在下载 (代理: !PROXY_PREFIX!)..."
) else (
    call :echoInfo "正在下载 (直连)..."
)
curl -f -L -C - --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 --max-time 300 -o "!TEMP_ZIP!" "!PROXY_DOWNLOAD_URL!" >nul
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
call :sbRunning
if !errorlevel! equ 0 (
    set "RUNNING_MODE=1"
    call :echoInfo "检测到 sing-box 正在运行，正在停止.."
    sc stop sing-box-mixed >nul 2>nul
    sc stop sing-box-tun >nul 2>nul
    set /a "_kw=0"
    :updateKernel_waitstop
    timeout /t 1 /nobreak >nul 2>nul
    set /a "_kw+=1"
    call :sbRunning
    if !errorlevel! equ 0 if !_kw! lss 10 goto :updateKernel_waitstop
)
REM Extract sing-box.exe directly from ZIP to final location
call :echoInfo "正在解压..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead('!TEMP_ZIP!'); $e = $z.Entries | Where-Object { $_.Name -eq 'sing-box.exe' }; if ($e) { $s = $e.Open(); $f = [IO.File]::Create('!SINGBOX_EXE!'); $s.CopyTo($f); $f.Dispose(); $s.Dispose() } else { exit 1 }; $z.Dispose() } catch { exit 1 }" >nul 2>nul
set "EXTRACT_OK=!errorlevel!"
del /f /q "!TEMP_ZIP!" >nul 2>nul
if !EXTRACT_OK! neq 0 (
    call :echoError "解压失败"
    goto :restoreKernel
)
call :echoSuccess "核心已更新"
if not defined RUNNING_MODE goto :updateKernel_norestart
call :echoInfo "正在重新启动 sing-box..."
call :restartBootMode
if !errorlevel! neq 0 call :echoWarn "核心已更新，但重启失败，请手动启动"
:updateKernel_norestart
del /f /q "!SINGBOX_EXE!.bak" >nul 2>nul
exit /b 0
:writePS1
REM Write PS1 with delayed expansion DISABLED —preserves ? and | as literals
REM %API_QUERY% and %WANT_PRE% expand via percent expansion (set on prior lines)
setlocal disabledelayedexpansion
echo $r = Invoke-RestMethod -Uri '%API_QUERY%' -TimeoutSec 30 > "%~1"
echo $v = $r ^| Where-Object { $_.prerelease -eq %WANT_PRE% -and ($_.tag_name -like '*alpha*') -eq %WANT_PRE% } ^| Select-Object -First 1 >> "%~1"
echo if ($v) { $v.tag_name ^| Out-File '%temp%\sb_ver.txt' -Encoding ascii; $v.assets ^| Where-Object { $_.name -match 'windows' -and $_.name -match 'amd64v3' -and $_.name -match '\.zip$' } ^| Select-Object -First 1 -ExpandProperty browser_download_url ^| Out-File '%temp%\sb_asset.txt' -Encoding ascii } >> "%~1"
endlocal
exit /b
:restoreKernel
call :echoWarn "正在从备份恢复.."
if exist "!SINGBOX_EXE!.bak" (
    copy /y "!SINGBOX_EXE!.bak" "!SINGBOX_EXE!" >nul 2>nul
    if !errorlevel! equ 0 (
        call :echoInfo "已恢复旧核心"
    ) else (
        call :echoError "恢复旧核心失败"
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
    call :echoWarn "TUN 网络就绪检测超时(30s)"
    goto :eof
)
timeout /t 3 /nobreak >nul 2>nul
goto :waitTunLoop
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
REM Download to temp files first (atomic: all-or-nothing)
if defined PROXY_PREFIX (
    call :echoInfo "正在下载 Mixed 配置 (代理: !PROXY_PREFIX!)..."
) else (
    call :echoInfo "正在下载 Mixed 配置 (直连)..."
)
curl -f -L --retry 3 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 60 -o "%MIXED_FILE%.tmp" "%PROXY_PREFIX%%MIXED_SUB_URL%" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "Mixed 配置下载失败"
    goto :subRestoreAndExit
)
if defined PROXY_PREFIX (
    call :echoInfo "正在下载 Tun 配置 (代理: !PROXY_PREFIX!)..."
) else (
    call :echoInfo "正在下载 Tun 配置 (直连)..."
)
curl -f -L --retry 3 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 60 -o "%TUN_FILE%.tmp" "%PROXY_PREFIX%%TUN_SUB_URL%" >nul 2>nul
if !errorlevel! neq 0 (
    call :echoError "Tun 配置下载失败"
    goto :subRestoreAndExit
)
REM All downloads succeeded — atomically replace configs
move /y "%MIXED_FILE%.tmp" "%MIXED_FILE%" >nul 2>nul
move /y "%TUN_FILE%.tmp" "%TUN_FILE%" >nul 2>nul
if not exist "%MIXED_FILE%" goto :subRestoreAndExit
if not exist "%TUN_FILE%" goto :subRestoreAndExit
del /f /q "%MIXED_FILE%.bak" "%TUN_FILE%.bak" >nul 2>nul
call :echoSuccess "订阅配置已更新"
REM Restart running instance to apply new config
REM Detect mode BEFORE killing so we know what to restart
call :sbRunning
if !errorlevel! neq 0 goto :updateSub_notrunning
call :echoInfo "检测到 sing-box 正在运行，正在重启以应用新配置.."
call :restartBootMode
if !errorlevel! neq 0 call :echoWarn "订阅已更新，但重启失败，请手动启动"
goto :updateSub_done
:updateSub_notrunning
call :echoInfo "无运行中的实例，新配置将在下次启动时生效"
:updateSub_done
exit /b 0
:subRestoreAndExit
del /f /q "%MIXED_FILE%.tmp" "%TUN_FILE%.tmp" >nul 2>nul
if exist "%MIXED_FILE%.bak" copy /y "%MIXED_FILE%.bak" "%MIXED_FILE%" >nul 2>nul
if exist "%TUN_FILE%.bak" copy /y "%TUN_FILE%.bak" "%TUN_FILE%" >nul 2>nul
del /f /q "%MIXED_FILE%.bak" "%TUN_FILE%.bak" >nul 2>nul
exit /b 1
REM ============================================================================
REM Download WinSW from GitHub (v3 alpha, WinSW-x64.exe)
REM ============================================================================
:downloadWinsw
if exist "!WINSW_EXE!" goto :downloadWinsw_exists
call :echoInfo "下载 WinSW 服务管理器.."
set "PS_WINSW=%temp%\sb_winsw.ps1"
powershell -NoProfile -NoLogo -Command "$r=Invoke-RestMethod '!WINSW_API!'; $v3=$r|Where-Object{$_.tag_name -like 'v3*'}|Select-Object -First 1; $v3.assets|Where-Object{$_.name -eq 'WinSW-x64.exe'}|Select-Object -ExpandProperty browser_download_url" > "!PS_WINSW!" 2>nul
set "WINSW_URL="
for /f "delims=" %%u in ('type "!PS_WINSW!"') do set "WINSW_URL=%%u"
del /f /q "!PS_WINSW!" >nul 2>nul
if not defined WINSW_URL call :echoError "无法获取 WinSW 下载地址" & exit /b 1
set "DL=!WINSW_URL!"
if defined PROXY_PREFIX set "DL=!PROXY_PREFIX!!WINSW_URL!"
call :echoInfo "下载: !DL!"
curl -f -L -o "!WINSW_EXE!" "!DL!" --retry 3 --connect-timeout 30 -#
if !errorlevel! neq 0 call :echoError "WinSW 下载失败" & del /f /q "!WINSW_EXE!" >nul 2>nul & exit /b 1
call :echoSuccess "WinSW 下载完成"
:downloadWinsw_exists
exit /b 0
REM ============================================================================
REM Install both WinSW services (mixed + tun)
REM ============================================================================
:installService
call :downloadWinsw
if !errorlevel! neq 0 exit /b 1
call :echoInfo "安装 sing-box Mixed 服务..."
"!WINSW_EXE!" install "!WINSW_XML_MIXED!" >nul 2>nul
if !errorlevel! neq 0 call :echoError "Mixed 服务安装失败" & exit /b 1
call :echoInfo "安装 sing-box TUN 服务..."
"!WINSW_EXE!" install "!WINSW_XML_TUN!" >nul 2>nul
if !errorlevel! neq 0 call :echoError "TUN 服务安装失败" & exit /b 1
REM Set default boot mode: Mixed=auto, TUN=manual
sc config sing-box-mixed start= delayed-auto >nul 2>nul
sc config sing-box-tun start= demand >nul 2>nul
call :echoSuccess "sing-box 服务已安装 (mixed + tun)"
exit /b 0
REM ============================================================================
REM Ensure both services are registered
REM ============================================================================
:ensureTasks
if not exist "!SINGBOX_EXE!" call :echoError "未找到 sing-box.exe，请先更新核心" & exit /b 1
sc query sing-box-mixed >nul 2>nul
if !errorlevel! neq 0 call :installService & exit /b !errorlevel!
sc query sing-box-tun >nul 2>nul
if !errorlevel! neq 0 call :installService & exit /b !errorlevel!
exit /b 0
REM ============================================================================
REM Switch boot mode
REM   %1 = "mixed" or "tun"
REM   Sets target mode XML to automatic, other to manual, then starts target
REM ============================================================================
:switchBoot
if /i "%~1"=="tun" (
    if not exist "service\core\config-tun.json" goto :switchBoot_notun
) else (
    if not exist "service\core\config-mixed.json" goto :switchBoot_nomixed
)
call :ensureTasks
if !errorlevel! neq 0 exit /b 1
call :setServiceBootMode %~1
call :startMode "%~1"
if !errorlevel! equ 0 exit /b 0
REM TUN failed — fall back to Mixed
if /i not "%~1"=="tun" exit /b 1
call :echoInfo "TUN 启动失败，回退到 Mixed 模式..."
call :setServiceBootMode mixed
call :startMode "mixed"
exit /b !errorlevel!
:switchBoot_notun
call :echoError "未找到 config-tun.json，请先更新订阅"
exit /b 1
:switchBoot_nomixed
call :echoError "未找到 config-mixed.json，请先更新订阅"
exit /b 1
REM ============================================================================
REM Stop all sing-box processes (both services)
REM ============================================================================
:stopSingbox
call :sbRunning
if !errorlevel! neq 0 goto :stopSingbox_notrunning
call :echoInfo "停止 sing-box..."
sc stop sing-box-mixed >nul 2>nul
sc stop sing-box-tun >nul 2>nul
set /a "_sw=0"
:stopSingbox_wait
timeout /t 1 /nobreak >nul 2>nul
set /a "_sw+=1"
call :sbRunning
if !errorlevel! equ 0 if !_sw! lss 10 goto :stopSingbox_wait
call :echoSuccess "sing-box 已停止"
exit /b 0
:stopSingbox_notrunning
call :echoWarn "sing-box 未在运行"
exit /b 0
REM ============================================================================
REM Start or restart sing-box in specified mode
REM   %1 = "mixed" or "tun"
REM   Stops the other service, starts the target service
REM ============================================================================
:startMode
if /i "%~1"=="tun" (
    if not exist "service\core\config-tun.json" goto :startMode_notun
    set "TARGET_SVC=sing-box-tun"
    set "OTHER_SVC=sing-box-mixed"
    set "TARGET_XML=!WINSW_XML_TUN!"
    set "OTHER_XML=!WINSW_XML_MIXED!"
) else (
    if not exist "service\core\config-mixed.json" goto :startMode_nomixed
    set "TARGET_SVC=sing-box-mixed"
    set "OTHER_SVC=sing-box-tun"
    set "TARGET_XML=!WINSW_XML_MIXED!"
    set "OTHER_XML=!WINSW_XML_TUN!"
)
call :ensureTasks
if !errorlevel! neq 0 exit /b 1
REM Stop the other service first
sc query !OTHER_SVC! 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 (
    call :echoInfo "停止 !OTHER_SVC!..."
    sc stop !OTHER_SVC! >nul 2>nul
)
REM Start target service
call :echoInfo "启动 sing-box (%~1 模式)..."
sc start !TARGET_SVC! >nul 2>nul
timeout /t 5 /nobreak >nul 2>nul
REM Check if running
sc query !TARGET_SVC! 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! neq 0 goto :startMode_fail
if /i "%~1"=="tun" call :waitTunReady
call :echoSuccess "sing-box (%~1 模式) 已启动"
exit /b 0
:startMode_fail
call :echoError "启动失败"
exit /b 1
:startMode_notun
call :echoError "未找到 config-tun.json，请先更新订阅"
exit /b 1
:startMode_nomixed
call :echoError "未找到 config-mixed.json，请先更新订阅"
exit /b 1
REM ============================================================================
REM Uninstall WinSW services (and clean up legacy scheduled tasks)
REM ============================================================================
:uninstallTask
set "HAD_ERROR=0"
sc query sing-box-mixed >nul 2>nul
if !errorlevel! equ 0 (
    sc stop sing-box-mixed >nul 2>nul
    "!WINSW_EXE!" uninstall "!WINSW_XML_MIXED!" >nul 2>nul
    if !errorlevel! neq 0 set "HAD_ERROR=1"
)
sc query sing-box-tun >nul 2>nul
if !errorlevel! equ 0 (
    sc stop sing-box-tun >nul 2>nul
    "!WINSW_EXE!" uninstall "!WINSW_XML_TUN!" >nul 2>nul
    if !errorlevel! neq 0 set "HAD_ERROR=1"
)
if !HAD_ERROR! equ 1 call :echoError "部分服务卸载失败"
if !HAD_ERROR! equ 0 call :echoSuccess "sing-box 服务已卸载"
goto :uninstallTask_cleanup
:uninstallTask_cleanup
call :taskExists "sing-box-mixed" && schtasks /delete /tn "sing-box-mixed" /f >nul 2>nul
call :taskExists "sing-box-tun" && schtasks /delete /tn "sing-box-tun" /f >nul 2>nul
exit /b !HAD_ERROR!
REM ============================================================================
:showStatus
REM Determine sing-box version
set "SB_VERSION=未安装"
if exist "!SINGBOX_EXE!" (
    for /f "tokens=3" %%v in ('"!SINGBOX_EXE!" version 2^>nul') do (
        if "!SB_VERSION!"=="未安装" set "SB_VERSION=%%v"
    )
    if "!SB_VERSION!"=="" set "SB_VERSION=未知"
)
call :echoColor 96 "sing-box:   !SB_VERSION!"
REM Determine running state
set "RUNNING=已停止"
sc query sing-box-mixed 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "RUNNING=Mixed 模式运行中"
sc query sing-box-tun 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "RUNNING=TUN 模式运行中"
call :echoColor 96 "运行状态:   !RUNNING!"
REM Determine boot mode from SCM startup type
set "BOOT_MODE=未注册"
sc qc sing-box-mixed 2>nul | findstr /i "AUTO_START" >nul 2>nul
if !errorlevel! equ 0 set "BOOT_MODE=Mixed"
sc qc sing-box-tun 2>nul | findstr /i "AUTO_START" >nul 2>nul
if !errorlevel! equ 0 set "BOOT_MODE=TUN"
if "!BOOT_MODE!"=="未注册" ( call :echoColor 90 "开机自启:   未注册" )
if "!BOOT_MODE!"=="Mixed" ( call :echoColor 96 "开机自启:   Mixed 模式" )
if "!BOOT_MODE!"=="TUN" ( call :echoColor 96 "开机自启:   TUN 模式" )
goto :eof
REM ============================================================================
REM Execute specified action
REM ============================================================================
:runAction
set "ACT=%~1"
set "SUCCESS=1"
if /i "%ACT%"=="kernel" goto :do_kernel
if /i "%ACT%"=="sub" goto :do_sub
if /i "%ACT%"=="winsw" goto :do_winsw
if /i "%ACT%"=="restart-mixed" goto :do_restart_mixed
if /i "%ACT%"=="restart-tun" goto :do_restart_tun
if /i "%ACT%"=="start" goto :do_restart_mixed
if /i "%ACT%"=="start-mixed" goto :do_restart_mixed
if /i "%ACT%"=="start-tun" goto :do_restart_tun
if /i "%ACT%"=="stop" goto :do_stop
if /i "%ACT%"=="boot-mixed" goto :do_boot-mixed
if /i "%ACT%"=="boot-tun" goto :do_boot-tun
if /i "%ACT%"=="uninstall" goto :do_uninstall
call :echoError "未知操作: %ACT%"
call :echoInfo "用法: restart-mixed / restart-tun / start / start-mixed / start-tun / stop / boot-mixed / boot-tun / uninstall / kernel / sub / winsw"
set "SUCCESS=1"
goto :runAction_done
:do_kernel
call :updateKernel
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_sub
call :updateSub
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_winsw
call :echoInfo "检查 WinSW 更新..."
set "PS_WINSW=%temp%\sb_winsw_ver.ps1"
powershell -NoProfile -NoLogo -Command "$r=Invoke-RestMethod '!WINSW_API!'; $v3=$r|Where-Object{$_.tag_name -like 'v3*'}|Select-Object -First 1; Write-Output $v3.tag_name" > "!PS_WINSW!" 2>nul
set "WINSW_VER="
for /f "delims=" %%v in ('type "!PS_WINSW!"') do if not defined WINSW_VER set "WINSW_VER=%%v"
del /f /q "!PS_WINSW!" >nul 2>nul
if not defined WINSW_VER call :echoError "获取 WinSW 版本失败" & set "SUCCESS=1" & goto :runAction_done
call :echoSuccess "最新版本: !WINSW_VER!"
REM Download new WinSW to temp file first (safe: preserves old binary)
call :echoInfo "下载 WinSW..."
set "WINSW_EXE_BAK=!WINSW_EXE!.bak"
if exist "!WINSW_EXE!" copy /y "!WINSW_EXE!" "!WINSW_EXE_BAK!" >nul 2>nul
del /f /q "!WINSW_EXE!" >nul 2>nul
call :downloadWinsw
if !errorlevel! neq 0 (
    call :echoError "WinSW 下载失败，正在恢复旧版本..."
    if exist "!WINSW_EXE_BAK!" copy /y "!WINSW_EXE_BAK!" "!WINSW_EXE!" >nul 2>nul
    del /f /q "!WINSW_EXE_BAK!" >nul 2>nul
    set "SUCCESS=1"
    goto :runAction_done
)
del /f /q "!WINSW_EXE_BAK!" >nul 2>nul
call :echoSuccess "WinSW 更新完成"
REM Capture running mode before stopping
set "_WAS_RUNNING="
sc query sing-box-mixed 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "_WAS_RUNNING=mixed"
sc query sing-box-tun 2>nul | findstr /i "RUNNING" >nul 2>nul
if !errorlevel! equ 0 set "_WAS_RUNNING=tun"
REM Capture current boot mode before reinstall
set "_WINSW_BOOT_MODE="
sc qc sing-box-mixed 2>nul | findstr /i "AUTO_START\|DELAYED" >nul 2>nul
if !errorlevel! equ 0 set "_WINSW_BOOT_MODE=mixed"
sc qc sing-box-tun 2>nul | findstr /i "AUTO_START\|DELAYED" >nul 2>nul
if !errorlevel! equ 0 set "_WINSW_BOOT_MODE=tun"
REM Stop services before reinstall
call :echoInfo "停止服务..."
sc stop sing-box-mixed >nul 2>nul
sc stop sing-box-tun >nul 2>nul
timeout /t 2 /nobreak >nul 2>nul
REM Reinstall services with new WinSW
call :echoInfo "重新注册服务..."
"!WINSW_EXE!" uninstall "!WINSW_XML_MIXED!" >nul 2>nul
"!WINSW_EXE!" uninstall "!WINSW_XML_TUN!" >nul 2>nul
"!WINSW_EXE!" install "!WINSW_XML_MIXED!" >nul 2>nul
if !errorlevel! neq 0 call :echoError "Mixed 服务注册失败" & set "SUCCESS=1" & goto :runAction_done
"!WINSW_EXE!" install "!WINSW_XML_TUN!" >nul 2>nul
if !errorlevel! neq 0 call :echoError "TUN 服务注册失败" & set "SUCCESS=1" & goto :runAction_done
REM Restore boot mode
if defined _WINSW_BOOT_MODE (
    call :setServiceBootMode !_WINSW_BOOT_MODE!
) else (
    call :setServiceBootMode mixed
)
call :echoSuccess "服务已重新注册"
REM Restart the service that was running before
if defined _WAS_RUNNING (
    call :echoInfo "正在恢复 !_WAS_RUNNING! 模式..."
    call :startMode "!_WAS_RUNNING!"
)
set "SUCCESS=0"
goto :runAction_done
:do_restart_mixed
call :startMode "mixed"
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_restart_tun
call :startMode "tun"
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_stop
call :stopSingbox
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_boot-mixed
call :switchBoot "mixed"
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_boot-tun
call :switchBoot "tun"
set "SUCCESS=!errorlevel!"
goto :runAction_done
:do_uninstall
call :uninstallTask
set "SUCCESS=!errorlevel!"
goto :runAction_done
:runAction_done
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
echo 请按任意键返回菜单...
pause >nul
exit /b !SUCCESS!
REM ============================================================================
REM Main
REM ============================================================================
:main
call :setESC
set "ACTION=%~1"
if not "%ACTION%"=="" goto :cliAction
goto :menu
:cliAction
call :runAction "%ACTION%"
exit /b !errorlevel!
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
set "ML=%ESC%[91m  3 - 停止 sing-box%ESC%[0m"                                              & call echo %%ML%%
echo.
call :echoColor 90 "  ── 设置 ──"
set "ML=%ESC%[96m  4 - 设置开机自启为 Mixed 模式%ESC%[0m"                                & call echo %%ML%%
set "ML=%ESC%[96m  5 - 设置开机自启为 TUN 模式%ESC%[0m"                                  & call echo %%ML%%
set "ML=%ESC%[91m  6 - 关闭开机自启(卸载 WinSW 服务)%ESC%[0m"                          & call echo %%ML%%
echo.
call :echoColor 90 "  ── 维护 ──"
set "ML=%ESC%[96m  7 - 更新核心%ESC%[0m"                                              & call echo %%ML%%
set "ML=%ESC%[96m  8 - 更新订阅%ESC%[0m"                                              & call echo %%ML%%
set "ML=%ESC%[96m  9 - 更新 WinSW%ESC%[0m"                                            & call echo %%ML%%
echo.
set "ML=%ESC%[90m  0 - 刷新状态%ESC%[0m"                                              & call echo %%ML%%
echo.
choice /c 1234567890 /n /m "请选择操作: "
set "CHOICE=!errorlevel!"
if "!CHOICE!"=="1" goto :menu_restart-mixed
if "!CHOICE!"=="2" goto :menu_restart-tun
if "!CHOICE!"=="3" goto :menu_stop
if "!CHOICE!"=="4" goto :menu_boot-mixed
if "!CHOICE!"=="5" goto :menu_boot-tun
if "!CHOICE!"=="6" goto :menu_uninstall
if "!CHOICE!"=="7" goto :menu_kernel
if "!CHOICE!"=="8" goto :menu_sub
if "!CHOICE!"=="9" goto :menu_winsw
if "!CHOICE!"=="10" goto :menu
call :echoError "无效选项"
goto :menu
:menu_restart-mixed
call :runAction "restart-mixed"
goto :menu
:menu_restart-tun
call :runAction "restart-tun"
goto :menu
:menu_stop
call :runAction "stop"
goto :menu
:menu_boot-mixed
call :runAction "boot-mixed"
goto :menu
:menu_boot-tun
call :runAction "boot-tun"
goto :menu
:menu_uninstall
call :runAction "uninstall"
goto :menu
:menu_kernel
call :runAction "kernel"
goto :menu
:menu_sub
call :runAction "sub"
goto :menu
:menu_winsw
call :runAction "winsw"
goto :menu
