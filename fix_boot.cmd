@echo off
chcp 65001 >nul 2>nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键"以管理员身份运行"！
    pause
    exit /b 1
)

echo [1] 创建计划任务...
schtasks /create /tn "sing-box-mixed" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" mixed" /sc onstart /ru SYSTEM /f >nul 2>nul
schtasks /create /tn "sing-box-tun" /tr "wscript.exe \"%~dp0service\start-singbox.vbs\" tun" /sc onstart /ru SYSTEM /f >nul 2>nul

echo [2] 启用 Mixed 模式开机自启...
schtasks /change /tn "sing-box-mixed" /enable >nul 2>nul
if %errorlevel% neq 0 (
    echo [错误] 启用失败！
) else (
    echo [成功] sing-box-mixed 已启用
)
schtasks /change /tn "sing-box-tun" /disable >nul 2>nul

echo [3] 验证任务状态...
schtasks /query /tn "sing-box-mixed" /fo list 2>&1 | findstr "Status"
echo.
echo ========================================
echo 完成！请重启电脑测试开机自启
echo ========================================
pause
