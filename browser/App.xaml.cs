using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace MHBrowser;

public partial class App : Application
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

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
}
