using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace MHBrowser;

public partial class App : Application
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant pvar);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr ptr;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PropertyKey pkey);
        int GetValue(ref PropertyKey key, out PropVariant pv);
        int SetValue(ref PropertyKey key, ref PropVariant pv);
        int Commit();
    }

    public static void ApplyDarkTitleBar(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        int dark = 1;
        if (DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int)) != 0)
            DwmSetWindowAttribute(hwnd, 19, ref dark, sizeof(int));
        int cap = 0x00171717;
        DwmSetWindowAttribute(hwnd, 35, ref cap, sizeof(int));
        int txt = 0x00F2F2F2;
        DwmSetWindowAttribute(hwnd, 36, ref txt, sizeof(int));
    }

    /// <summary>
    /// Assigns an independent Windows Taskbar AppUserModelID to a window so Browser windows
    /// appear under their own dedicated Browser icon on the Taskbar, separate from the Hub.
    /// </summary>
    public static void SetWindowAppUserModelId(Window window, string appId) =>
        SetHwndAppUserModelId(new WindowInteropHelper(window).Handle, appId);

    public static void SetHwndAppUserModelId(IntPtr hwnd, string appId)
    {
        try
        {
            if (hwnd == IntPtr.Zero) return;
            var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            if (SHGetPropertyStoreForWindow(hwnd, ref iid, out var store) != 0 || store is null) return;
            var key = new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
            var pv = new PropVariant { vt = 31, ptr = Marshal.StringToCoTaskMemUni(appId) }; // VT_LPWSTR
            try
            {
                store.SetValue(ref key, ref pv);
                store.Commit();
            }
            finally
            {
                PropVariantClear(ref pv);
                Marshal.ReleaseComObject(store);
            }
        }
        catch { }
    }
}
