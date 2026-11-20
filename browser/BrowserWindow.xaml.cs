using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

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
    private string _activeTimezone = "";

    public BrowserWindow(BrowserProfile profile)
    {
        InitializeComponent();
        _profile = profile;
        Title = $"MH Browser - {profile.Name}";
        ProfileBadgeText.Text = profile.Name;
        ProxyBadgeText.Text = profile.ProxySummary;
        UaStatusText.Text = profile.DeviceSummary;

        Loaded += async (_, _) => await InitEnvironmentAndFirstTabAsync();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
    }

    protected override void OnClosed(EventArgs e)
    {
        foreach (var t in _tabs)
        {
            try { t.WebView.Dispose(); } catch { }
        }
        _tabs.Clear();
        _profile.IsRunning = false;
        base.OnClosed(e);
    }

    private async Task InitEnvironmentAndFirstTabAsync()
    {
        try
        {
            _profile.IsRunning = true;

            // Auto-detect timezone from active VPN / Proxy IP if enabled
            _activeTimezone = _profile.Timezone;
            if (_profile.AutoTimezone)
            {
                StatusText.Text = "Detecting IP & Timezone...";
                var (ok, ip, loc, tz) = await IpTimezoneDetector.DetectAsync(_profile);
                if (ok)
                {
                    _activeTimezone = tz;
                    _profile.Timezone = tz;
                    _profile.NotifyAll();
                    StatusText.Text = $"IP: {ip} ({loc}) -> Timezone: {tz}";
                }
            }
            TzBadgeText.Text = string.IsNullOrWhiteSpace(_activeTimezone) ? "TZ: System" : $"TZ: {_activeTimezone}";

            // Build isolated Chromium environment per profile
            var args = new List<string> { $"--lang={_profile.Language}" };
            if (_profile.ProxyType != "Direct" && !string.IsNullOrWhiteSpace(_profile.ProxyHost) && !string.IsNullOrWhiteSpace(_profile.ProxyPort))
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
                "MH Browser", MessageBoxButton.OK, MessageBoxImage.Warning);
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

        // 1) User-Agent & native Chromium right-click / DevTools settings
        if (!string.IsNullOrWhiteSpace(_profile.UserAgent))
            core.Settings.UserAgent = _profile.UserAgent;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;

        // 2) Apply per-profile timezone override via Chromium DevTools Protocol
        if (!string.IsNullOrWhiteSpace(_activeTimezone))
        {
            try
            {
                var tzPayload = JsonSerializer.Serialize(new { timezoneId = _activeTimezone });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setTimezoneOverride", tzPayload);
            }
            catch { }
        }

        // 3) Inject per-profile fingerprint consistency script (platform, cores, memory, webdriver, subtle canvas noise)
        await core.AddScriptToExecuteOnDocumentCreatedAsync(BuildFingerprintScript());

        // 4) Auto-authenticate HTTP/HTTPS proxy credentials if provided
        core.BasicAuthenticationRequested += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(_profile.ProxyUser))
            {
                e.Response.UserName = _profile.ProxyUser;
                e.Response.Password = _profile.ProxyPass;
            }
        };

        // 5) Open target="_blank" links as new tabs inside MH Browser (never spawn Edge/Chrome)
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            var targetUri = e.Uri;
            Dispatcher.BeginInvoke(async () => await OpenNewTabAsync(targetUri));
        };

        // 6) Add custom MH Browser items to Chromium's native right-click context menu
        core.ContextMenuRequested += (_, e) =>
        {
            try
            {
                if (!string.IsNullOrEmpty(e.ContextMenuTarget.LinkUri))
                {
                    var link = e.ContextMenuTarget.LinkUri;
                    var itemNewTab = core.Environment.CreateContextMenuItem("Open Link in New MH Tab", null, CoreWebView2ContextMenuItemKind.Command);
                    itemNewTab.CustomItemSelected += (_, _) => Dispatcher.BeginInvoke(async () => await OpenNewTabAsync(link));
                    e.MenuItems.Insert(0, itemNewTab);
                }
            }
            catch { }
        };

        // 7) Auto-allow camera/mic permission when user tests HD USB Webcam
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
        int cores = Math.Clamp(_profile.HardwareConcurrency, 2, 32);
        int mem = Math.Clamp(_profile.DeviceMemoryGb, 2, 64);
        int seed = _profile.NoiseSeed;
        string noiseBlock = _profile.FingerprintNoise ? $@"
try {{
  const seed = {seed};
  const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
  CanvasRenderingContext2D.prototype.getImageData = function(x, y, w, h) {{
    const img = origGetImageData.call(this, x, y, w, h);
    if (img && img.data && img.data.length > 4) {{
      img.data[0] = (img.data[0] + (seed % 3)) & 255;
    }}
    return img;
  }};
}} catch (e) {{}}" : "";

        return $@"
try {{
  Object.defineProperty(navigator, 'webdriver', {{ get: () => false }});
  Object.defineProperty(navigator, 'platform', {{ get: () => {plat} }});
  Object.defineProperty(navigator, 'hardwareConcurrency', {{ get: () => {cores} }});
  Object.defineProperty(navigator, 'deviceMemory', {{ get: () => {mem} }});
  Object.defineProperty(navigator, 'language', {{ get: () => {lang} }});
  Object.defineProperty(navigator, 'languages', {{ get: () => [{lang}, 'en'] }});
}} catch (e) {{}}
{noiseBlock}";
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
                Padding = new Thickness(6, 0, 2, 0),
                FontSize = 14,
                Cursor = Cursors.Hand
            };
            closeBtn.Click += (_, e) => { e.Handled = true; CloseTab(idx); };
            sp.Children.Add(closeBtn);

            var tabBorder = new Border
            {
                Background = (Brush)FindResource(active ? "Panel" : "Surface"),
                BorderBrush = (Brush)FindResource(active ? "Accent" : "BorderBrush"),
                BorderThickness = active ? new Thickness(1, 2, 1, 0) : new Thickness(1),
                CornerRadius = new CornerRadius(6, 6, 0, 0),
                Padding = new Thickness(10, 5, 6, 5),
                Margin = new Thickness(0, 4, 4, 0),
                Cursor = Cursors.Hand,
                Child = sp
            };
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
