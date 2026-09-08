@echo off
chcp 65001 >nul 2>nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键"以管理员身份运行"！
    pause
    exit /b 1
)

echo [1] 创建计划任务...
schtasks /create /tn "sing-box-mixed" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" mixed" /sc onstart /ru SYSTEM /f >nul
if %errorlevel% neq 0 (
    echo [错误] 创建 sing-box-mixed 失败！
) else (
    echo [成功] sing-box-mixed 已创建
)
schtasks /create /tn "sing-box-tun" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" tun" /sc onstart /ru SYSTEM /f >nul
if %errorlevel% neq 0 (
    echo [错误] 创建 sing-box-tun 失败！
) else (
    echo [成功] sing-box-tun 已创建
)

echo [2] 启用 Mixed 模式开机自启...
schtasks /change /tn "sing-box-mixed" /enable >nul
if %errorlevel% neq 0 (
    echo [错误] 启用失败！
) else (
    echo [成功] sing-box-mixed 已启用
)
schtasks /change /tn "sing-box-tun" /disable >nul 2>nul

echo [3] 验证任务状态...
schtasks /query /tn "sing-box-mixed" /fo list 2>&1 | findstr "Status"
if %errorlevel% neq 0 (
    echo [错误] 无法查询任务状态，任务可能不存在
)
echo.
echo ========================================
echo 完成！请重启电脑测试开机自启
echo 日志路径: service\core\vbs_boot.log
echo ========================================
pause
