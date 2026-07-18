' Silent launcher for sing-box TUN mode
' Used by scheduled task to avoid visible console window

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve the directory where this VBS script resides
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
configPath = fso.BuildPath(coreDir, "config-tun.json")

' Wait for internet connectivity (max 10 minutes, check every 5s)
Dim elapsed, http
elapsed = 0
Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
http.SetTimeouts 5000, 5000, 5000, 5000
Do While elapsed < 600
    On Error Resume Next
    http.Open "GET", "http://connect.rom.miui.com/generate_204", False
    http.Send
    If Err.Number = 0 And http.Status = 204 Then
        On Error GoTo 0
        Exit Do
    End If
    On Error GoTo 0
    WScript.Sleep 5000
    elapsed = elapsed + 5
Loop
If elapsed >= 600 Then WScript.Quit 1

' Check if sing-box.exe is already running with this config
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name='sing-box.exe'")
For Each objProcess in colProcesses
    If InStr(LCase(objProcess.CommandLine), "config-tun") > 0 Then
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
