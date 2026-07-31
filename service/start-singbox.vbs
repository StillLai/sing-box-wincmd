' Silent launcher for sing-box
' Used by scheduled task to avoid visible console window
' Usage: start-singbox.vbs <mixed|tun>

Dim mode
If WScript.Arguments.Count < 1 Then
    WScript.Quit 1
End If
mode = LCase(WScript.Arguments(0))
If mode <> "mixed" And mode <> "tun" Then
    WScript.Quit 1
End If

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve the directory where this VBS script resides
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
configPath = fso.BuildPath(coreDir, "config-" & mode & ".json")

' Wait for internet connectivity (max 10 minutes, check every 3s)
Dim elapsed, execObj
elapsed = 0
Do While elapsed < 600
    Set execObj = WshShell.Exec("cmd /c curl -s --connect-timeout 3 --max-time 3 -o nul http://connect.rom.miui.com/generate_204")
    Do While execObj.Status = 0
        WScript.Sleep 100
    Loop
    If execObj.ExitCode = 0 Then
        Exit Do
    End If
    WScript.Sleep 3000
    elapsed = elapsed + 3
Loop
If elapsed >= 600 Then WScript.Quit 1

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

' Launch sing-box hidden via ShellExecute (inherits admin token reliably)
Set shellApp = CreateObject("Shell.Application")
shellApp.ShellExecute exePath, "run -c """ & configPath & """", coreDir, "open", 0