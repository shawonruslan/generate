using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace MHVirtualCam;

/// <summary>
/// System-wide hotkeys (work even when Zoom/Teams is focused) via Win32
/// RegisterHotKey. All use Ctrl+Alt so they never collide with meeting apps.
///   Ctrl+Alt+S  Start / Stop virtual camera
///   Ctrl+Alt+N  Next clip / image
///   Ctrl+Alt+B  Previous clip / image
///   Ctrl+Alt+Space  Play / Pause
///   Ctrl+Alt+Up / Down  Zoom in / out
///   Ctrl+Alt+0  Reset zoom
///   Ctrl+Alt+L  Cycle loop mode
/// </summary>
public sealed class GlobalHotkeys : IDisposable
{
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const uint MOD_ALT = 0x0001, MOD_CONTROL = 0x0002, MOD_NOREPEAT = 0x4000;
    private const int WM_HOTKEY = 0x0312;

    public event Action<string>? HotkeyPressed;

    private IntPtr _hwnd;
    private HwndSource? _source;
    private readonly Dictionary<int, string> _map = new();

    public void Register(IntPtr hwnd)
    {
        _hwnd = hwnd;
        _source = HwndSource.FromHwnd(hwnd);
        _source?.AddHook(WndProc);
        Add(1, "toggle-camera", 0x53);          // S
        Add(2, "next", 0x4E);                   // N
        Add(3, "prev", 0x42);                   // B
        Add(4, "playpause", 0x20);              // Space
        Add(5, "zoom-in", 0x26);                // Up
        Add(6, "zoom-out", 0x28);               // Down
        Add(7, "zoom-reset", 0x30);             // 0
        Add(8, "loop", 0x4C);                   // L
    }

    private void Add(int id, string name, uint vk)
    {
        if (RegisterHotKey(_hwnd, id, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, vk))
            _map[id] = name;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && _map.TryGetValue(wParam.ToInt32(), out var name))
        {
            HotkeyPressed?.Invoke(name);
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        foreach (var id in _map.Keys) UnregisterHotKey(_hwnd, id);
        _source?.RemoveHook(WndProc);
    }
}
