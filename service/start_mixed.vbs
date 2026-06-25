' Silent launcher for sing-box Mixed mode (noTun)
' Used by scheduled task to avoid visible console window

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve the directory where this VBS script resides
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
coreDir = fso.BuildPath(scriptDir, "core")
exePath = fso.BuildPath(coreDir, "sing-box.exe")
configPath = fso.BuildPath(coreDir, "config_noTun.json")

' Check if sing-box.exe is already running with this config
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name='sing-box.exe'")
For Each objProcess in colProcesses
    If InStr(LCase(objProcess.CommandLine), "config_notun") > 0 Then
        WScript.Quit 0
    End If
Next

' Launch sing-box hidden (0 = hidden window, False = don't wait)
WshShell.CurrentDirectory = coreDir
WshShell.Run """" & exePath & """ run -c """ & configPath & """", 0, False