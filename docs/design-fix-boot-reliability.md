# 设计文档：修复开机自启可靠性

## 问题背景

`sing-box-wincmd` 的开机自启功能（通过 Windows 计划任务 + VBS 静默启动器）存在间歇性失败。有时能成功启动，有时 `sing-box.exe` 未能在开机后运行。

> **术语约定**：本文档中 `serviceDir` = `service\core\`（即 VBS 脚本所在目录的 `core` 子目录，与当前代码中的 `coreDir` 同义）。

## 根因分析

### 🔴 根因 1：子进程生命周期问题（最关键）

`start-singbox.vbs` 第 108 行使用 `WshShell.Run cmdLine, 0, False`（异步模式）启动 `sing-box.exe`。Windows 任务计划程序在 SYSTEM 账户下运行时，使用 **Job Object** 管理进程树。当 VBS 脚本退出后，Job Object 可能被销毁，导致 `sing-box.exe` 子进程被一起杀死。这完全是概率性的——有时子进程在 VBS 退出前已成功脱离，有时没有。

**证据**：日志显示脚本执行了启动命令并正常退出，但 sing-box 进程并未实际运行。

### 🔴 根因 2：无启动后验证

脚本（第 108-109 行）发出 `WshShell.Run` 后立刻退出，从未检查 `sing-box.exe` 是否真的在运行。失败完全静默——日志显示"Launch sent"但进程可能并不存在。

### 🔴 根因 3：无重试机制

一旦启动失败，就彻底失败——要等到下次开机才有机会重试。无任何容错。

### 🟡 根因 4：无启动延迟

计划任务在系统启动时立即执行，此时网络栈、端口绑定（`mixed-port`/`tun`）等可能还没准备好，导致绑定失败或静默退出。

### 🟡 根因 5：日志轮转过于激进

当前代码（`start-singbox.vbs` 第 92-101 行）的轮转逻辑：遍历 `serviceDir` 下所有 `.log` 文件（排除 `*.old.log`），对每个文件执行 `Delete old → Move current to old`。问题在于：

1. **`sing-box.log` 每次开机都被轮转掉** —— 上一次运行的输出在下次开机时被覆盖，丧失了诊断能力
2. **非定向轮转** —— 没有区分 "只轮转启动日志" 和 "轮转运行时日志"，两者的保留策略应该不同
3. **`vbs_boot.log` 也被轮转** —— 但实际上它在启动前就已被打开（第 16 行 append 模式），轮转产生的新文件会丢失之前的启动记录

---

## 设计方案

### 修改文件清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `service/start-singbox.vbs` | 重写 | 核心修复：启动逻辑、验证、重试、日志 |
| `sing-box-manager.cmd` | 小改 | `ensureTasks` 函数：设置任务失败重试策略 |

### 1. `service/start-singbox.vbs` — 重写启动逻辑

#### 1.1 启动延迟 + 网络就绪检测

```vbs
If Not direct Then
    ' Step 1: 等待 30 秒让系统稳定（服务、驱动加载等）
    For i = 1 To 6
        WriteLog "Waiting for system ready... (" & i * 5 & "s / 30s)"
        WScript.Sleep 5000
    Next

    ' Step 2: 网络就绪检测（最多 60 秒，每 5 秒 ping 一次）
    Dim netReady, netStart, netElapsed
    netReady = False
    netStart = Now
    Do While DateDiff("s", netStart, Now) < 60
        Set execObj = WshShell.Exec("cmd /c ping -n 1 -w 3000 223.5.5.5")
        Do While execObj.Status = 0
            WScript.Sleep 100
        Loop
        If execObj.ExitCode = 0 Then
            netReady = True
            Exit Do
        End If
        WScript.Sleep 2000
    Loop

    netElapsed = DateDiff("s", netStart, Now)
    If netReady Then
        WriteLog "Network ready after " & netElapsed & "s"
    Else
        WriteLog "WARN: Network not ready after 60s, proceeding anyway"
    End If
End If
```

**理由**：
- **30 秒固定延迟**：让系统完成服务初始化、驱动加载等，避免在系统尚未稳定时就开始检测
- **60 秒 ping 检测**：保留原有网络就绪检测能力，覆盖慢 Wi-Fi/VPN/DHCP 场景
- **网络超时不阻塞**：60 秒后即使网络未就绪也继续尝试启动 sing-box（sing-box 自身有重连能力）
- `--direct` 模式（手动启动）跳过整个等待

#### 1.2 修复日志轮转

改为定向的两代轮转，只轮转 `vbs_boot.log`，不动 `sing-box.log` 等运行时日志：

```vbs
Sub LogRotate(curPath, oldPath)
    On Error Resume Next
    If fso.FileExists(oldPath) Then fso.DeleteFile oldPath, True
    If fso.FileExists(curPath) Then fso.MoveFile curPath, oldPath
    On Error GoTo 0
End Sub
```

调用位置：在日志初始化之前（脚本最开头），仅对 `vbs_boot.log` 执行轮转：

```vbs
Dim logPath, logOldPath
logPath = scriptDir & "\core\vbs_boot.log"
logOldPath = scriptDir & "\core\vbs_boot.old.log"
LogRotate logPath, logOldPath
```

**关键改动**：
- 使用固定的 `vbs_boot.old.log`，与 `sing-box.old.log` 命名风格一致
- 仅轮转 `vbs_boot.log`，不再遍历整个目录
- 不再动 `sing-box.log` —— 保留上次运行输出供诊断

#### 1.3 可靠启动：cmd /c start /b 包装

当前问题：`WshShell.Run cmdLine, 0, False` 直接启动 sing-box，子进程在 Job Object 中，VBS 退出后可能被杀。

修复方案：使用 `cmd /c start /b` 包装，让 sing-box 进程脱离父级 Job Object。

```vbs
cmdLine = "cmd.exe /c start /b """" """ & exePath & """ run -c """ & cfgPath & """ -D """ & serviceDir & """"
```

**原理**：`start /b` 创建的子进程在独立的进程组中运行，不继承父进程的 Job Object 限制。当 VBS 和包装 cmd 退出后，sing-box 进程继续独立运行。

> **注意**：`start /b` 脱离 Job Object 的行为在 Windows 10/11 各版本中被广泛观察到，但微软官方文档未明确保证。作为兜底，如果首次启动失败，重试机制（见 1.4）会确保最终成功。

#### 1.4 启动后验证 + 重试 + 失败诊断

```vbs
Const MAX_RETRIES = 3
Const WAIT_AFTER_LAUNCH = 8000   ' 启动后等待 8 秒再验证
Const WAIT_BETWEEN_RETRIES = 5000 ' 重试间隔 5 秒

Function IsProcessRunning(processName, configKey)
    IsProcessRunning = False
    On Error Resume Next
    Dim wmi, processes, proc
    Set wmi = GetObject("winmgmts:\\.\root\cimv2")
    Set processes = wmi.ExecQuery("SELECT * FROM Win32_Process WHERE Name = '" & processName & "'")
    For Each proc In processes
        If InStr(1, proc.CommandLine, configKey, vbTextCompare) > 0 Then
            IsProcessRunning = True
            Exit For
        End If
    Next
    On Error GoTo 0
End Function

' 检查 sing-box.log 是否有新内容（区分 "被杀" vs "配置错误"）
Function SingBoxLogModified(logFile, sinceTime)
    SingBoxLogModified = False
    On Error Resume Next
    If fso.FileExists(logFile) Then
        Dim f
        Set f = fso.GetFile(logFile)
        If f.DateLastModified > sinceTime Then
            SingBoxLogModified = True
        End If
    End If
    On Error GoTo 0
End Function

Dim launched, attempt, attemptStart
launched = False

For attempt = 1 To MAX_RETRIES
    attemptStart = Now
    WriteLog "Launch attempt " & attempt & "/" & MAX_RETRIES
    WriteLog "  CMD: " & cmdLine

    WshShell.Run cmdLine, 0, False
    WScript.Sleep WAIT_AFTER_LAUNCH

    If IsProcessRunning("sing-box.exe", "config-" & mode) Then
        WriteLog "SUCCESS: sing-box is running (attempt " & attempt & ")"
        launched = True
        Exit For
    Else
        ' 诊断：sing-box 是否曾经短暂运行过（日志文件有更新 = 进程启动过但退出了）
        If SingBoxLogModified(singBoxLog, attemptStart) Then
            WriteLog "WARN: sing-box started but exited (attempt " & attempt & ") - likely config or port error, check sing-box.log"
        Else
            WriteLog "WARN: sing-box not detected, likely killed by Job Object (attempt " & attempt & ")"
        End If
        If attempt < MAX_RETRIES Then
            WriteLog "Retrying in 5 seconds..."
            WScript.Sleep WAIT_BETWEEN_RETRIES
        End If
    End If
Next

If Not launched Then
    WriteLog "FAILED: sing-box could not be started after " & MAX_RETRIES & " attempts"
    WScript.Quit 1
End If
```

**关键设计决策**：
- 使用 WMI 查询而非 `Tasklist`，因为 WMI 在 SYSTEM 账户下更可靠
- 通过 `CommandLine` 匹配配置文件路径（`config-mixed` / `config-tun`），避免误检测其他实例
- 8 秒验证等待时间：sing-box 启动通常 < 3 秒，8 秒留足余量
- **失败诊断**：检查 `sing-box.log` 的修改时间来区分两种失败场景：
  - **日志有更新** → 进程启动过但因配置错误/端口冲突等原因退出 → 日志提示"check sing-box.log"
  - **日志无更新** → 进程从未真正启动，大概率被 Job Object 杀死 → 日志提示"killed by Job Object"
- 失败时 `WScript.Quit 1`：配合计划任务的失败重试策略（见下文）

#### 1.5 完整的启动日志

每次启动记录：
- 脚本启动时间、模式（mixed/tun）、是否 direct 模式
- 系统等待阶段心跳（每 5 秒）
- 网络就绪检测结果及耗时
- 每次启动尝试的结果及诊断信息
- 最终成功/失败状态及总耗时

### 2. `sing-box-manager.cmd` — 优化任务配置

在 `ensureTasks` 函数中，创建任务后添加失败重试策略：

```cmd
:: 设置失败重试：最多重试 3 次，间隔 60 秒
powershell -NoProfile -Command ^
  "$t = Get-ScheduledTask -TaskName 'sing-box-mixed'; " ^
  "$s = $t.Settings; " ^
  "$s.RestartCount = 3; " ^
  "$s.RestartInterval = 'PT1M'; " ^
  "Set-ScheduledTask -TaskName 'sing-box-mixed' -Settings $s"
```

对 `sing-box-tun` 同样处理。

**效果**：双重重试保障：
- **第一层**：VBS 内部重试 3 次（间隔 5 秒，共约 40 秒）
- **第二层**：计划任务重试 3 次（间隔 60 秒）
- **总保障**：最多 9 次启动机会，跨越约 4 分钟

---

## 验收标准

1. **手动测试**：以管理员身份运行 `sing-box-manager.cmd`，选择菜单 4/5 设置开机自启，然后手动重启电脑，验证 sing-box 在开机后自动运行
2. **日志验证**：重启后检查 `service\core\vbs_boot.log`，应包含：
   - 系统等待心跳日志（30 秒阶段每 5 秒一条）
   - 网络就绪检测结果及耗时
   - 启动尝试记录及诊断信息（成功/失败原因）
   - 最终 `SUCCESS` 状态
3. **重试验证**：人为制造失败条件（如在 sing-box 启动时快速杀死进程），验证重试机制工作，并确认日志区分了"被杀"和"配置错误"
4. **计划任务验证**：`schtasks /query /tn sing-box-mixed /v` 确认任务配置了失败重试（RestartCount=3, RestartInterval=PT1M）
5. **手动启动**：从管理菜单手动启动，不应有 30 秒等待（`--direct` 模式）
6. **日志保留**：重启后 `service\core\sing-box.log` 不应被清空（仅 `vbs_boot.log` 被轮转）

## 不在范围内

- sing-box 本身的配置错误（IPv6 不可达等）
- 网络订阅更新逻辑
- 其他菜单功能
