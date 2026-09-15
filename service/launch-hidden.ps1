param(
    [string]$Exe,
    [string]$CmdArgs,
    [string]$Dir
)

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Launcher {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode, Pack=4)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute;
        public int dwFlags;
        public ushort wShowWindow;
        public ushort cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcess(
        string lpApplicationName, string lpCommandLine,
        IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
        bool bInheritHandles, uint dwCreationFlags,
        IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo, ref PROCESS_INFORMATION lpProcessInformation);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    public static int Launch(string exe, string args, string dir) {
        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = 0x00000001; // STARTF_USESHOWWINDOW
        si.wShowWindow = 0;      // SW_HIDE
        var pi = new PROCESS_INFORMATION();
        // CREATE_BREAKAWAY_FROM_JOB (0x01000000): escape Task Scheduler Job Object
        // CREATE_NEW_CONSOLE     (0x00000010): own console, not inheriting parent's
        uint flags = 0x01000010;
        // Use lpApplicationName for exe path (handles spaces in path).
        // lpCommandLine must still include quoted exe as argv[0].
        bool ok = CreateProcess(exe, "\"" + exe + "\" " + args,
            IntPtr.Zero, IntPtr.Zero, false, flags,
            IntPtr.Zero, dir, ref si, ref pi);
        if (!ok) {
            int err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            Console.Error.WriteLine("[launch-hidden] CreateProcess FAILED: Win32Error " + err);
            return 1;
        }
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return 0;
    }
}
"@
} catch {
    Console.Error.WriteLine("[launch-hidden] Add-Type FAILED: " + $_.Exception.Message)
    exit 1
}

$result = [Launcher]::Launch($Exe, $CmdArgs, $Dir)
exit $result
