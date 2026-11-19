using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;

namespace MHVirtualCam;

/// <summary>
/// System-wide hotkeys (work even when Chrome/Zoom/Teams is focused) via Win32
/// RegisterHotKey. Supports both built-in playback controls and user-defined
/// per-clip / per-image shortcuts.
/// </summary>
public sealed class GlobalHotkeys : IDisposable
{
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const uint MOD_ALT = 0x0001, MOD_CONTROL = 0x0002, MOD_SHIFT = 0x0004, MOD_NOREPEAT = 0x4000;
    private const int WM_HOTKEY = 0x0312;
    private const int ClipIdBase = 1000;

    public event Action<string>? HotkeyPressed;
    public event Action<int>? ClipHotkeyPressed;

    private IntPtr _hwnd;
    private HwndSource? _source;
    private readonly Dictionary<int, string> _map = new();
    private readonly Dictionary<int, int> _clipMap = new();

    public void Register(IntPtr hwnd)
    {
        _hwnd = hwnd;
        _source = HwndSource.FromHwnd(hwnd);
        _source?.AddHook(WndProc);
        Add(1, "toggle-camera", 0x53);          // Ctrl+Alt+S
        Add(2, "next", 0x4E);                   // Ctrl+Alt+N
        Add(3, "prev", 0x42);                   // Ctrl+Alt+B
        Add(4, "playpause", 0x20);              // Ctrl+Alt+Space
        Add(5, "zoom-in", 0x26);                // Ctrl+Alt+Up
        Add(6, "zoom-out", 0x28);               // Ctrl+Alt+Down
        Add(7, "zoom-reset", 0x30);             // Ctrl+Alt+0
        Add(8, "loop", 0x4C);                   // Ctrl+Alt+L
    }

    public void RegisterClipHotkeys(IEnumerable<(int index, ModifierKeys modifiers, Key key)> bindings)
    {
        if (_hwnd == IntPtr.Zero) return;
        foreach (var id in _clipMap.Keys) UnregisterHotKey(_hwnd, id);
        _clipMap.Clear();

        int nextId = ClipIdBase;
        foreach (var (index, modifiers, key) in bindings)
        {
            if (key == Key.None) continue;
            uint vk = (uint)KeyInterop.VirtualKeyFromKey(key);
            if (vk == 0) continue;
            uint fsMods = MOD_NOREPEAT;
            if ((modifiers & ModifierKeys.Control) != 0) fsMods |= MOD_CONTROL;
            if ((modifiers & ModifierKeys.Alt) != 0) fsMods |= MOD_ALT;
            if ((modifiers & ModifierKeys.Shift) != 0) fsMods |= MOD_SHIFT;

            if (RegisterHotKey(_hwnd, nextId, fsMods, vk))
            {
                _clipMap[nextId] = index;
                nextId++;
            }
        }
    }

    private void Add(int id, string name, uint vk)
    {
        if (RegisterHotKey(_hwnd, id, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, vk))
            _map[id] = name;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY)
        {
            int id = wParam.ToInt32();
            if (_clipMap.TryGetValue(id, out var clipIdx))
            {
                ClipHotkeyPressed?.Invoke(clipIdx);
                handled = true;
            }
            else if (_map.TryGetValue(id, out var name))
            {
                HotkeyPressed?.Invoke(name);
                handled = true;
            }
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        foreach (var id in _clipMap.Keys) UnregisterHotKey(_hwnd, id);
        foreach (var id in _map.Keys) UnregisterHotKey(_hwnd, id);
        _clipMap.Clear();
        _map.Clear();
        _source?.RemoveHook(WndProc);
    }
}
