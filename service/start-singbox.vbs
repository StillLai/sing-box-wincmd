' Silent launcher for sing-box
' Used by scheduled task and manual launch to share the same logic
' Usage: start-singbox.vbs <mixed|tun> [--direct]
'   --direct: skip network wait (for manual launch from menu)

Dim mode, direct, logPath, fso
direct = False

Set fso = CreateObject("Scripting.FileSystemObject")

' Diagnostic log — writes to service\core\vbs_boot.log for troubleshooting
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

' Initialize log path once
logPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "core\vbs_boot.log")
WriteLog "VBS started - Args: " & WScript.Arguments.Count

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

Set WshShell = CreateObject("WScript.Shell")

' Resolve the directory where this VBS script resides
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
configPath = fso.BuildPath(coreDir, "config-" & mode & ".json")

' Validate required files exist
If Not fso.FileExists(exePath) Then
    WriteLog "ERROR: sing-box.exe not found at " & exePath
    WScript.Quit 1
End If
If Not fso.FileExists(configPath) Then
    WriteLog "ERROR: config not found at " & configPath
    WScript.Quit 1
End If
WriteLog "Files OK - exe=" & exePath & " config=" & configPath

' Wait for internet connectivity (max 120s, check every ~6s)
' Uses ping (native, works at boot) instead of curl (may not be in SYSTEM PATH)
' Skipped when launched with --direct (system is already booted)
If Not direct Then
    Dim execObj, startTime
    startTime = Now
    Do While DateDiff("s", startTime, Now) < 120
        Set execObj = WshShell.Exec("cmd /c ping -n 1 -w 3000 223.5.5.5")
        Do While execObj.Status = 0
            WScript.Sleep 100
        Loop
        If execObj.ExitCode = 0 Then
            Exit Do
        End If
        WScript.Sleep 3000
    Loop
    If DateDiff("s", startTime, Now) >= 120 Then
        WriteLog "ERROR: Network wait timed out (120s)"
        WScript.Quit 1
    End If
    WriteLog "Network OK"
End If

' Check if sing-box.exe is already running with this config
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name='sing-box.exe'")
For Each objProcess in colProcesses
    If InStr(LCase(objProcess.CommandLine), "config-" & mode) > 0 Then
        WriteLog "Already running with config-" & mode & ", exiting"
        WScript.Quit 0
    End If
Next

' Rotate log files: rename *.log to *.old.log (overwrite if exists, skip *.old.log)
Dim logFolder, logFile, oldLogPath
Set logFolder = fso.GetFolder(coreDir)
For Each logFile In logFolder.Files
    If LCase(fso.GetExtensionName(logFile.Name)) = "log" And LCase(Right(logFile.Name, 8)) <> ".old.log" Then
        oldLogPath = fso.BuildPath(coreDir, fso.GetBaseName(logFile.Name) & ".old.log")
        If fso.FileExists(oldLogPath) Then fso.DeleteFile oldLogPath, True
        fso.MoveFile logFile.Path, oldLogPath
    End If
Next

' Launch sing-box hidden via WshShell.Run (works under SYSTEM account at boot,
' unlike ShellExecute which requires Explorer to be initialized)
WshShell.CurrentDirectory = coreDir
cmdLine = Chr(34) & exePath & Chr(34) & " run -c " & Chr(34) & configPath & Chr(34)
WriteLog "Launching: " & cmdLine
WshShell.Run cmdLine, 0, False
WriteLog "Launch sent"
