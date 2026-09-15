param(
    [string]$Exe,
    [string]$Config,
    [string]$Dir
)

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Launcher {
    // Pack=4: matches Windows SDK STARTUPINFO alignment
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
        // CREATE_NO_WINDOW         (0x08000000): no new console window allocated
        // Process inherits parent's hidden console — sing-box gets valid stdin/stdout.
        uint flags = 0x09000000;
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
    Write-Error "[launch-hidden] Add-Type FAILED: $($_.Exception.Message)"
    exit 1
}

# Build the args string inside PowerShell to avoid cmd.exe quote escaping issues
$cmdArgs = "run -c `"$Config`" -D `"$Dir`""
$result = [Launcher]::Launch($Exe, $cmdArgs, $Dir)
exit $result
