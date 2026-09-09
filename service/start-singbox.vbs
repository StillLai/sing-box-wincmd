' Silent launcher for sing-box
' Used by scheduled task and manual launch to share the same logic
' Usage: start-singbox.vbs <mixed|tun> [--direct]
'   --direct: skip network wait (for manual launch from menu)

Dim mode, direct, logPath, fso, WshShell, scriptDir, coreDir, exePath, configPath, singBoxLog
direct = False
Set fso = CreateObject("Scripting.FileSystemObject")
Set WshShell = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
singBoxLog = fso.BuildPath(coreDir, "sing-box.log")

' ============================================================================
' LogRotate: Two-generation rotation (current -> old)
' ============================================================================
Sub LogRotate(curPath, oldPath)
    On Error Resume Next
    If fso.FileExists(oldPath) Then fso.DeleteFile oldPath, True
    If fso.FileExists(curPath) Then fso.MoveFile curPath, oldPath
    On Error GoTo 0
End Sub

' ============================================================================
' WriteLog: Append a timestamped line to vbs_boot.log
' ============================================================================
Function WriteLog(msg)
    Dim f
    On Error Resume Next
    Set f = fso.OpenTextFile(logPath, 8, True) ' 8=ForAppending
    If Err.Number = 0 Then
        f.WriteLine Now & " " & msg
        f.Close
    End If
    On Error GoTo 0
End Function

' ============================================================================
' IsProcessRunning: Check if sing-box.exe is running with matching config
' ============================================================================
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

' ============================================================================
' SingBoxLogModified: Check if sing-box.log was modified after a given time
'   (distinguishes "Job Object kill" from "config error")
' ============================================================================
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

' ============================================================================
' Step 1: Rotate vbs_boot.log ONLY (not sing-box.log or other files)
' ============================================================================
Dim logOldPath
logPath = fso.BuildPath(coreDir, "vbs_boot.log")
logOldPath = fso.BuildPath(coreDir, "vbs_boot.old.log")
LogRotate logPath, logOldPath

' ============================================================================
' Step 2: Parse arguments
' ============================================================================
If WScript.Arguments.Count < 1 Then
    WScript.Quit 1
End If
mode = LCase(WScript.Arguments(0))
If mode <> "mixed" And mode <> "tun" Then
    WScript.Quit 1
End If
If WScript.Arguments.Count > 1 Then
    If LCase(WScript.Arguments(1)) = "--direct" Then
        direct = True
    End If
End If
configPath = fso.BuildPath(coreDir, "config-" & mode & ".json")

' ============================================================================
' Step 3: Validate files exist
' ============================================================================
If Not fso.FileExists(exePath) Then
    WriteLog "ERROR: sing-box.exe not found at " & exePath
    WScript.Quit 1
End If
If Not fso.FileExists(configPath) Then
    WriteLog "ERROR: config not found at " & configPath
    WScript.Quit 1
End If

' ============================================================================
' Step 4: Log startup info
' ============================================================================
WriteLog "========== sing-box boot =========="
WriteLog "Start time: " & Now
WriteLog "Mode: " & mode & " | Direct: " & direct
WriteLog "Exe: " & exePath
WriteLog "Config: " & configPath
WriteLog "Core dir: " & coreDir

' ============================================================================
' Step 5: System ready delay (30s) + network readiness check (60s)
'   Skipped in --direct mode (manual launch)
' ============================================================================
If Not direct Then
    ' 30-second system ready delay with heartbeat every 5s
    Dim i
    For i = 1 To 6
        WriteLog "Waiting for system ready... (" & i * 5 & "s / 30s)"
        WScript.Sleep 5000
    Next

    ' Network readiness check: ping 223.5.5.5, up to 60s
    Dim execObj, netReady, netStart, netElapsed
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

' ============================================================================
' Step 6: Check if already running via WMI
' ============================================================================
On Error Resume Next
Dim objWMIService, colProcesses, objProcess
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name='sing-box.exe'")
For Each objProcess In colProcesses
    If InStr(LCase(objProcess.CommandLine), "config-" & mode) > 0 Then
        WriteLog "Already running with config-" & mode & ", exiting"
        WScript.Quit 0
    End If
Next
On Error GoTo 0

' ============================================================================
' Step 7: Launch with retry + verification
' ============================================================================
Const MAX_RETRIES = 3
Const WAIT_AFTER_LAUNCH = 8000
Const WAIT_BETWEEN_RETRIES = 5000

Dim cmdLine
cmdLine = "cmd.exe /c start /b """" """ & exePath & """ run -c """ & configPath & """ -D """ & coreDir & """"

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

WriteLog "========== boot complete =========="
