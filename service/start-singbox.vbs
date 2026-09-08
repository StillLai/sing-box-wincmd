' Silent launcher for sing-box
' Used by scheduled task and manual launch to share the same logic
' Usage: start-singbox.vbs <mixed|tun> [--direct]
'   --direct: skip network wait (for manual launch from menu)

Dim mode, direct
direct = False

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
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve the directory where this VBS script resides
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
configPath = fso.BuildPath(coreDir, "config-" & mode & ".json")

' Validate required files exist
If Not fso.FileExists(exePath) Then WScript.Quit 1
If Not fso.FileExists(configPath) Then WScript.Quit 1

' Wait for internet connectivity (max 120s, check every ~6s)
' Uses ping (native, works at boot) instead of curl (may not be in SYSTEM PATH)
' Skipped when launched with --direct (system is already booted)
If Not direct Then
    Dim execObj, startTime
    startTime = Timer
    Do While (Timer - startTime) < 120
        Set execObj = WshShell.Exec("cmd /c ping -n 1 -w 3000 223.5.5.5")
        Do While execObj.Status = 0
            WScript.Sleep 100
        Loop
        If execObj.ExitCode = 0 Then
            Exit Do
        End If
        WScript.Sleep 3000
    Loop
    If (Timer - startTime) >= 120 Then WScript.Quit 1
End If

' Check if sing-box.exe is already running with this config
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name='sing-box.exe'")
For Each objProcess in colProcesses
    If InStr(LCase(objProcess.CommandLine), "config-" & mode) > 0 Then
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
WshShell.Run cmdLine, 0, False
