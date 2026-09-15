@echo off
chcp 65001 >nul 2>nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键"以管理员身份运行"！
    pause
    exit /b 1
)

echo [1] 检查 WinSW...
set "WINSW_EXE=%~dp0service\sing-box-service.exe"
set "WINSW_XML=%~dp0service\sing-box-service.xml"

if not exist "%WINSW_EXE%" (
    echo [信息] WinSW 不存在，请先运行 sing-box-manager.cmd 选项 4 自动下载
    pause
    exit /b 1
)

echo [2] 检查服务状态...
sc query sing-box >nul 2>nul
if %errorlevel% neq 0 (
    echo [信息] 服务未安装，正在安装...
    if not exist "%WINSW_XML%" (
        echo [错误] WinSW XML 配置不存在，请先运行 sing-box-manager.cmd 选项 4
        pause
        exit /b 1
    )
    "%WINSW_EXE%" install >nul 2>nul
    if %errorlevel% neq 0 (
        echo [错误] 服务安装失败！
        pause
        exit /b 1
    )
    echo [成功] sing-box 服务已安装
) else (
    echo [成功] sing-box 服务已存在
)

echo [3] 启动服务...
"%WINSW_EXE%" start >nul 2>nul
if %errorlevel% neq 0 (
    echo [警告] 服务启动可能失败，正在尝试重启...
    "%WINSW_EXE%" stop >nul 2>nul
    timeout /t 2 /nobreak >nul 2>nul
    "%WINSW_EXE%" start >nul 2>nul
)

echo [4] 验证服务状态...
sc query sing-box | findstr "RUNNING" >nul 2>nul
if %errorlevel% equ 0 (
    echo [成功] sing-box 服务正在运行
) else (
    echo [警告] 服务可能未在运行，请检查日志
)

echo.
echo ========================================
echo 完成！sing-box 作为 Windows 服务运行
echo 服务管理: sing-box-service.exe start/stop/status
echo ========================================
pause
