using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Threading;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace MHBrowser;

public partial class ProfileToolsDockWindow : Window
{
    private readonly RealChromiumSession _session;
    private readonly Action _saveStore;
    private bool _expanded;
    private bool _loadingGeo;
    private bool _cookieRobotRunning;
    private DispatcherTimer? _followTimer;

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    public ProfileToolsDockWindow(RealChromiumSession session, Action saveStore)
    {
        InitializeComponent();
        _session = session;
        _saveStore = saveStore;

        TxtProfileHeader.Text = $"MH Tools - {session.Profile.Name}";
        TxtPillProfile.Text = session.Profile.Name;
        CollapsedPill.ToolTip = $"Profile: {session.Profile.Name} — Click to open MH Tools";
        TxtCdpEndpoint.Text = $"http://127.0.0.1:{session.CdpPort}";
        TxtSessionIp.Text = string.IsNullOrWhiteSpace(session.Connection.ExitIp)
            ? $"Proxy: {session.Profile.ProxySummary}"
            : $"IP: {session.Connection.ExitIp} ({session.Connection.Location})";
        TxtSessionTz.Text = string.IsNullOrWhiteSpace(session.Connection.Timezone)
            ? "TZ: System"
            : $"TZ: {session.Connection.Timezone}";

        _loadingGeo = true;
        CbGeoPreset.ItemsSource = GeoPresets.All.Select(g => g.Name).ToList();
        CbGeoPreset.SelectedIndex = session.Profile.AutoGeolocation ? 0 : GeoPresets.All.Length - 1;
        _loadingGeo = false;

        var (hasGeo, lat, lon, acc) = session.GetResolvedGeo();
        if (hasGeo)
        {
            TxtLat.Text = lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLon.Text = lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtGeoStatus.Text = $"Active GPS: {lat:F4}, {lon:F4} (±{acc:F0}m)";
        }

        Loaded += (_, _) =>
        {
            SnapToRightEdge();
            StartWindowFollowLoop();
        };
        Closed += (_, _) => _followTimer?.Stop();
    }

    private void StartWindowFollowLoop()
    {
        _followTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(220) };
        _followTimer.Tick += (_, _) =>
        {
            if (!_session.IsRunning)
            {
                _followTimer.Stop();
                Close();
                return;
            }
            var chromeHwnd = _session.MainHwnd;
            if (chromeHwnd == IntPtr.Zero || !IsWindow(chromeHwnd))
                return;

            // Hide immediately when Chromium is minimized or not in the foreground (so it NEVER floats over desktop/other apps)
            if (IsIconic(chromeHwnd))
            {
                if (Visibility == Visibility.Visible) Hide();
                return;
            }

            IntPtr fg = GetForegroundWindow();
            IntPtr myHwnd = new WindowInteropHelper(this).Handle;
            bool isChromeOrDockFocused = fg == chromeHwnd || fg == myHwnd;
            if (!isChromeOrDockFocused && fg != IntPtr.Zero && _session.ChromeProcessId > 0)
            {
                GetWindowThreadProcessId(fg, out uint fgPid);
                if (fgPid == (uint)_session.ChromeProcessId) isChromeOrDockFocused = true;
            }

            if (!isChromeOrDockFocused)
            {
                if (Visibility == Visibility.Visible) Hide();
                return;
            }

            if (Visibility != Visibility.Visible) Show();
            SnapToRightEdge();
        };
        _followTimer.Start();
    }

    private void SnapToRightEdge()
    {
        var wa = SystemParameters.WorkArea;
        double rightEdge = wa.Right;
        double topEdge = wa.Top;
        double availH = wa.Height;

        var chromeHwnd = _session.MainHwnd;
        if (chromeHwnd != IntPtr.Zero && IsWindow(chromeHwnd) && GetWindowRect(chromeHwnd, out var rc) && rc.Right > rc.Left)
        {
            // Convert physical pixels to WPF DIPs
            var src = PresentationSource.FromVisual(this);
            double scaleX = src?.CompositionTarget?.TransformFromDevice.M11 ?? 1.0;
            double scaleY = src?.CompositionTarget?.TransformFromDevice.M22 ?? 1.0;
            rightEdge = Math.Min(wa.Right, rc.Right * scaleX);
            topEdge = Math.Max(wa.Top, rc.Top * scaleY);
            availH = Math.Max(200, (rc.Bottom - rc.Top) * scaleY);
        }

        if (_expanded)
        {
            Width = 315;
            Height = Math.Min(690, availH - 40);
            Left = rightEdge - Width;
            Top = topEdge + (availH - Height) / 2;
        }
        else
        {
            Width = 34;
            Height = 118;
            Left = rightEdge - Width;
            Top = topEdge + (availH - Height) / 2;
        }
    }

    private void CollapsedPill_Click(object sender, MouseButtonEventArgs e)
    {
        _expanded = true;
        CollapsedPill.Visibility = Visibility.Collapsed;
        ExpandedPanel.Visibility = Visibility.Visible;
        SnapToRightEdge();
    }

    private void BtnCollapse_Click(object sender, RoutedEventArgs e)
    {
        _expanded = false;
        ExpandedPanel.Visibility = Visibility.Collapsed;
        CollapsedPill.Visibility = Visibility.Visible;
        SnapToRightEdge();
    }

    private void Header_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            try { DragMove(); } catch { }
    }

    private void BtnOpenInspector_Click(object sender, RoutedEventArgs e)
    {
        _session.OpenInspector();
        DockStatus.Text = "Reqable / Fiddler Inspector opened.";
    }

    private async void BtnCamTest_Click(object sender, RoutedEventArgs e)
    {
        await _session.NavigateActiveTabAsync("https://webcamtoy.com/app/");
        DockStatus.Text = "Opened webcamtoy.com";
    }

    private async void BtnCheckIp_Click(object sender, RoutedEventArgs e)
    {
        await _session.NavigateActiveTabAsync("https://whoer.net");
        DockStatus.Text = "Opened whoer.net";
    }

    private async void BtnTestGeo_Click(object sender, RoutedEventArgs e)
    {
        await _session.NavigateActiveTabAsync("https://browserleaks.com/geo");
        DockStatus.Text = "Opened browserleaks.com/geo";
    }

    private async void BtnCookieRobot_Click(object sender, RoutedEventArgs e)
    {
        if (_cookieRobotRunning)
        {
            _cookieRobotRunning = false;
            BtnCookieRobot.Content = "Cookie Robot";
            DockStatus.Text = "Cookie Robot stopped.";
            return;
        }
        _cookieRobotRunning = true;
        BtnCookieRobot.Content = "Stop Robot";
        string[] sites = { "https://www.wikipedia.org", "https://www.bbc.com", "https://www.github.com", "https://www.reddit.com", "https://www.nytimes.com" };
        try
        {
            foreach (var site in sites)
            {
                if (!_cookieRobotRunning || !_session.IsRunning) break;
                DockStatus.Text = $"Warming cookies: {site}";
                await _session.NavigateActiveTabAsync(site);
                await Task.Delay(5500);
            }
        }
        catch { }
        finally
        {
            _cookieRobotRunning = false;
            BtnCookieRobot.Content = "Cookie Robot";
            DockStatus.Text = "Cookie Robot finished.";
        }
    }

    private async void BtnHumanPaste_Click(object sender, RoutedEventArgs e)
    {
        string text = "";
        try { text = Clipboard.GetText(); } catch { }
        if (string.IsNullOrEmpty(text))
        {
            DockStatus.Text = "Clipboard is empty.";
            return;
        }
        DockStatus.Text = $"Human typing {text.Length} chars...";
        _session.Activate();
        await Task.Delay(300);
        await _session.HumanTypeAsync(text);
        DockStatus.Text = "Human Paste complete.";
    }

    private void CbGeoPreset_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingGeo || CbGeoPreset.SelectedIndex < 0 || CbGeoPreset.SelectedIndex >= GeoPresets.All.Length) return;
        var p = GeoPresets.All[CbGeoPreset.SelectedIndex];
        if (CbGeoPreset.SelectedIndex == 0 && (Math.Abs(_session.Connection.Lat) > 0.0001 || Math.Abs(_session.Connection.Lon) > 0.0001))
        {
            TxtLat.Text = _session.Connection.Lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLon.Text = _session.Connection.Lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
        }
        else if (Math.Abs(p.Lat) > 0.0001 || Math.Abs(p.Lon) > 0.0001)
        {
            TxtLat.Text = p.Lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLon.Text = p.Lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
        }
    }

    private async void BtnApplyGeo_Click(object sender, RoutedEventArgs e)
    {
        if (!double.TryParse(TxtLat.Text.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double lat) ||
            !double.TryParse(TxtLon.Text.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double lon))
        {
            DockStatus.Text = "Invalid Lat/Lon numbers.";
            return;
        }
        lat = Math.Clamp(lat, -90, 90);
        lon = Math.Clamp(lon, -180, 180);
        _session.Profile.AutoGeolocation = CbGeoPreset.SelectedIndex == 0;
        _session.Profile.CustomGeoLat = lat;
        _session.Profile.CustomGeoLon = lon;
        _saveStore();

        await _session.ApplyLiveGeolocationAsync(lat, lon);
        TxtGeoStatus.Text = $"Active GPS: {lat:F4}, {lon:F4}";
        DockStatus.Text = $"Live GPS updated: {lat:F4}, {lon:F4}";
    }

    private void BtnVCam_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string cmd) return;
        try
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "MHVirtualCam");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "remote_cmd.txt"), $"{cmd}|{DateTime.UtcNow.Ticks}");
            DockStatus.Text = $"VirtualCam cmd sent: {cmd}";
        }
        catch (Exception ex) { DockStatus.Text = $"VCam err: {ex.Message}"; }
    }

    private async void BtnExportCookies_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog { Filter = "JSON Cookies (*.json)|*.json", FileName = $"{_session.Profile.Name}_cookies.json" };
        if (dlg.ShowDialog() != true) return;
        int n = await _session.ExportCookiesJsonAsync(dlg.FileName);
        DockStatus.Text = $"Exported {n} cookies.";
    }

    private async void BtnImportCookies_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "JSON Cookies (*.json)|*.json|All Files|*.*" };
        if (dlg.ShowDialog() != true) return;
        int n = await _session.ImportCookiesJsonAsync(dlg.FileName);
        DockStatus.Text = $"Imported {n} cookies.";
    }

    private void BtnCopyCdp_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(TxtCdpEndpoint.Text); DockStatus.Text = "Copied CDP URL."; } catch { }
    }
}
