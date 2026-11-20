using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;

namespace MHBrowser;

public partial class BrowserWindow : Window
{
    private sealed class TabState
    {
        public WebView2 WebView { get; init; } = new();
        public string Title { get; set; } = "New Tab";
        public string Url { get; set; } = "";
    }

    private readonly BrowserProfile _profile;
    private readonly List<TabState> _tabs = new();
    private int _activeIndex = -1;
    private CoreWebView2Environment? _env;
    private ProfileVpnSession? _vpnSession;
    private int _localVpnSocksPort;
    private string _activeTimezone = "";
    private double _geoLat;
    private double _geoLon;
    private bool _hasGeo;

    public BrowserWindow(BrowserProfile profile)
    {
        InitializeComponent();
        _profile = profile;
        Title = $"MH Browser - {profile.Name}";
        ProfileBadgeText.Text = profile.Name;
        ProxyBadgeText.Text = profile.ProxySummary;
        UaStatusText.Text = $"{profile.DeviceSummary} | {profile.ScreenW}x{profile.ScreenH}";

        Loaded += async (_, _) => await InitEnvironmentAndFirstTabAsync();
    }

    protected override void OnClosed(EventArgs e)
    {
        foreach (var t in _tabs)
        {
            try { t.WebView.Dispose(); } catch { }
        }
        _tabs.Clear();
        try { _vpnSession?.Dispose(); } catch { }
        _vpnSession = null;
        _profile.IsRunning = false;
        base.OnClosed(e);
    }

    private void Window_StateChanged(object sender, EventArgs e)
    {
        RootGrid.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
        BtnMaxRestore.Content = WindowState == WindowState.Maximized ? "\u2750" : "\u25A1";
    }

    private void BtnMin_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void BtnMax_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private async Task InitEnvironmentAndFirstTabAsync()
    {
        try
        {
            _profile.IsRunning = true;

            // 1) Start isolated per-profile OpenVPN / WireGuard tunnel (ZERO CMD window, PC IP untouched!)
            if (_profile.ProxyType is "OpenVPN" or "WireGuard")
            {
                _vpnSession = new ProfileVpnSession();
                var (ok, port, msg) = await _vpnSession.StartAsync(
                    _profile.Id,
                    _profile.ProxyType,
                    _profile.VpnConfigPath,
                    status => Dispatcher.BeginInvoke(() => StatusText.Text = status));

                if (!ok)
                {
                    StatusText.Text = msg;
                    ProxyBadgeText.Text = $"{_profile.ProxyType}: Failed";
                    MessageBox.Show(this,
                        $"Could not connect isolated {_profile.ProxyType} tunnel:\n\n{msg}",
                        "MH Advanced Tool - Profile VPN", MessageBoxButton.OK, MessageBoxImage.Warning);
                    Close();
                    return;
                }

                _localVpnSocksPort = port;
                ProxyBadgeText.Text = $"{_profile.ProxyType} (Isolated)";
                StatusText.Text = msg;
            }

            // 2) Auto-detect timezone & geolocation through the profile's proxy OR isolated VPN SOCKS5 port
            _activeTimezone = _profile.Timezone;
            if (_profile.AutoTimezone || _profile.AutoGeolocation)
            {
                StatusText.Text = "Detecting profile exit IP, Timezone & Geolocation...";
                var (ok, ip, loc, tz, lat, lon) = await IpTimezoneDetector.DetectAsync(_profile, _localVpnSocksPort);
                if (ok)
                {
                    if (_profile.AutoTimezone)
                    {
                        _activeTimezone = tz;
                        _profile.Timezone = tz;
                    }
                    if (_profile.AutoGeolocation && (Math.Abs(lat) > 0.001 || Math.Abs(lon) > 0.001))
                    {
                        _geoLat = lat;
                        _geoLon = lon;
                        _hasGeo = true;
                    }
                    _profile.NotifyAll();
                    StatusText.Text = $"Profile IP: {ip} ({loc}) | TZ: {_activeTimezone}";
                }
            }
            TzBadgeText.Text = string.IsNullOrWhiteSpace(_activeTimezone) ? "TZ: System" : $"TZ: {_activeTimezone}";

            // 3) Build isolated Chromium environment per profile
            var args = new List<string>
            {
                $"--lang={_profile.Language}",
                "--disable-blink-features=AutomationControlled"
            };
            if (_localVpnSocksPort > 0)
            {
                // Route ONLY this browser profile through its isolated local VPN SOCKS5 tunnel!
                args.Add($"--proxy-server=\"socks5://127.0.0.1:{_localVpnSocksPort}\"");
                args.Add("--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE 127.0.0.1\"");
            }
            else if (_profile.ProxyType is "HTTP" or "HTTPS" or "SOCKS5" &&
                     !string.IsNullOrWhiteSpace(_profile.ProxyHost) && !string.IsNullOrWhiteSpace(_profile.ProxyPort))
            {
                string scheme = _profile.ProxyType switch
                {
                    "SOCKS5" => "socks5",
                    "HTTPS" => "https",
                    _ => "http"
                };
                args.Add($"--proxy-server=\"{scheme}://{_profile.ProxyHost}:{_profile.ProxyPort}\"");
            }
            if (_profile.WebRtcProtect)
            {
                args.Add("--force-webrtc-ip-handling-policy=disable_non_proxied_udp");
            }

            Directory.CreateDirectory(_profile.UserDataDir);
            var opts = new CoreWebView2EnvironmentOptions(string.Join(" ", args), _profile.Language);
            _env = await CoreWebView2Environment.CreateAsync(null, _profile.UserDataDir, opts);

            string startUrl = string.IsNullOrWhiteSpace(_profile.StartUrl) ? "https://whoer.net" : _profile.StartUrl;
            await OpenNewTabAsync(startUrl);
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Chromium init error: {ex.Message}";
            MessageBox.Show(this,
                $"Could not initialize WebView2 Chromium engine:\n{ex.Message}\n\nMake sure Microsoft Edge WebView2 Runtime is installed.",
                "MH Advanced Tool", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task OpenNewTabAsync(string url)
    {
        if (_env is null) return;
        var tab = new TabState { Url = url };
        tab.WebView.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 14, 16, 19);
        WebViewHost.Children.Add(tab.WebView);
        _tabs.Add(tab);
        int idx = _tabs.Count - 1;
        SelectTab(idx);

        await tab.WebView.EnsureCoreWebView2Async(_env);
        var core = tab.WebView.CoreWebView2;

        // 1) User-Agent & native Chromium settings
        if (!string.IsNullOrWhiteSpace(_profile.UserAgent))
            core.Settings.UserAgent = _profile.UserAgent;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;

        // 2) CDP Timezone override
        if (!string.IsNullOrWhiteSpace(_activeTimezone))
        {
            try
            {
                var tzPayload = JsonSerializer.Serialize(new { timezoneId = _activeTimezone });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setTimezoneOverride", tzPayload);
            }
            catch { }
        }

        // 3) CDP Geolocation override synced to Proxy/VPN IP
        if (_hasGeo && _profile.AutoGeolocation)
        {
            try
            {
                var geoPayload = JsonSerializer.Serialize(new { latitude = _geoLat, longitude = _geoLon, accuracy = 100 });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setGeolocationOverride", geoPayload);
            }
            catch { }
        }

        // 4) CDP Mobile device metrics override for Mobile/Tablet presets
        if (_profile.IsMobile && _profile.ScreenW > 200 && _profile.ScreenH > 200)
        {
            try
            {
                var metricsPayload = JsonSerializer.Serialize(new
                {
                    width = _profile.ScreenW,
                    height = _profile.ScreenH,
                    deviceScaleFactor = _profile.PixelRatio,
                    mobile = true
                });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setDeviceMetricsOverride", metricsPayload);
            }
            catch { }
        }

        // 5) Inject advanced multi-layer fingerprint spoofing script
        await core.AddScriptToExecuteOnDocumentCreatedAsync(BuildFingerprintScript());

        // 6) Auto-authenticate HTTP/HTTPS proxy credentials if provided
        core.BasicAuthenticationRequested += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(_profile.ProxyUser))
            {
                e.Response.UserName = _profile.ProxyUser;
                e.Response.Password = _profile.ProxyPass;
            }
        };

        // 7) Open target="_blank" links as new tabs inside MH Browser
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            var targetUri = e.Uri;
            Dispatcher.BeginInvoke(async () => await OpenNewTabAsync(targetUri));
        };

        // 8) Native right-click context menu item
        core.ContextMenuRequested += (_, e) =>
        {
            try
            {
                if (!string.IsNullOrEmpty(e.ContextMenuTarget.LinkUri))
                {
                    var link = e.ContextMenuTarget.LinkUri;
                    var itemNewTab = core.Environment.CreateContextMenuItem("Open Link in New Tab", null, CoreWebView2ContextMenuItemKind.Command);
                    itemNewTab.CustomItemSelected += (_, _) => Dispatcher.BeginInvoke(async () => await OpenNewTabAsync(link));
                    e.MenuItems.Insert(0, itemNewTab);
                }
            }
            catch { }
        };

        // 9) Auto-allow camera/mic permission for HD USB Webcam
        core.PermissionRequested += (_, e) =>
        {
            if (e.PermissionKind is CoreWebView2PermissionKind.Camera or CoreWebView2PermissionKind.Microphone)
                e.State = CoreWebView2PermissionState.Allow;
        };

        core.DocumentTitleChanged += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            tab.Title = string.IsNullOrWhiteSpace(core.DocumentTitle) ? "New Tab" : core.DocumentTitle;
            RebuildTabStrip();
        });

        core.SourceChanged += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            tab.Url = core.Source;
            if (_activeIndex >= 0 && _activeIndex < _tabs.Count && ReferenceEquals(_tabs[_activeIndex], tab))
                UrlBox.Text = tab.Url;
        });

        core.NavigationStarting += (_, e) => Dispatcher.BeginInvoke(() => StatusText.Text = $"Loading {e.Uri}...");
        core.NavigationCompleted += (_, e) => Dispatcher.BeginInvoke(() =>
            StatusText.Text = e.IsSuccess ? $"Ready - {core.Source}" : $"Navigation error ({e.WebErrorStatus})");

        core.Navigate(NormalizeUrl(url));
    }

    private string BuildFingerprintScript()
    {
        var plat = JsonSerializer.Serialize(_profile.Platform);
        var lang = JsonSerializer.Serialize(_profile.Language);
        var webglVendor = JsonSerializer.Serialize(string.IsNullOrWhiteSpace(_profile.WebGlVendor) ? "Google Inc. (NVIDIA)" : _profile.WebGlVendor);
        var webglRenderer = JsonSerializer.Serialize(string.IsNullOrWhiteSpace(_profile.WebGlRenderer) ? "ANGLE (NVIDIA, NVIDIA GeForce RTX 4060 Direct3D11 vs_5_0 ps_5_0, D3D11)" : _profile.WebGlRenderer);
        int cores = Math.Clamp(_profile.HardwareConcurrency, 2, 32);
        int mem = Math.Clamp(_profile.DeviceMemoryGb, 2, 64);
        int sw = Math.Clamp(_profile.ScreenW, 320, 7680);
        int sh = Math.Clamp(_profile.ScreenH, 320, 4320);
        double dpr = Math.Clamp(_profile.PixelRatio, 1.0, 4.0);
        string isMobileJs = _profile.IsMobile ? "true" : "false";
        int touchPoints = _profile.IsMobile ? 5 : 0;
        string chPlatform = _profile.Platform.Contains("Mac", StringComparison.OrdinalIgnoreCase) ? "macOS"
            : _profile.Platform.Contains("iPhone", StringComparison.OrdinalIgnoreCase) || _profile.Platform.Contains("iPad", StringComparison.OrdinalIgnoreCase) ? "iOS"
            : _profile.UserAgent.Contains("Android", StringComparison.OrdinalIgnoreCase) ? "Android"
            : _profile.Platform.Contains("Linux", StringComparison.OrdinalIgnoreCase) ? "Linux"
            : "Windows";
        var chPlatJson = JsonSerializer.Serialize(chPlatform);
        int seed = _profile.NoiseSeed;

        string canvasBlock = _profile.FingerprintNoise ? $@"
try {{
  const seed = {seed};
  const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
  CanvasRenderingContext2D.prototype.getImageData = function(x, y, w, h) {{
    const img = origGetImageData.call(this, x, y, w, h);
    if (img && img.data && img.data.length > 8) {{
      img.data[0] = (img.data[0] + (seed % 3) + 1) & 255;
      img.data[4] = (img.data[4] + ((seed >> 2) % 3)) & 255;
    }}
    return img;
  }};
  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
  HTMLCanvasElement.prototype.toDataURL = function() {{
    try {{
      const ctx = this.getContext('2d');
      if (ctx && this.width > 2 && this.height > 2) {{
        const px = origGetImageData.call(ctx, 0, 0, 1, 1);
        px.data[0] = (px.data[0] ^ ((seed % 2) + 1)) & 255;
        ctx.putImageData(px, 0, 0);
      }}
    }} catch (e) {{}}
    return origToDataURL.apply(this, arguments);
  }};
}} catch (e) {{}}" : "";

        string webglBlock = _profile.WebGlSpoof ? $@"
try {{
  const patchWebGL = (proto) => {{
    if (!proto || !proto.getParameter) return;
    const origGetParameter = proto.getParameter;
    proto.getParameter = function(param) {{
      if (param === 37445) return {webglVendor};
      if (param === 37446) return {webglRenderer};
      return origGetParameter.call(this, param);
    }};
  }};
  if (typeof WebGLRenderingContext !== 'undefined') patchWebGL(WebGLRenderingContext.prototype);
  if (typeof WebGL2RenderingContext !== 'undefined') patchWebGL(WebGL2RenderingContext.prototype);
}} catch (e) {{}}" : "";

        string audioBlock = _profile.AudioNoise ? $@"
try {{
  const aSeed = (({seed} % 97) + 1) * 1e-7;
  const origGetChannelData = AudioBuffer.prototype.getChannelData;
  AudioBuffer.prototype.getChannelData = function(channel) {{
    const data = origGetChannelData.call(this, channel);
    if (data && data.length > 0 && !data.__mhPatched) {{
      for (let i = 0; i < Math.min(data.length, 64); i += 16) {{
        data[i] = data[i] + aSeed;
      }}
      Object.defineProperty(data, '__mhPatched', {{ value: true }});
    }}
    return data;
  }};
}} catch (e) {{}}" : "";

        return $@"
try {{
  Object.defineProperty(navigator, 'webdriver', {{ get: () => false }});
  Object.defineProperty(navigator, 'platform', {{ get: () => {plat} }});
  Object.defineProperty(navigator, 'hardwareConcurrency', {{ get: () => {cores} }});
  Object.defineProperty(navigator, 'deviceMemory', {{ get: () => {mem} }});
  Object.defineProperty(navigator, 'maxTouchPoints', {{ get: () => {touchPoints} }});
  Object.defineProperty(navigator, 'language', {{ get: () => {lang} }});
  Object.defineProperty(navigator, 'languages', {{ get: () => [{lang}, 'en'] }});
  if (navigator.userAgentData) {{
    const uaData = {{
      brands: [{{ brand: 'Chromium', version: '131' }}, {{ brand: 'Not_A Brand', version: '24' }}, {{ brand: 'Google Chrome', version: '131' }}],
      mobile: {isMobileJs},
      platform: {chPlatJson},
      getHighEntropyValues: async (hints) => ({{
        architecture: 'x86',
        bitness: '64',
        mobile: {isMobileJs},
        model: '',
        platform: {chPlatJson},
        platformVersion: '15.0.0',
        uaFullVersion: '131.0.0.0'
      }})
    }};
    Object.defineProperty(navigator, 'userAgentData', {{ get: () => uaData }});
  }}
  Object.defineProperty(window, 'devicePixelRatio', {{ get: () => {dpr.ToString(System.Globalization.CultureInfo.InvariantCulture)} }});
  Object.defineProperty(screen, 'width', {{ get: () => {sw} }});
  Object.defineProperty(screen, 'height', {{ get: () => {sh} }});
  Object.defineProperty(screen, 'availWidth', {{ get: () => {sw} }});
  Object.defineProperty(screen, 'availHeight', {{ get: () => {Math.Max(sh - 40, 200)} }});
  Object.defineProperty(screen, 'colorDepth', {{ get: () => 24 }});
  Object.defineProperty(screen, 'pixelDepth', {{ get: () => 24 }});
}} catch (e) {{}}
{canvasBlock}
{webglBlock}
{audioBlock}";
    }

    private void SelectTab(int index)
    {
        if (index < 0 || index >= _tabs.Count) return;
        _activeIndex = index;
        for (int i = 0; i < _tabs.Count; i++)
            _tabs[i].WebView.Visibility = (i == index) ? Visibility.Visible : Visibility.Collapsed;
        UrlBox.Text = _tabs[index].Url;
        RebuildTabStrip();
    }

    private void CloseTab(int index)
    {
        if (index < 0 || index >= _tabs.Count) return;
        if (_tabs.Count == 1) { Close(); return; }
        var tab = _tabs[index];
        WebViewHost.Children.Remove(tab.WebView);
        try { tab.WebView.Dispose(); } catch { }
        _tabs.RemoveAt(index);
        SelectTab(Math.Min(index, _tabs.Count - 1));
    }

    private void RebuildTabStrip()
    {
        TabsPanel.Children.Clear();
        for (int i = 0; i < _tabs.Count; i++)
        {
            int idx = i;
            bool active = (i == _activeIndex);
            var title = _tabs[i].Title;
            if (title.Length > 20) title = title[..20] + "...";

            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            sp.Children.Add(new TextBlock
            {
                Text = title,
                Foreground = (Brush)FindResource(active ? "Text" : "Muted"),
                FontSize = 12,
                FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal,
                VerticalAlignment = VerticalAlignment.Center
            });

            var closeBtn = new Button
            {
                Content = "×",
                Background = Brushes.Transparent,
                Foreground = (Brush)FindResource("Muted"),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(7, 0, 2, 0),
                FontSize = 13.5,
                Cursor = Cursors.Hand
            };
            WindowChrome.SetIsHitTestVisibleInChrome(closeBtn, true);
            closeBtn.Click += (_, e) => { e.Handled = true; CloseTab(idx); };
            sp.Children.Add(closeBtn);

            var tabBorder = new Border
            {
                Background = (Brush)FindResource(active ? "Panel" : "Surface"),
                BorderBrush = active ? (Brush)FindResource("BorderBrush") : Brushes.Transparent,
                BorderThickness = active ? new Thickness(1, 1, 1, 0) : new Thickness(0),
                CornerRadius = new CornerRadius(8, 8, 0, 0),
                Padding = new Thickness(12, 6, 8, 6),
                Margin = new Thickness(0, 5, 3, 0),
                Cursor = Cursors.Hand,
                Child = sp
            };
            WindowChrome.SetIsHitTestVisibleInChrome(tabBorder, true);
            tabBorder.MouseLeftButtonDown += (_, _) => SelectTab(idx);
            TabsPanel.Children.Add(tabBorder);
        }
    }

    private CoreWebView2? ActiveCore =>
        (_activeIndex >= 0 && _activeIndex < _tabs.Count) ? _tabs[_activeIndex].WebView.CoreWebView2 : null;

    private static string NormalizeUrl(string input)
    {
        input = input.Trim();
        if (string.IsNullOrEmpty(input)) return "https://whoer.net";
        if (input.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return input;
        if (!input.Contains(' ') && input.Contains('.'))
            return "https://" + input;
        return "https://duckduckgo.com/?q=" + Uri.EscapeDataString(input);
    }

    private void NavigateCurrent(string input) => ActiveCore?.Navigate(NormalizeUrl(input));

    private async void BtnNewTab_Click(object sender, RoutedEventArgs e) => await OpenNewTabAsync("https://duckduckgo.com");
    private void BtnBack_Click(object sender, RoutedEventArgs e) { if (ActiveCore?.CanGoBack == true) ActiveCore.GoBack(); }
    private void BtnForward_Click(object sender, RoutedEventArgs e) { if (ActiveCore?.CanGoForward == true) ActiveCore.GoForward(); }
    private void BtnReload_Click(object sender, RoutedEventArgs e) => ActiveCore?.Reload();
    private void BtnHome_Click(object sender, RoutedEventArgs e) => NavigateCurrent(_profile.StartUrl);
    private void BtnWebcamTest_Click(object sender, RoutedEventArgs e) => NavigateCurrent("https://webcamtests.com");
    private void BtnWhoer_Click(object sender, RoutedEventArgs e) => NavigateCurrent("https://whoer.net");
    private void BtnDevTools_Click(object sender, RoutedEventArgs e) => ActiveCore?.OpenDevToolsWindow();

    private void UrlBox_GotFocus(object sender, KeyboardFocusChangedEventArgs e) => UrlBox.SelectAll();

    private void UrlBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            NavigateCurrent(UrlBox.Text);
            e.Handled = true;
        }
    }

    private async void Window_KeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        if (ctrl && e.Key == Key.T) { await OpenNewTabAsync("https://duckduckgo.com"); e.Handled = true; }
        else if (ctrl && e.Key == Key.W) { CloseTab(_activeIndex); e.Handled = true; }
        else if (ctrl && e.Key == Key.L) { UrlBox.Focus(); UrlBox.SelectAll(); e.Handled = true; }
        else if (e.Key == Key.F5) { ActiveCore?.Reload(); e.Handled = true; }
        else if (e.Key == Key.F12) { ActiveCore?.OpenDevToolsWindow(); e.Handled = true; }
    }
}
