using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using Microsoft.Win32;

namespace Wake.Windows;

internal sealed class WindowsPower : IDisposable
{
    private SafeWaitHandle? _timer;
    private DateTimeOffset? _armed;
    private bool _awake;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeWaitHandle CreateWaitableTimer(IntPtr attributes, bool manualReset, string? name);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWaitableTimer(SafeWaitHandle timer, ref long due, int period, IntPtr callback, IntPtr arg, bool resume);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CancelWaitableTimer(SafeWaitHandle timer);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SetThreadExecutionState(uint flags);

    public void Update(bool keepAwake, DateTimeOffset? nextWake)
    {
        if (keepAwake != _awake)
        {
            if (SetThreadExecutionState(0x80000000u | (keepAwake ? 1u : 0u)) == 0)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            _awake = keepAwake;
        }
        if (_armed == nextWake) return;
        if (_timer is not null) { CancelWaitableTimer(_timer); _timer.Dispose(); _timer = null; }
        _armed = null;
        if (nextWake is null) return;
        _timer = CreateWaitableTimer(IntPtr.Zero, true, null);
        if (_timer.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        // Wake a minute early, or immediately when less than a minute remains.
        long due = (nextWake.Value - TimeSpan.FromMinutes(1) > DateTimeOffset.UtcNow
            ? nextWake.Value - TimeSpan.FromMinutes(1) : DateTimeOffset.UtcNow.AddSeconds(1)).UtcDateTime.ToFileTimeUtc();
        if (!SetWaitableTimer(_timer, ref due, 0, IntPtr.Zero, IntPtr.Zero, true))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        _armed = nextWake;
    }

    public static bool StartsAtLogin()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("WakeNative") is string;
    }
    public static void SetLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
        {
            string executable = Environment.ProcessPath ?? throw new InvalidOperationException("Executable path unavailable.");
            if (!string.Equals(System.IO.Path.GetFileNameWithoutExtension(executable), "Wake", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Enable start at login from the published Wake.exe, not dotnet run.");
            key.SetValue("WakeNative", $"\"{executable}\" --background");
        }
        else key.DeleteValue("WakeNative", false);
    }
    public void Dispose()
    {
        if (_timer is not null) { CancelWaitableTimer(_timer); _timer.Dispose(); }
        SetThreadExecutionState(0x80000000u);
    }
}
