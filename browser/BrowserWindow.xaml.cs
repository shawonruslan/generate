using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;

namespace MHBrowser;

public sealed record VerifiedConnection(
    ProfileVpnSession? VpnSession,
    LocalSocks5AuthForwarder? SocksForwarder,
    int LocalSocksPort,
    string ExitIp,
    string Location,
    string Timezone,
    double Lat,
    double Lon,
    LocalHttpProxyAuthForwarder? HttpForwarder = null,
    int LocalHttpPort = 0);

public partial class BrowserWindow : Window
{
    private sealed class TabState
    {
        public WebView2 WebView { get; init; } = new();
        public string Title { get; set; } = "New Tab";
        public string Url { get; set; } = "";
        public bool IsLoading { get; set; }
        public ImageSource? Favicon { get; set; }
        public bool InspectorAttached { get; set; }
    }

    private readonly BrowserProfile _profile;
    private readonly Action _saveStore;
    private readonly VerifiedConnection _conn;
    private readonly List<TabState> _tabs = new();
    private readonly int _cdpPort;
    private int _activeIndex = -1;
    private CoreWebView2Environment? _env;
    private DispatcherTimer? _killSwitchTimer;
    private int _consecutiveDropCount;
    private bool _shieldAlertActive;
    private bool _healthCheckInFlight;
    private bool _extensionsLoaded;
    private readonly Dictionary<string, string> _extIdToFolder = new();
    private bool _trayOpen;
    private bool _loadingEngineCombo;
    private bool _cookieRobotRunning;
    private readonly ObservableCollection<CapturedNetRequest> _capturedNet = new();
    private readonly Dictionary<string, CapturedNetRequest> _netById = new();
    private readonly ObservableCollection<RecordedUiAction> _recordedUi = new();
    private readonly ObservableCollection<InternalSecurityEvent> _internalEvents = new();
    private InspectorWindow? _inspectorWindow;
    private CoreWebView2PermissionRequestedEventArgs? _pendingPermArgs;
    private CoreWebView2Deferral? _pendingPermDeferral;
    private double _activeGeoLat;
    private double _activeGeoLon;
    private double _activeGeoAcc = 35;
    private bool _geoSpoofActive;
    private bool _loadingGeoCombo;

    public BrowserWindow(BrowserProfile profile, VerifiedConnection conn, Action saveStore)
    {
        InitializeComponent();
        _profile = profile;
        _conn = conn;
        _saveStore = saveStore;
        _cdpPort = CdpPortAllocator.AllocateFreePort();

        Title = $"MH Browser - {profile.Name}";
        ProfileBadgeText.Text = profile.Name;
        ProxyBadgeText.Text = _conn.LocalSocksPort > 0 && profile.ProxyType is "OpenVPN" or "WireGuard"
            ? $"{profile.ProxyType} (Isolated)"
            : profile.ProxySummary;
        TzBadgeText.Text = string.IsNullOrWhiteSpace(_conn.Timezone) ? "TZ: System" : $"TZ: {_conn.Timezone}";
        UaStatusText.Text = $"{profile.DeviceSummary} | {profile.ScreenW}x{profile.ScreenH}";
        TraySessionIp.Text = string.IsNullOrWhiteSpace(_conn.ExitIp) ? "IP: Direct" : $"IP: {_conn.ExitIp} ({_conn.Location})";
        TraySessionDevice.Text = $"{profile.DeviceSummary}\nGPU: {profile.WebGlRenderer}";
        TxtCdpUrl.Text = $"http://127.0.0.1:{_cdpPort}";

        _loadingEngineCombo = true;
        CbSearchEngine.ItemsSource = SearchEngines.All.Select(e => e.Name).ToList();
        int seIdx = Array.FindIndex(SearchEngines.All, e => e.Name.Equals(profile.SearchEngine, StringComparison.OrdinalIgnoreCase));
        CbSearchEngine.SelectedIndex = seIdx >= 0 ? seIdx : 0;
        _loadingEngineCombo = false;

        // Resolve initial spoofed GPS coordinates (custom coordinates take priority when AutoGeolocation is off)
        _activeGeoAcc = profile.CustomGeoAccuracy > 0 ? profile.CustomGeoAccuracy : 35;
        if (!profile.AutoGeolocation && (Math.Abs(profile.CustomGeoLat) > 0.0001 || Math.Abs(profile.CustomGeoLon) > 0.0001))
        {
            _activeGeoLat = profile.CustomGeoLat;
            _activeGeoLon = profile.CustomGeoLon;
            _geoSpoofActive = true;
        }
        else if (Math.Abs(conn.Lat) > 0.0001 || Math.Abs(conn.Lon) > 0.0001)
        {
            _activeGeoLat = conn.Lat;
            _activeGeoLon = conn.Lon;
            _geoSpoofActive = true;
        }
        else if (Math.Abs(profile.CustomGeoLat) > 0.0001 || Math.Abs(profile.CustomGeoLon) > 0.0001)
        {
            _activeGeoLat = profile.CustomGeoLat;
            _activeGeoLon = profile.CustomGeoLon;
            _geoSpoofActive = true;
        }

        _loadingGeoCombo = true;
        CbLiveGeoPreset.ItemsSource = GeoPresets.All.Select(g => g.Name).ToList();
        CbLiveGeoPreset.SelectedIndex = profile.AutoGeolocation ? 0 : GeoPresets.All.Length - 1;
        _loadingGeoCombo = false;
        RefreshLiveGeoUi();

        RefreshBookmarksUi();
        RefreshHistoryUi();
        WindowSyncManager.Register(this);

        Loaded += async (_, _) => { Window_StateChanged(this, EventArgs.Empty); await InitEnvironmentAndRestoreTabsAsync(); };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.SetWindowAppUserModelId(this, "MHAdvancedTool.Browser");
        try
        {
            Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/browser.ico", UriKind.Absolute));
        }
        catch { }
    }

    protected override void OnClosed(EventArgs e)
    {
        _killSwitchTimer?.Stop();
        WindowSyncManager.Unregister(this);
        try { _inspectorWindow?.Close(); } catch { }
        PersistOpenTabs();
        foreach (var t in _tabs)
        {
            try { t.WebView.Dispose(); } catch { }
        }
        _tabs.Clear();
        try { _conn.VpnSession?.Dispose(); } catch { }
        try { _conn.SocksForwarder?.Dispose(); } catch { }
        _profile.IsRunning = false;
        base.OnClosed(e);
    }

    private void PersistOpenTabs()
    {
        try
        {
            var urls = _tabs
                .Select(t => t.Url)
                .Where(u => !string.IsNullOrWhiteSpace(u) && !u.StartsWith("about:", StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (urls.Count > 0)
            {
                _profile.SavedTabs = urls;
                _profile.ActiveTabIndex = Math.Clamp(_activeIndex, 0, urls.Count - 1);
                _saveStore();
            }
        }
        catch { }
    }

    private void Window_StateChanged(object sender, EventArgs e)
    {
        RootGrid.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
        BtnMaxRestore.Content = WindowState == WindowState.Maximized ? "\u2750" : "\u25A1";
    }

    private void BtnMin_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void BtnMax_Click(object sender, RoutedEventArgs e) =>
        WindowState = (WindowState == WindowState.Maximized) ? WindowState.Normal : WindowState.Maximized;
    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void StartKillSwitchWatchdog()
    {
        if (_profile.ProxyType == "Direct") return;
        _killSwitchTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(25) };
        _killSwitchTimer.Tick += async (_, _) => await RunShieldHealthCheckAsync(forceReconnect: false);
        _killSwitchTimer.Start();
    }

    private async void BtnReconnectNow_Click(object sender, RoutedEventArgs e)
    {
        BtnReconnectNow.IsEnabled = false;
        BtnReconnectNow.Content = "Checking...";
        try
        {
            await RunShieldHealthCheckAsync(forceReconnect: true);
        }
        finally
        {
            BtnReconnectNow.Content = "Reconnect Now";
            BtnReconnectNow.IsEnabled = true;
        }
    }

    private async Task RunShieldHealthCheckAsync(bool forceReconnect)
    {
        if (_profile.ProxyType == "Direct" || _healthCheckInFlight) return;
        _healthCheckInFlight = true;
        try
        {
            // 1) If an isolated VPN tunnel process (OpenVPN / WireGuard) actually died, auto-restart it on the SAME local port
            if (_conn.VpnSession is not null && (forceReconnect || !_conn.VpnSession.IsProcessAlive))
            {
                _shieldAlertActive = true;
                KillSwitchBanner.Visibility = Visibility.Visible;
                KillSwitchBannerText.Text = $"SHIELD ACTIVE: {_profile.ProxyType} tunnel interrupted (Real IP safe). Reconnecting tunnel...";
                StatusText.Text = $"Reconnecting {_profile.ProxyType} tunnel (Zero-Leak Shield active)...";

                var (recOk, recMsg) = await _conn.VpnSession.ReconnectInPlaceAsync(
                    status => Dispatcher.Invoke(() => StatusText.Text = status));
                if (!recOk)
                {
                    KillSwitchBannerText.Text = $"SHIELD ACTIVE: {_profile.ProxyType} reconnecting... ({recMsg.Split('\n')[0]}) - Real IP protected.";
                    if (_killSwitchTimer is not null) _killSwitchTimer.Interval = TimeSpan.FromSeconds(6);
                    return;
                }
            }

            // 2) Verify proxy/VPN connectivity through the locked tunnel (never uses direct host IP)
            var (ok, ip, loc, tz, _, _) = await IpTimezoneDetector.DetectAsync(
                _conn.LocalSocksPort > 0 ? null : _profile, _conn.LocalSocksPort);

            if (ok)
            {
                _consecutiveDropCount = 0;
                if (_shieldAlertActive)
                {
                    _shieldAlertActive = false;
                    KillSwitchBanner.Visibility = Visibility.Collapsed;
                    if (_killSwitchTimer is not null) _killSwitchTimer.Interval = TimeSpan.FromSeconds(25);
                }
                if (!string.IsNullOrWhiteSpace(ip))
                {
                    TraySessionIp.Text = $"IP: {ip} ({loc})";
                    if (StatusText.Text.Contains("SHIELD", StringComparison.OrdinalIgnoreCase) ||
                        StatusText.Text.Contains("Reconnect", StringComparison.OrdinalIgnoreCase))
                    {
                        StatusText.Text = $"Reconnected: {ip} ({loc}) | Zero-Leak Shield OK";
                    }
                }
            }
            else
            {
                _consecutiveDropCount++;
                // Tolerate 1 brief network blip; alert & fast-retry after 2 consecutive misses (or manual reconnect)
                if (forceReconnect || _consecutiveDropCount >= 2)
                {
                    _shieldAlertActive = true;
                    KillSwitchBanner.Visibility = Visibility.Visible;
                    KillSwitchBannerText.Text = "SHIELD ACTIVE: Proxy/VPN temporarily unreachable. Real IP is 100% blocked from leaking — auto-retrying every 6s...";
                    StatusText.Text = "Proxy/VPN temporarily down (Real IP shielded — auto-retrying...)";
                    if (_killSwitchTimer is not null) _killSwitchTimer.Interval = TimeSpan.FromSeconds(6);
                }
            }
        }
        catch { }
        finally
        {
            _healthCheckInFlight = false;
        }
    }

    private async Task InitEnvironmentAndRestoreTabsAsync()
    {
        try
        {
            _profile.IsRunning = true;
            StatusText.Text = string.IsNullOrWhiteSpace(_conn.ExitIp)
                ? "Initializing Chromium profile..."
                : $"Connected: {_conn.ExitIp} ({_conn.Location}) | TZ: {_conn.Timezone} | CDP:{_cdpPort}";

            var args = new List<string>
            {
                $"--lang={_profile.Language}",
                "--disable-blink-features=AutomationControlled",
                "--disable-quic",
                "--auto-accept-camera-and-microphone-capture",
                $"--remote-debugging-port={_cdpPort}"
            };

            if (_conn.LocalSocksPort > 0)
            {
                args.Add($"--proxy-server=\"socks5://127.0.0.1:{_conn.LocalSocksPort}\"");
                args.Add("--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE 127.0.0.1\"");
            }
            else if (_profile.ProxyType is "HTTP" or "HTTPS" &&
                     !string.IsNullOrWhiteSpace(_profile.ProxyHost) && !string.IsNullOrWhiteSpace(_profile.ProxyPort))
            {
                string scheme = _profile.ProxyType == "HTTPS" ? "https" : "http";
                args.Add($"--proxy-server=\"{scheme}://{_profile.ProxyHost}:{_profile.ProxyPort}\"");
                args.Add($"--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE {_profile.ProxyHost.Trim()}\"");
            }

            // Always block non-proxied WebRTC UDP whenever any proxy/VPN is active so real IP can NEVER leak
            if (_profile.WebRtcProtect || _profile.ProxyType != "Direct")
                args.Add("--force-webrtc-ip-handling-policy=disable_non_proxied_udp");

            Directory.CreateDirectory(_profile.UserDataDir);
            var opts = new CoreWebView2EnvironmentOptions(string.Join(" ", args), _profile.Language)
            {
                AreBrowserExtensionsEnabled = true
            };
            _env = await CoreWebView2Environment.CreateAsync(null, _profile.UserDataDir, opts);

            var tabsToOpen = _profile.SavedTabs is { Count: > 0 }
                ? _profile.SavedTabs.Where(u => !string.IsNullOrWhiteSpace(u)).ToList()
                : new List<string>();

            if (tabsToOpen.Count == 0)
                tabsToOpen.Add(string.IsNullOrWhiteSpace(_profile.StartUrl) ? "https://whoer.net" : _profile.StartUrl);

            foreach (var u in tabsToOpen)
                await OpenNewTabAsync(u, selectNew: false);

            SelectTab(Math.Clamp(_profile.ActiveTabIndex, 0, _tabs.Count - 1));
            StartKillSwitchWatchdog();
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Chromium init error: {ex.Message}";
            DarkDialog.ShowInfo(this, "MH Browser",
                $"Could not initialize WebView2 Chromium engine:\n{ex.Message}\n\nMake sure Microsoft Edge WebView2 Runtime is installed.");
        }
    }

    private async Task OpenNewTabAsync(string url, bool selectNew = true)
    {
        if (_env is null) return;
        var tab = new TabState { Url = url };
        tab.WebView.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 14, 16, 19);
        WebViewHost.Children.Add(tab.WebView);
        _tabs.Add(tab);
        int idx = _tabs.Count - 1;
        if (selectNew || _activeIndex < 0) SelectTab(idx);
        else tab.WebView.Visibility = Visibility.Collapsed;

        await tab.WebView.EnsureCoreWebView2Async(_env);
        var core = tab.WebView.CoreWebView2;

        // Load profile Chrome extensions once per profile session
        if (!_extensionsLoaded)
        {
            _extensionsLoaded = true;
            var extErrors = new List<string>();
            foreach (var extDir in (_profile.ExtensionPaths ?? new List<string>()).ToList())
            {
                if (!Directory.Exists(extDir)) continue;
                try
                {
                    string metaDir = Path.Combine(extDir, "_metadata");
                    if (Directory.Exists(metaDir)) try { Directory.Delete(metaDir, true); } catch { }
                    var loaded = await core.Profile.AddBrowserExtensionAsync(extDir);
                    _extIdToFolder[loaded.Id] = extDir;
                }
                catch (Exception ex)
                {
                    extErrors.Add($"{Path.GetFileName(extDir)}: {ex.Message}");
                }
            }
            await RefreshLoadedExtensionsUiAsync(core);
            if (extErrors.Count > 0)
                StatusText.Text = $"Extension warning: {extErrors[0]}";
        }

        if (!string.IsNullOrWhiteSpace(_profile.UserAgent))
            core.Settings.UserAgent = _profile.UserAgent;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;

        // Localhost Port-Scan Blocker (Transport-level --proxy-server + --host-resolver-rules + WebRTC lock already guarantees 0% real-IP leak even on brief drops)
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) =>
        {
            // Block external websites from scanning localhost / 127.0.0.1 / 0.0.0.0 ports
            if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var reqUri) &&
                (reqUri.Host == "127.0.0.1" || reqUri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || reqUri.Host == "0.0.0.0"))
            {
                if (!string.IsNullOrEmpty(tab.Url) &&
                    !tab.Url.StartsWith("http://127.0.0.1", StringComparison.OrdinalIgnoreCase) &&
                    !tab.Url.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase))
                {
                    e.Response = _env.CreateWebResourceResponse(null, 403, "Blocked Port Scan", "");
                    AddInternalEvent("PORTSCAN", tab.Url, $"Blocked localhost probe -> {e.Request.Uri}");
                }
            }
        };

        // Real website favicon capture for browser tab strip
        core.FaviconChanged += async (_, _) =>
        {
            try
            {
                using var stream = await core.GetFaviconAsync(CoreWebView2FaviconImageFormat.Png);
                if (stream is not null && stream.Length > 0)
                {
                    using var ms = new MemoryStream();
                    await stream.CopyToAsync(ms);
                    ms.Position = 0;
                    await Dispatcher.BeginInvoke(() =>
                    {
                        try
                        {
                            var bmp = new BitmapImage();
                            bmp.BeginInit();
                            bmp.CacheOption = BitmapCacheOption.OnLoad;
                            bmp.StreamSource = ms;
                            bmp.EndInit();
                            bmp.Freeze();
                            tab.Favicon = bmp;
                            RebuildTabStrip();
                        }
                        catch { }
                    });
                }
            }
            catch { }
        };

        // Attach heavy CDP Network/Audits capture ONLY when Inspector is actively open (keeps normal browsing fast & clean)
        if (_inspectorWindow is not null && _inspectorWindow.IsLoaded)
            await AttachInspectorToTabAsync(tab);

        if (!string.IsNullOrWhiteSpace(_conn.Timezone))
        {
            try
            {
                var tzPayload = JsonSerializer.Serialize(new { timezoneId = _conn.Timezone });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setTimezoneOverride", tzPayload);
            }
            catch { }
        }

        if (_geoSpoofActive)
        {
            try
            {
                var geoPayload = JsonSerializer.Serialize(new { latitude = _activeGeoLat, longitude = _activeGeoLon, accuracy = _activeGeoAcc });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setGeolocationOverride", geoPayload);
            }
            catch { }
        }

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

        await core.AddScriptToExecuteOnDocumentCreatedAsync(BuildFingerprintScript());

        core.BasicAuthenticationRequested += (_, e) =>
        {
            if (!string.IsNullOrWhiteSpace(_profile.ProxyUser))
            {
                e.Response.UserName = _profile.ProxyUser;
                e.Response.Password = _profile.ProxyPass;
            }
        };

        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            var targetUri = e.Uri;
            Dispatcher.BeginInvoke(async () => await OpenNewTabAsync(targetUri));
        };

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

        core.PermissionRequested += (_, e) => HandlePermissionRequest(e);
        core.FrameCreated += (_, fe) =>
        {
            try
            {
                fe.Frame.PermissionRequested += (_, pe) => HandlePermissionRequest(pe);
            }
            catch { }
        };

        core.DocumentTitleChanged += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            tab.Title = string.IsNullOrWhiteSpace(core.DocumentTitle) ? "New Tab" : core.DocumentTitle;
            RebuildTabStrip();
        });

        core.SourceChanged += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            tab.Url = core.Source;
            if (IsActiveTab(tab))
            {
                UrlBox.Text = tab.Url;
                UpdateBookmarkStarState();
            }
            PersistOpenTabs();
        });

        core.NavigationStarting += (_, e) => Dispatcher.BeginInvoke(() =>
        {
            tab.IsLoading = true;
            if (IsActiveTab(tab))
            {
                StatusText.Text = $"Loading {e.Uri}...";
                UpdateLoadingAnimation(true);
            }
        });

        core.NavigationCompleted += (_, e) => Dispatcher.BeginInvoke(() =>
        {
            tab.IsLoading = false;
            if (IsActiveTab(tab))
            {
                StatusText.Text = e.IsSuccess ? $"Ready - {core.Source}" : $"Navigation error ({e.WebErrorStatus})";
                UpdateLoadingAnimation(false);
                UpdateBookmarkStarState();
            }
            if (e.IsSuccess && !string.IsNullOrWhiteSpace(core.Source) && core.Source.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                RecordHistory(string.IsNullOrWhiteSpace(core.DocumentTitle) ? core.Source : core.DocumentTitle, core.Source);
            }
        });

        core.Navigate(NormalizeUrl(url));
    }

    // --------------------------------------------------------- Permissions & Site Controls
    private void HandlePermissionRequest(CoreWebView2PermissionRequestedEventArgs e)
    {
        // Auto-allow Camera, Microphone, Clipboard, and Multi-Downloads immediately (and persist in profile)
        if (e.PermissionKind is CoreWebView2PermissionKind.Camera
            or CoreWebView2PermissionKind.Microphone
            or CoreWebView2PermissionKind.ClipboardRead
            or CoreWebView2PermissionKind.MultipleAutomaticDownloads)
        {
            e.State = CoreWebView2PermissionState.Allow;
            e.SavesInProfile = true;
            e.Handled = true;
            if (e.PermissionKind is CoreWebView2PermissionKind.Camera or CoreWebView2PermissionKind.Microphone &&
                Uri.TryCreate(e.Uri, UriKind.Absolute, out var pu))
            {
                string permOrigin = $"{pu.Scheme}://{pu.Authority}";
                Dispatcher.BeginInvoke(async () =>
                {
                    try
                    {
                        var ac = ActiveCore;
                        if (ac is not null)
                        {
                            string gj = JsonSerializer.Serialize(new { origin = permOrigin, permissions = new[] { "videoCapture", "audioCapture" } });
                            await ac.CallDevToolsProtocolMethodAsync("Browser.grantPermissions", gj);
                        }
                    }
                    catch { }
                });
            }
            Dispatcher.BeginInvoke(() =>
            {
                string host = Uri.TryCreate(e.Uri, UriKind.Absolute, out var u) ? u.Host : e.Uri;
                StatusText.Text = $"Permission granted ({e.PermissionKind}) for {host}";
            });
            return;
        }

        // For Geolocation / Notifications / other prompts, show an interactive dark Permission Prompt Bar
        try
        {
            var deferral = e.GetDeferral();
            e.Handled = true;
            Dispatcher.BeginInvoke(() =>
            {
                // Complete any previous unanswered prompt safely
                if (_pendingPermDeferral is not null)
                {
                    try { _pendingPermDeferral.Complete(); } catch { }
                    _pendingPermDeferral = null;
                    _pendingPermArgs = null;
                }
                _pendingPermArgs = e;
                _pendingPermDeferral = deferral;
                string host = Uri.TryCreate(e.Uri, UriKind.Absolute, out var u) ? u.Host : e.Uri;
                PermissionPromptText.Text = $"{host} wants permission: {e.PermissionKind}";
                PermissionPromptBar.Visibility = Visibility.Visible;
            });
        }
        catch
        {
            e.State = CoreWebView2PermissionState.Allow;
            e.Handled = true;
        }
    }

    private void BtnPermPromptAllow_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingPermArgs is not null)
        {
            _pendingPermArgs.State = CoreWebView2PermissionState.Allow;
            _pendingPermArgs.SavesInProfile = true;
        }
        try { _pendingPermDeferral?.Complete(); } catch { }
        _pendingPermDeferral = null;
        _pendingPermArgs = null;
        PermissionPromptBar.Visibility = Visibility.Collapsed;
    }

    private void BtnPermPromptDeny_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingPermArgs is not null)
        {
            _pendingPermArgs.State = CoreWebView2PermissionState.Deny;
            _pendingPermArgs.SavesInProfile = true;
        }
        try { _pendingPermDeferral?.Complete(); } catch { }
        _pendingPermDeferral = null;
        _pendingPermArgs = null;
        PermissionPromptBar.Visibility = Visibility.Collapsed;
    }

    private string GetCurrentOrigin()
    {
        var url = ActiveCore?.Source ?? UrlBox.Text;
        if (Uri.TryCreate(url, UriKind.Absolute, out var u) && (u.Scheme == "http" || u.Scheme == "https"))
            return $"{u.Scheme}://{u.Authority}";
        return "";
    }

    private async void BtnSitePermissions_Click(object sender, RoutedEventArgs e)
    {
        if (SitePermissionsBar.Visibility == Visibility.Visible)
        {
            SitePermissionsBar.Visibility = Visibility.Collapsed;
            return;
        }
        string origin = GetCurrentOrigin();
        SitePermissionsOriginText.Text = string.IsNullOrEmpty(origin)
            ? "Site Permissions (open an https:// site first)"
            : $"Site: {origin} (checking camera/mic...)";
        SitePermissionsBar.Visibility = Visibility.Visible;
        await RefreshSitePermissionsAndDevicesAsync();
    }

    private async Task RefreshSitePermissionsAndDevicesAsync()
    {
        var core = ActiveCore;
        string origin = GetCurrentOrigin();
        var cams = new List<string> { "Auto (Default Camera)" };
        var mics = new List<string> { "Auto (Default Microphone)" };
        string camState = "allow", micState = "allow";

        if (core is not null)
        {
            try
            {
                string probeJs = @"(async () => {
                    let camPerm = 'unknown', micPerm = 'unknown';
                    try { camPerm = (await navigator.permissions.query({name:'camera'})).state; } catch {}
                    try { micPerm = (await navigator.permissions.query({name:'microphone'})).state; } catch {}
                    const devs = navigator.mediaDevices && navigator.mediaDevices.enumerateDevices
                        ? await navigator.mediaDevices.enumerateDevices() : [];
                    return {
                        camPerm, micPerm,
                        cams: devs.filter(d => d.kind === 'videoinput').map((d, i) => d.label || ('Camera #' + (i + 1))),
                        mics: devs.filter(d => d.kind === 'audioinput').map((d, i) => d.label || ('Microphone #' + (i + 1)))
                    };
                })()";
                string evalPayload = JsonSerializer.Serialize(new
                {
                    expression = probeJs,
                    awaitPromise = true,
                    returnByValue = true
                });
                string raw = await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", evalPayload);
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.TryGetProperty("result", out var resObj) &&
                    resObj.TryGetProperty("value", out var root) &&
                    root.ValueKind == JsonValueKind.Object)
                {
                    if (root.TryGetProperty("camPerm", out var cp)) camState = cp.GetString() ?? camState;
                    if (root.TryGetProperty("micPerm", out var mp)) micState = mp.GetString() ?? micState;
                    if (root.TryGetProperty("cams", out var cArr) && cArr.ValueKind == JsonValueKind.Array)
                        foreach (var c in cArr.EnumerateArray())
                        {
                            var lbl = c.GetString();
                            if (!string.IsNullOrWhiteSpace(lbl) && !cams.Contains(lbl)) cams.Add(lbl);
                        }
                    if (root.TryGetProperty("mics", out var mArr) && mArr.ValueKind == JsonValueKind.Array)
                        foreach (var m in mArr.EnumerateArray())
                        {
                            var lbl = m.GetString();
                            if (!string.IsNullOrWhiteSpace(lbl) && !mics.Contains(lbl)) mics.Add(lbl);
                        }
                }
            }
            catch { }
        }

        SitePermissionsOriginText.Text = string.IsNullOrEmpty(origin)
            ? $"Media Devices ({cams.Count - 1} cam, {mics.Count - 1} mic)"
            : $"{origin}  |  Cam: {camState.ToUpperInvariant()} ({cams.Count - 1} found)  |  Mic: {micState.ToUpperInvariant()}";

        CbSiteCamera.ItemsSource = cams;
        int camIdx = string.IsNullOrWhiteSpace(_profile.PreferredCameraLabel)
            ? 0
            : cams.FindIndex(c => c.Equals(_profile.PreferredCameraLabel, StringComparison.OrdinalIgnoreCase));
        CbSiteCamera.SelectedIndex = camIdx >= 0 ? camIdx : 0;

        CbSiteMic.ItemsSource = mics;
        int micIdx = string.IsNullOrWhiteSpace(_profile.PreferredMicLabel)
            ? 0
            : mics.FindIndex(m => m.Equals(_profile.PreferredMicLabel, StringComparison.OrdinalIgnoreCase));
        CbSiteMic.SelectedIndex = micIdx >= 0 ? micIdx : 0;
    }

    private async void BtnApplyMediaDevices_Click(object sender, RoutedEventArgs e)
    {
        string selCam = CbSiteCamera.SelectedIndex > 0 ? (CbSiteCamera.SelectedItem?.ToString() ?? "") : "";
        string selMic = CbSiteMic.SelectedIndex > 0 ? (CbSiteMic.SelectedItem?.ToString() ?? "") : "";
        _profile.PreferredCameraLabel = selCam;
        _profile.PreferredMicLabel = selMic;
        _saveStore();

        string js = $"window.__mhPreferredCam = {JsonSerializer.Serialize(selCam)}; window.__mhPreferredMic = {JsonSerializer.Serialize(selMic)};";
        foreach (var t in _tabs)
        {
            try { if (t.WebView.CoreWebView2 is not null) await t.WebView.CoreWebView2.ExecuteScriptAsync(js); } catch { }
        }

        StatusText.Text = string.IsNullOrWhiteSpace(selCam)
            ? "Camera set to Auto (Default) — reloading..."
            : $"Preferred Camera set to '{selCam}' — reloading...";
        SitePermissionsBar.Visibility = Visibility.Collapsed;
        ActiveCore?.Reload();
    }

    private void BtnSitePermissionsClose_Click(object sender, RoutedEventArgs e) =>
        SitePermissionsBar.Visibility = Visibility.Collapsed;

    private async void BtnSiteAllowCamMic_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveCore;
        string origin = GetCurrentOrigin();
        if (core is null || string.IsNullOrEmpty(origin)) return;
        try
        {
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Camera, origin, CoreWebView2PermissionState.Allow);
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Microphone, origin, CoreWebView2PermissionState.Allow);
            try
            {
                string grantJson = JsonSerializer.Serialize(new { origin, permissions = new[] { "videoCapture", "audioCapture" } });
                await core.CallDevToolsProtocolMethodAsync("Browser.grantPermissions", grantJson);
            }
            catch { }
            StatusText.Text = $"Camera & Microphone ALLOWED for {origin} — reloading...";
            SitePermissionsBar.Visibility = Visibility.Collapsed;
            core.Reload();
        }
        catch (Exception ex) { StatusText.Text = $"Permission update error: {ex.Message}"; }
    }

    private async void BtnSiteBlockCamMic_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveCore;
        string origin = GetCurrentOrigin();
        if (core is null || string.IsNullOrEmpty(origin)) return;
        try
        {
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Camera, origin, CoreWebView2PermissionState.Deny);
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Microphone, origin, CoreWebView2PermissionState.Deny);
            StatusText.Text = $"Camera & Microphone BLOCKED for {origin}";
            SitePermissionsBar.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex) { StatusText.Text = $"Permission update error: {ex.Message}"; }
    }

    private async void BtnSiteAllowLoc_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveCore;
        string origin = GetCurrentOrigin();
        if (core is null || string.IsNullOrEmpty(origin)) return;
        try
        {
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Geolocation, origin, CoreWebView2PermissionState.Allow);
            StatusText.Text = $"Location ALLOWED for {origin}";
            SitePermissionsBar.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex) { StatusText.Text = $"Permission update error: {ex.Message}"; }
    }

    private async void BtnSiteAllowNotif_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveCore;
        string origin = GetCurrentOrigin();
        if (core is null || string.IsNullOrEmpty(origin)) return;
        try
        {
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Notifications, origin, CoreWebView2PermissionState.Allow);
            StatusText.Text = $"Notifications ALLOWED for {origin}";
            SitePermissionsBar.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex) { StatusText.Text = $"Permission update error: {ex.Message}"; }
    }

    private void RefreshLiveGeoUi()
    {
        if (_geoSpoofActive)
        {
            TxtLiveLat.Text = _activeGeoLat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLiveLon.Text = _activeGeoLon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TrayGeoStatus.Text = $"Active GPS: {_activeGeoLat:F4}, {_activeGeoLon:F4} (±{_activeGeoAcc:F0}m)";
        }
        else
        {
            TrayGeoStatus.Text = "Active GPS: Not set (pick a city below)";
        }
    }

    private void CbLiveGeoPreset_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingGeoCombo || CbLiveGeoPreset.SelectedIndex < 0 || CbLiveGeoPreset.SelectedIndex >= GeoPresets.All.Length) return;
        var p = GeoPresets.All[CbLiveGeoPreset.SelectedIndex];
        if (CbLiveGeoPreset.SelectedIndex == 0 && (Math.Abs(_conn.Lat) > 0.0001 || Math.Abs(_conn.Lon) > 0.0001))
        {
            TxtLiveLat.Text = _conn.Lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLiveLon.Text = _conn.Lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
        }
        else if (Math.Abs(p.Lat) > 0.0001 || Math.Abs(p.Lon) > 0.0001)
        {
            TxtLiveLat.Text = p.Lat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
            TxtLiveLon.Text = p.Lon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture);
        }
    }

    private async void BtnApplyLiveGeo_Click(object sender, RoutedEventArgs e)
    {
        if (!double.TryParse(TxtLiveLat.Text.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double lat) ||
            !double.TryParse(TxtLiveLon.Text.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double lon))
        {
            DarkDialog.ShowInfo(this, "Location Spoofer", "Enter valid Latitude and Longitude numbers (e.g. 40.7128 and -74.0060).");
            return;
        }
        _activeGeoLat = Math.Clamp(lat, -90, 90);
        _activeGeoLon = Math.Clamp(lon, -180, 180);
        _geoSpoofActive = true;

        _profile.AutoGeolocation = CbLiveGeoPreset.SelectedIndex == 0;
        _profile.CustomGeoLat = _activeGeoLat;
        _profile.CustomGeoLon = _activeGeoLon;
        _profile.CustomGeoAccuracy = _activeGeoAcc;
        _saveStore();
        RefreshLiveGeoUi();

        string cdpPayload = JsonSerializer.Serialize(new { latitude = _activeGeoLat, longitude = _activeGeoLon, accuracy = _activeGeoAcc });
        string jsUpdate = $"window.__mhGeo = {{ enabled: true, lat: {_activeGeoLat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)}, lon: {_activeGeoLon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)}, acc: {_activeGeoAcc.ToString("F1", System.Globalization.CultureInfo.InvariantCulture)} }};";
        foreach (var t in _tabs)
        {
            try
            {
                if (t.WebView.CoreWebView2 is not null)
                {
                    await t.WebView.CoreWebView2.CallDevToolsProtocolMethodAsync("Emulation.setGeolocationOverride", cdpPayload);
                    await t.WebView.CoreWebView2.ExecuteScriptAsync(jsUpdate);
                }
            }
            catch { }
        }
        StatusText.Text = $"Spoofed GPS applied live: {_activeGeoLat:F4}, {_activeGeoLon:F4}";
    }

    private async void BtnTestGeo_Click(object sender, RoutedEventArgs e) =>
        await OpenNewTabAsync("https://browserleaks.com/geo");

    // --------------------------------------------------------- Window Sync Receiver
    public void SyncNavigateFromMaster(string url) => ActiveCore?.Navigate(url);

    public async void SyncActionFromMaster(string actionType, double x, double y, string text)
    {
        if (ActiveCore is null) return;
        try
        {
            if (actionType == "scroll")
            {
                await ActiveCore.ExecuteScriptAsync($"window.scrollTo({(int)x}, {(int)y});");
            }
            else if (actionType == "click")
            {
                var pDown = JsonSerializer.Serialize(new { type = "mousePressed", x, y, button = "left", clickCount = 1 });
                var pUp = JsonSerializer.Serialize(new { type = "mouseReleased", x, y, button = "left", clickCount = 1 });
                await ActiveCore.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent", pDown);
                await ActiveCore.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent", pUp);
            }
        }
        catch { }
    }

    private void BtnSetMasterSync_Click(object sender, RoutedEventArgs e)
    {
        WindowSyncManager.MasterWindow = this;
        WindowSyncManager.IsSyncEnabled = !WindowSyncManager.IsSyncEnabled;
        BtnSetMasterSync.Content = WindowSyncManager.IsSyncEnabled ? "Sync: MASTER ON" : "Set as Master";
        StatusText.Text = WindowSyncManager.IsSyncEnabled
            ? $"Multi-Window Sync ACTIVE (Master: {_profile.Name}, {WindowSyncManager.OpenCount} windows)"
            : "Multi-Window Sync paused.";
    }

    private void BtnTileWindows_Click(object sender, RoutedEventArgs e) => WindowSyncManager.TileWindowsGrid();

    private void BtnVCamCmd_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string cmd) return;
        VirtualCamBridge.SendCommand(cmd);
        StatusText.Text = $"Sent VirtualCam command: {cmd}";
    }

    private void BtnCopyCdp_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(TxtCdpUrl.Text);
            StatusText.Text = $"Copied CDP Automation URL: {TxtCdpUrl.Text}";
        }
        catch { }
    }

    // --------------------------------------------------------- Cookie Robot (Auto Cookie Warmer)
    private async void BtnCookieRobot_Click(object sender, RoutedEventArgs e)
    {
        if (_cookieRobotRunning)
        {
            _cookieRobotRunning = false;
            BtnCookieRobot.Content = "Run Cookie Robot";
            StatusText.Text = "Cookie Robot stopped.";
            return;
        }
        if (ActiveCore is null) return;

        _cookieRobotRunning = true;
        BtnCookieRobot.Content = "Stop Robot";
        try
        {
            int idx = 0;
            foreach (var site in CookieRobotDefaults.TrustedSites)
            {
                if (!_cookieRobotRunning || ActiveCore is null) break;
                idx++;
                StatusText.Text = $"Cookie Robot ({idx}/{CookieRobotDefaults.TrustedSites.Length}): Visiting {site}...";
                ActiveCore.Navigate(site);
                await Task.Delay(Random.Shared.Next(3200, 4800));
                if (!_cookieRobotRunning || ActiveCore is null) break;
                try
                {
                    await ActiveCore.ExecuteScriptAsync("window.scrollBy({top: 450, behavior: 'smooth'});");
                    await Task.Delay(1200);
                    await ActiveCore.ExecuteScriptAsync("window.scrollBy({top: 550, behavior: 'smooth'});");
                    await Task.Delay(1000);
                }
                catch { }
            }
            StatusText.Text = "Cookie Robot completed! Profile warmed with trusted cookies.";
        }
        finally
        {
            _cookieRobotRunning = false;
            BtnCookieRobot.Content = "Run Cookie Robot";
        }
    }

    private bool IsActiveTab(TabState tab) =>
        _activeIndex >= 0 && _activeIndex < _tabs.Count && ReferenceEquals(_tabs[_activeIndex], tab);

    private void UpdateLoadingAnimation(bool loading)
    {
        if (loading)
        {
            PageLoadBar.Visibility = Visibility.Visible;
            PageLoadBar.BeginAnimation(OpacityProperty, new DoubleAnimation(1.0, TimeSpan.FromMilliseconds(140)));
        }
        else
        {
            var fade = new DoubleAnimation(0.0, TimeSpan.FromMilliseconds(220));
            fade.Completed += (_, _) => { if (!(_activeIndex >= 0 && _activeIndex < _tabs.Count && _tabs[_activeIndex].IsLoading)) PageLoadBar.Visibility = Visibility.Collapsed; };
            PageLoadBar.BeginAnimation(OpacityProperty, fade);
        }
    }

    // --------------------------------------------------------- Cookies, Extensions & Human Paste
    private async void BtnExportCookies_Click(object sender, RoutedEventArgs e)
    {
        if (ActiveCore is null) return;
        var dlg = new SaveFileDialog
        {
            Filter = "JSON Cookies (*.json)|*.json|Netscape Cookies (*.txt)|*.txt",
            FileName = $"{_profile.Name}_cookies.json",
            Title = "Export Profile Cookies"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            int count = await CookieHelper.ExportCookiesAsync(ActiveCore.CookieManager, dlg.FileName);
            StatusText.Text = $"Exported {count} cookies to {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Cookie Export Error", ex.Message); }
    }

    private void BtnImportCookies_Click(object sender, RoutedEventArgs e)
    {
        if (ActiveCore is null) return;
        var dlg = new OpenFileDialog
        {
            Filter = "Cookies (*.json;*.txt)|*.json;*.txt|All Files|*.*",
            Title = "Import Cookies (JSON or Netscape)"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            int count = CookieHelper.ImportCookies(ActiveCore.CookieManager, dlg.FileName);
            StatusText.Text = $"Imported {count} cookies. Reload page to apply.";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Cookie Import Error", ex.Message); }
    }

    private async void BtnLoadExtLive_Click(object sender, RoutedEventArgs e)
    {
        if (ActiveCore is null) return;
        var dlg = new OpenFileDialog
        {
            Filter = "Chrome Extension (*.zip;*.crx)|*.zip;*.crx|All Files|*.*",
            Title = "Upload & Load Chrome Extension (.zip or .crx)"
        };
        if (dlg.ShowDialog() != true) return;
        await InstallAndLoadExtensionAsync(dlg.FileName);
    }

    private async void BtnLoadExtFolderLive_Click(object sender, RoutedEventArgs e)
    {
        if (ActiveCore is null) return;
        var dlg = new OpenFolderDialog { Title = "Select Unpacked Chrome Extension Folder (containing manifest.json)" };
        if (dlg.ShowDialog() != true) return;
        await InstallAndLoadExtensionAsync(dlg.FolderName);
    }

    private async Task InstallAndLoadExtensionAsync(string sourcePath)
    {
        var core = ActiveCore;
        if (core is null) return;
        var (ok, folder, msg) = ExtensionHelper.InstallExtension(sourcePath);
        if (!ok)
        {
            DarkDialog.ShowInfo(this, "Extension Error", msg);
            return;
        }
        try
        {
            var ext = await core.Profile.AddBrowserExtensionAsync(folder);
            _extIdToFolder[ext.Id] = folder;
            _profile.ExtensionPaths ??= new List<string>();
            if (!_profile.ExtensionPaths.Contains(folder))
            {
                _profile.ExtensionPaths.Add(folder);
                _saveStore();
            }
            try { await ext.EnableAsync(true); } catch { }
            await RefreshLoadedExtensionsUiAsync(core);
            StatusText.Text = $"Extension active: {ext.Name} — reloading page to inject scripts...";
            core.Reload();
        }
        catch (Exception ex)
        {
            DarkDialog.ShowInfo(this, "Extension Load Error",
                $"Chromium rejected this extension:\n{ex.Message}\n\nTip: Make sure it is a valid Manifest V3/V2 Chrome extension (unpacked folder, .zip, or .crx).");
        }
    }

    private async Task RefreshLoadedExtensionsUiAsync(CoreWebView2 core)
    {
        try
        {
            var rawList = await core.Profile.GetBrowserExtensionsAsync();
            // Hide built-in Edge system component extensions that cannot be removed
            var list = rawList.Where(x =>
                !x.Name.Equals("Microsoft Clipboard Extension", StringComparison.OrdinalIgnoreCase) &&
                !x.Name.Equals("Microsoft Edge PDF Viewer", StringComparison.OrdinalIgnoreCase)).ToList();
            Dispatcher.Invoke(() =>
            {
                LoadedExtensionsPanel.Children.Clear();
                if (list.Count == 0)
                {
                    TrayExtStatus.Text = "No user extensions loaded";
                    return;
                }
                TrayExtStatus.Text = $"{list.Count} active extension(s) — click Open for popup";
                foreach (var ext in list)
                {
                    var row = new Grid { Margin = new Thickness(0, 0, 0, 5) };
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    var nameTb = new TextBlock
                    {
                        Text = ext.Name,
                        Foreground = (Brush)FindResource("Text"),
                        FontSize = 11,
                        VerticalAlignment = VerticalAlignment.Center,
                        TextTrimming = TextTrimming.CharacterEllipsis,
                        ToolTip = $"{ext.Name} ({ext.Id})"
                    };
                    Grid.SetColumn(nameTb, 0);
                    row.Children.Add(nameTb);

                    var openBtn = new Button
                    {
                        Content = "Open",
                        Style = (Style)FindResource("FlatButton"),
                        Padding = new Thickness(7, 2, 7, 2),
                        FontSize = 10.5,
                        Margin = new Thickness(6, 0, 4, 0)
                    };
                    openBtn.Click += async (_, _) =>
                    {
                        string? page = null;
                        if (_extIdToFolder.TryGetValue(ext.Id, out var dir))
                            page = ExtensionHelper.GetPopupOrOptionsPage(dir);
                        else if (_profile.ExtensionPaths is not null)
                        {
                            foreach (var ep in _profile.ExtensionPaths)
                            {
                                if (ExtensionHelper.ReadExtensionName(ep).Equals(ext.Name, StringComparison.OrdinalIgnoreCase))
                                {
                                    page = ExtensionHelper.GetPopupOrOptionsPage(ep);
                                    break;
                                }
                            }
                        }
                        string extUrl = !string.IsNullOrWhiteSpace(page)
                            ? $"chrome-extension://{ext.Id}/{page}"
                            : $"chrome-extension://{ext.Id}/popup.html";
                        await OpenNewTabAsync(extUrl);
                    };
                    Grid.SetColumn(openBtn, 1);
                    row.Children.Add(openBtn);

                    var remBtn = new Button
                    {
                        Content = "X",
                        Style = (Style)FindResource("FlatButton"),
                        Padding = new Thickness(6, 2, 6, 2),
                        FontSize = 10.5
                    };
                    remBtn.Click += async (_, _) =>
                    {
                        remBtn.IsEnabled = false;
                        try
                        {
                            try { await ext.EnableAsync(false); } catch { }
                            await ext.RemoveAsync();

                            if (_profile.ExtensionPaths is not null)
                            {
                                if (_extIdToFolder.TryGetValue(ext.Id, out var dir))
                                {
                                    _profile.ExtensionPaths.RemoveAll(p => p.Equals(dir, StringComparison.OrdinalIgnoreCase));
                                    _extIdToFolder.Remove(ext.Id);
                                }
                                _profile.ExtensionPaths.RemoveAll(p =>
                                    ExtensionHelper.ReadExtensionName(p).Equals(ext.Name, StringComparison.OrdinalIgnoreCase));
                                _saveStore();
                            }

                            await RefreshLoadedExtensionsUiAsync(core);
                            StatusText.Text = $"Removed extension: {ext.Name}";
                        }
                        catch (Exception ex)
                        {
                            remBtn.IsEnabled = true;
                            DarkDialog.ShowInfo(this, "Remove Extension", $"Could not remove '{ext.Name}':\n{ex.Message}");
                        }
                    };
                    Grid.SetColumn(remBtn, 2);
                    row.Children.Add(remBtn);

                    LoadedExtensionsPanel.Children.Add(row);
                }
            });
        }
        catch { }
    }

    private async void BtnHumanPaste_Click(object sender, RoutedEventArgs e)
    {
        if (ActiveCore is null) return;
        string text = "";
        try { text = Clipboard.GetText(); } catch { }
        if (string.IsNullOrEmpty(text))
        {
            StatusText.Text = "Clipboard is empty.";
            return;
        }
        StatusText.Text = $"Human-typing {text.Length} characters...";
        foreach (char ch in text)
        {
            if (ch == '\r') continue;
            try
            {
                var payload = JsonSerializer.Serialize(new { type = "char", text = ch.ToString() });
                await ActiveCore.CallDevToolsProtocolMethodAsync("Input.dispatchKeyEvent", payload);
            }
            catch { break; }
            await Task.Delay(Random.Shared.Next(45, 130));
        }
        StatusText.Text = "Human paste completed.";
    }

    // --------------------------------------------------------- Bookmarks & History
    private void RecordHistory(string title, string url)
    {
        _profile.History ??= new List<HistoryItem>();
        if (_profile.History.Count > 0 && _profile.History[0].Url.Equals(url, StringComparison.OrdinalIgnoreCase))
            return;
        _profile.History.Insert(0, new HistoryItem { Title = title, Url = url, VisitedAt = DateTime.Now.ToString("HH:mm") });
        if (_profile.History.Count > 200) _profile.History.RemoveRange(200, _profile.History.Count - 200);
        _saveStore();
        RefreshHistoryUi();
    }

    private void RefreshHistoryUi()
    {
        HistoryList.ItemsSource = null;
        HistoryList.ItemsSource = _profile.History;
    }

    private void RefreshBookmarksUi()
    {
        _profile.Bookmarks ??= new List<BookmarkItem>();
        BookmarksList.ItemsSource = null;
        BookmarksList.ItemsSource = _profile.Bookmarks;

        BookmarksBarPanel.Children.Clear();
        foreach (var bm in _profile.Bookmarks)
        {
            var item = bm;
            var btn = new Button
            {
                Style = (Style)FindResource("FlatButton"),
                Padding = new Thickness(9, 3, 9, 3),
                Margin = new Thickness(0, 0, 6, 0),
                FontSize = 11.5,
                Content = item.Title.Length > 22 ? item.Title[..22] + "..." : item.Title,
                ToolTip = item.Url
            };
            btn.Click += (_, _) => NavigateCurrent(item.Url);
            BookmarksBarPanel.Children.Add(btn);
        }
        BookmarksBarBorder.Visibility = _profile.Bookmarks.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        UpdateBookmarkStarState();
    }

    private void UpdateBookmarkStarState()
    {
        string url = (_activeIndex >= 0 && _activeIndex < _tabs.Count) ? _tabs[_activeIndex].Url : "";
        bool isBookmarked = !string.IsNullOrWhiteSpace(url) &&
                            _profile.Bookmarks.Any(b => b.Url.Equals(url, StringComparison.OrdinalIgnoreCase));
        BookmarkStarIcon.Fill = (Brush)FindResource(isBookmarked ? "Accent" : "Muted");
    }

    private void BtnToggleBookmark_Click(object sender, RoutedEventArgs e)
    {
        if (_activeIndex < 0 || _activeIndex >= _tabs.Count) return;
        var tab = _tabs[_activeIndex];
        if (string.IsNullOrWhiteSpace(tab.Url)) return;

        var existing = _profile.Bookmarks.FirstOrDefault(b => b.Url.Equals(tab.Url, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            _profile.Bookmarks.Remove(existing);
            StatusText.Text = $"Removed bookmark: {existing.Title}";
        }
        else
        {
            _profile.Bookmarks.Insert(0, new BookmarkItem { Title = string.IsNullOrWhiteSpace(tab.Title) ? tab.Url : tab.Title, Url = tab.Url });
            StatusText.Text = $"Bookmarked: {tab.Title}";
        }
        _saveStore();
        RefreshBookmarksUi();
    }

    private void BtnRemoveBookmark_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BookmarkItem bm) return;
        _profile.Bookmarks.Remove(bm);
        _saveStore();
        RefreshBookmarksUi();
    }

    private void BookmarkItem_Click(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is BookmarkItem bm) NavigateCurrent(bm.Url);
    }

    private void HistoryItem_Click(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is HistoryItem h) NavigateCurrent(h.Url);
    }

    private void BtnClearHistory_Click(object sender, RoutedEventArgs e)
    {
        _profile.History.Clear();
        _saveStore();
        RefreshHistoryUi();
        StatusText.Text = "Browsing history cleared.";
    }

    private void BtnToggleTray_Click(object sender, RoutedEventArgs e)
    {
        _trayOpen = !_trayOpen;
        var anim = new DoubleAnimation(_trayOpen ? 324 : 0, TimeSpan.FromMilliseconds(200))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        SideTray.BeginAnimation(WidthProperty, anim);
    }

    private void SetTrayTab(string tab)
    {
        TrayToolsPanel.Visibility = tab == "Tools" ? Visibility.Visible : Visibility.Collapsed;
        TrayBookmarksPanel.Visibility = tab == "Bookmarks" ? Visibility.Visible : Visibility.Collapsed;
        TrayHistoryPanel.Visibility = tab == "History" ? Visibility.Visible : Visibility.Collapsed;
        var accent = (Style)FindResource("AccentButton");
        var flat = (Style)FindResource("FlatButton");
        TrayTabTools.Style = tab == "Tools" ? accent : flat;
        TrayTabBookmarks.Style = tab == "Bookmarks" ? accent : flat;
        TrayTabHistory.Style = tab == "History" ? accent : flat;
    }

    private async Task AttachInspectorToTabAsync(TabState tab)
    {
        if (tab.InspectorAttached) return;
        var core = tab.WebView.CoreWebView2;
        if (core is null) return;
        tab.InspectorAttached = true;
        // Live Reqable/Fiddler-style CDP Network & API Capture
        try
        {
            await core.CallDevToolsProtocolMethodAsync("Network.enable", "{}");
            var reqRecv = core.GetDevToolsProtocolEventReceiver("Network.requestWillBeSent");
            reqRecv.DevToolsProtocolEventReceived += (_, ev) =>
            {
                if (_inspectorWindow is not null && !_inspectorWindow.IsCapturing) return;
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var root = doc.RootElement;
                    string reqId = root.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    string resType = root.TryGetProperty("type", out var tEl) ? (tEl.GetString() ?? "") : "";
                    if (!root.TryGetProperty("request", out var reqEl)) return;
                    string rUrl = reqEl.TryGetProperty("url", out var uEl) ? (uEl.GetString() ?? "") : "";
                    if (rUrl.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) return;
                    string method = reqEl.TryGetProperty("method", out var mEl) ? (mEl.GetString() ?? "GET") : "GET";
                    string postData = reqEl.TryGetProperty("postData", out var pEl) ? (pEl.GetString() ?? "") : "";
                    string reqHeaders = reqEl.TryGetProperty("headers", out var hEl) ? FormatHeaders(hEl) : "";

                    string gqlOp = "";
                    if (!string.IsNullOrEmpty(postData) && postData.Contains("operationName", StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            using var pd = JsonDocument.Parse(postData);
                            if (pd.RootElement.TryGetProperty("operationName", out var opEl))
                                gqlOp = opEl.GetString() ?? "";
                        }
                        catch { }
                    }

                    var item = new CapturedNetRequest
                    {
                        RequestId = reqId,
                        Time = DateTime.Now.ToString("HH:mm:ss"),
                        Method = method,
                        Url = rUrl,
                        ResourceType = resType,
                        GraphQlOp = gqlOp,
                        StartTickMs = Environment.TickCount64,
                        RequestHeaders = reqHeaders,
                        PostData = postData
                    };
                    Dispatcher.BeginInvoke(() =>
                    {
                        _netById[reqId] = item;
                        _capturedNet.Insert(0, item);
                        if (_capturedNet.Count > 800) _capturedNet.RemoveAt(_capturedNet.Count - 1);
                        TrayInspectorCount.Text = $"Captured: {_capturedNet.Count} API/WS | {_recordedUi.Count} UI actions";
                    });
                }
                catch { }
            };

            var respRecv = core.GetDevToolsProtocolEventReceiver("Network.responseReceived");
            respRecv.DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var root = doc.RootElement;
                    string reqId = root.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    if (!root.TryGetProperty("response", out var respEl)) return;
                    int status = respEl.TryGetProperty("status", out var sEl) ? sEl.GetInt32() : 0;
                    string proto = respEl.TryGetProperty("protocol", out var prEl) ? (prEl.GetString() ?? "") : "";
                    string rip = respEl.TryGetProperty("remoteIPAddress", out var ipEl) ? (ipEl.GetString() ?? "") : "";
                    long encLen = respEl.TryGetProperty("encodedDataLength", out var szEl) ? szEl.GetInt64() : 0;
                    string respHeaders = respEl.TryGetProperty("headers", out var hEl) ? FormatHeaders(hEl) : "";
                    bool fromDisk = respEl.TryGetProperty("fromDiskCache", out var fdEl) && fdEl.ValueKind == JsonValueKind.True;
                    bool fromSw = respEl.TryGetProperty("fromServiceWorker", out var swEl) && swEl.ValueKind == JsonValueKind.True;

                    string tlsInfo = "";
                    if (respEl.TryGetProperty("securityDetails", out var secEl) && secEl.ValueKind == JsonValueKind.Object)
                    {
                        string tp = secEl.TryGetProperty("protocol", out var p1) ? (p1.GetString() ?? "") : "";
                        string tc = secEl.TryGetProperty("cipher", out var c1) ? (c1.GetString() ?? "") : "";
                        string subj = secEl.TryGetProperty("subjectName", out var s1) ? (s1.GetString() ?? "") : "";
                        string iss = secEl.TryGetProperty("issuer", out var i1) ? (i1.GetString() ?? "") : "";
                        tlsInfo = $"Protocol: {tp} | Cipher: {tc}\nSubject (SNI): {subj} | Issuer: {iss}";
                    }

                    string timingInfo = "";
                    if (respEl.TryGetProperty("timing", out var tmEl) && tmEl.ValueKind == JsonValueKind.Object)
                    {
                        double dns = (tmEl.TryGetProperty("dnsEnd", out var de) && tmEl.TryGetProperty("dnsStart", out var ds) && de.GetDouble() >= 0 && ds.GetDouble() >= 0) ? (de.GetDouble() - ds.GetDouble()) : 0;
                        double tcp = (tmEl.TryGetProperty("connectEnd", out var ce) && tmEl.TryGetProperty("connectStart", out var cs) && ce.GetDouble() >= 0 && cs.GetDouble() >= 0) ? (ce.GetDouble() - cs.GetDouble()) : 0;
                        double ssl = (tmEl.TryGetProperty("sslEnd", out var se) && tmEl.TryGetProperty("sslStart", out var ss) && se.GetDouble() >= 0 && ss.GetDouble() >= 0) ? (se.GetDouble() - ss.GetDouble()) : 0;
                        double ttfb = tmEl.TryGetProperty("receiveHeadersEnd", out var rhe) ? Math.Max(0, rhe.GetDouble()) : 0;
                        timingInfo = $"DNS: {dns:F1} ms | TCP: {tcp:F1} ms | TLS: {ssl:F1} ms | TTFB: {ttfb:F1} ms";
                    }

                    Dispatcher.BeginInvoke(() =>
                    {
                        if (_netById.TryGetValue(reqId, out var existing))
                        {
                            existing.StatusCode = status;
                            existing.Protocol = proto;
                            existing.RemoteIp = rip;
                            if (fromSw) existing.CacheSource = "SW";
                            else if (fromDisk) existing.CacheSource = "DISK";
                            if (!string.IsNullOrEmpty(tlsInfo)) existing.TlsInfo = tlsInfo;
                            if (!string.IsNullOrEmpty(timingInfo)) existing.TimingBreakdown = timingInfo;
                            if (encLen > 0) existing.SizeBytes = encLen;
                            existing.DurationMs = Math.Max(1, Environment.TickCount64 - existing.StartTickMs);
                            existing.ResponseHeaders = respHeaders;
                            existing.NotifyUpdate();
                        }
                    });
                }
                catch { }
            };

            var finRecv = core.GetDevToolsProtocolEventReceiver("Network.loadingFinished");
            finRecv.DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var root = doc.RootElement;
                    string reqId = root.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    long len = root.TryGetProperty("encodedDataLength", out var lEl) ? lEl.GetInt64() : 0;
                    Dispatcher.BeginInvoke(() =>
                    {
                        if (_netById.TryGetValue(reqId, out var existing))
                        {
                            if (len > 0) existing.SizeBytes = len;
                            existing.DurationMs = Math.Max(1, Environment.TickCount64 - existing.StartTickMs);
                            existing.NotifyUpdate();
                        }
                    });
                }
                catch { }
            };

            var failRecv = core.GetDevToolsProtocolEventReceiver("Network.loadingFailed");
            failRecv.DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var root = doc.RootElement;
                    string reqId = root.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    string err = root.TryGetProperty("errorText", out var eEl) ? (eEl.GetString() ?? "Failed") : "Failed";
                    Dispatcher.BeginInvoke(() =>
                    {
                        if (_netById.TryGetValue(reqId, out var existing))
                        {
                            existing.ErrorText = err;
                            existing.NotifyUpdate();
                        }
                    });
                }
                catch { }
            };

            // WebSocket Frames Capture (WS SEND / WS RECV)
            var wsUrls = new Dictionary<string, string>();
            var wsCreated = core.GetDevToolsProtocolEventReceiver("Network.webSocketCreated");
            wsCreated.DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    string id = doc.RootElement.GetProperty("requestId").GetString() ?? "";
                    string u = doc.RootElement.GetProperty("url").GetString() ?? "";
                    lock (wsUrls) wsUrls[id] = u;
                }
                catch { }
            };

            void HandleWsFrame(string dir, string json)
            {
                if (_inspectorWindow is not null && !_inspectorWindow.IsCapturing) return;
                try
                {
                    using var doc = JsonDocument.Parse(json);
                    string id = doc.RootElement.GetProperty("requestId").GetString() ?? "";
                    string payload = doc.RootElement.GetProperty("response").GetProperty("payloadData").GetString() ?? "";
                    string wsUrl;
                    lock (wsUrls) wsUrl = wsUrls.TryGetValue(id, out var u) ? u : "wss://websocket";
                    var wsItem = new CapturedNetRequest
                    {
                        Time = DateTime.Now.ToString("HH:mm:ss"),
                        Method = dir,
                        Url = wsUrl,
                        ResourceType = "WebSocket",
                        SizeBytes = payload.Length,
                        PostData = dir == "WS SEND" ? payload : "",
                        ResponseBody = dir == "WS RECV" ? payload : ""
                    };
                    Dispatcher.BeginInvoke(() =>
                    {
                        _capturedNet.Insert(0, wsItem);
                        if (_capturedNet.Count > 800) _capturedNet.RemoveAt(_capturedNet.Count - 1);
                    });
                }
                catch { }
            }

            core.GetDevToolsProtocolEventReceiver("Network.webSocketFrameSent").DevToolsProtocolEventReceived += (_, ev) => HandleWsFrame("WS SEND", ev.ParameterObjectAsJson);
            core.GetDevToolsProtocolEventReceiver("Network.webSocketFrameReceived").DevToolsProtocolEventReceived += (_, ev) => HandleWsFrame("WS RECV", ev.ParameterObjectAsJson);

            // Unredacted Request Headers (Cookie / Authorization)
            core.GetDevToolsProtocolEventReceiver("Network.requestWillBeSentExtraInfo").DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var r = doc.RootElement;
                    string id = r.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    string hdrs = r.TryGetProperty("headers", out var hEl) ? FormatHeaders(hEl) : "";
                    Dispatcher.BeginInvoke(() => { if (_netById.TryGetValue(id, out var ex)) ex.UnredactedReqHeaders = hdrs; });
                }
                catch { }
            };

            // Unredacted Response Headers (Set-Cookie) + SameSite Blocked Cookies
            core.GetDevToolsProtocolEventReceiver("Network.responseReceivedExtraInfo").DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var r = doc.RootElement;
                    string id = r.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    string hdrs = r.TryGetProperty("headers", out var hEl) ? FormatHeaders(hEl) : "";
                    string blocked = "";
                    if (r.TryGetProperty("blockedCookies", out var bcEl) && bcEl.ValueKind == JsonValueKind.Array && bcEl.GetArrayLength() > 0)
                    {
                        var bsb = new StringBuilder();
                        foreach (var bc in bcEl.EnumerateArray())
                        {
                            string reasons = bc.TryGetProperty("blockedReasons", out var br) ? br.ToString() : "";
                            string line = bc.TryGetProperty("cookieLine", out var cl) ? (cl.GetString() ?? "") : "";
                            bsb.AppendLine($"Blocked {reasons}: {line}");
                        }
                        blocked = bsb.ToString().TrimEnd();
                        AddInternalEvent("SAMESITE", id, blocked);
                    }
                    Dispatcher.BeginInvoke(() =>
                    {
                        if (_netById.TryGetValue(id, out var ex))
                        {
                            ex.UnredactedRespHeaders = hdrs;
                            if (!string.IsNullOrEmpty(blocked)) ex.BlockedCookiesInfo = blocked;
                        }
                    });
                }
                catch { }
            };

            // Memory Cache (RAM) hits
            core.GetDevToolsProtocolEventReceiver("Network.requestServedFromCache").DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    string id = doc.RootElement.TryGetProperty("requestId", out var idEl) ? (idEl.GetString() ?? "") : "";
                    Dispatcher.BeginInvoke(() =>
                    {
                        if (_netById.TryGetValue(id, out var ex)) { ex.CacheSource = "RAM"; ex.NotifyUpdate(); }
                    });
                }
                catch { }
            };

            // Server-Sent Events (SSE)
            core.GetDevToolsProtocolEventReceiver("Network.eventSourceMessageReceived").DevToolsProtocolEventReceived += (_, ev) =>
            {
                if (_inspectorWindow is not null && !_inspectorWindow.IsCapturing) return;
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    var r = doc.RootElement;
                    string evName = r.TryGetProperty("eventName", out var en) ? (en.GetString() ?? "message") : "message";
                    string data = r.TryGetProperty("data", out var dt) ? (dt.GetString() ?? "") : "";
                    var sseItem = new CapturedNetRequest
                    {
                        Time = DateTime.Now.ToString("HH:mm:ss"),
                        Method = "SSE",
                        Url = $"sse://{evName}",
                        ResourceType = "EventSource",
                        SizeBytes = data.Length,
                        ResponseBody = data
                    };
                    Dispatcher.BeginInvoke(() =>
                    {
                        _capturedNet.Insert(0, sseItem);
                        if (_capturedNet.Count > 800) _capturedNet.RemoveAt(_capturedNet.Count - 1);
                    });
                }
                catch { }
            };

            // Browser Security Audits (CORS, CSP, Mixed Content, SameSite, SRI)
            await core.CallDevToolsProtocolMethodAsync("Audits.enable", "{}");
            core.GetDevToolsProtocolEventReceiver("Audits.issueAdded").DevToolsProtocolEventReceived += (_, ev) =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(ev.ParameterObjectAsJson);
                    if (doc.RootElement.TryGetProperty("issue", out var iss))
                    {
                        string code = iss.TryGetProperty("code", out var cEl) ? (cEl.GetString() ?? "AUDIT") : "AUDIT";
                        string details = iss.TryGetProperty("details", out var dEl) ? dEl.ToString() : "";
                        AddInternalEvent(code.ToUpperInvariant(), tab.Url, details.Length > 260 ? details[..260] + "..." : details);
                    }
                }
                catch { }
            };
        }
        catch { }

        // Receive Master window sync events AND UI Action Recorder events from JS
        core.WebMessageReceived += (_, e) =>
        {
            try
            {
                using var doc = JsonDocument.Parse(e.WebMessageAsJson);
                var root = doc.RootElement;
                string type = root.TryGetProperty("type", out var tEl) ? (tEl.GetString() ?? "") : "";
                if (type == "internal_event")
                {
                    string cat = root.TryGetProperty("category", out var cEl) ? (cEl.GetString() ?? "EVENT") : "EVENT";
                    string srcUrl = root.TryGetProperty("source", out var sEl) ? (sEl.GetString() ?? "") : "";
                    string det = root.TryGetProperty("detail", out var dEl) ? (dEl.GetString() ?? "") : "";
                    AddInternalEvent(cat, srcUrl, det);
                    return;
                }
                if (type == "ui_action")
                {
                    if (_inspectorWindow is not null && !_inspectorWindow.IsCapturing) return;
                    var act = new RecordedUiAction
                    {
                        Time = DateTime.Now.ToString("HH:mm:ss"),
                        Action = root.TryGetProperty("action", out var aEl) ? (aEl.GetString() ?? "") : "",
                        Tag = root.TryGetProperty("tag", out var tgEl) ? (tgEl.GetString() ?? "") : "",
                        Selector = root.TryGetProperty("selector", out var sEl) ? (sEl.GetString() ?? "") : "",
                        XPath = root.TryGetProperty("xpath", out var xpEl) ? (xpEl.GetString() ?? "") : "",
                        FullXPath = root.TryGetProperty("fullXpath", out var fxpEl) ? (fxpEl.GetString() ?? "") : "",
                        ElementId = root.TryGetProperty("id", out var eidEl) ? (eidEl.GetString() ?? "") : "",
                        ElementName = root.TryGetProperty("name", out var enEl) ? (enEl.GetString() ?? "") : "",
                        AriaLabel = root.TryGetProperty("aria", out var arEl) ? (arEl.GetString() ?? "") : "",
                        DataTestId = root.TryGetProperty("testid", out var dtEl) ? (dtEl.GetString() ?? "") : "",
                        Bounds = root.TryGetProperty("bounds", out var bEl) ? (bEl.GetString() ?? "") : "",
                        Value = root.TryGetProperty("value", out var vEl) ? (vEl.GetString() ?? "") : "",
                        PageUrl = root.TryGetProperty("url", out var uEl) ? (uEl.GetString() ?? "") : ""
                    };
                    Dispatcher.BeginInvoke(() =>
                    {
                        _recordedUi.Insert(0, act);
                        if (_recordedUi.Count > 400) _recordedUi.RemoveAt(_recordedUi.Count - 1);
                        TrayInspectorCount.Text = $"Captured: {_capturedNet.Count} API/Net | {_recordedUi.Count} UI actions";
                    });
                    return;
                }
                if (!WindowSyncManager.IsSyncEnabled || !ReferenceEquals(WindowSyncManager.MasterWindow, this)) return;
                double x = root.TryGetProperty("x", out var xe) ? xe.GetDouble() : 0;
                double y = root.TryGetProperty("y", out var ye) ? ye.GetDouble() : 0;
                WindowSyncManager.BroadcastAction(this, type, x, y);
            }
            catch { }
        };

    }

    private async void BtnOpenInspector_Click(object sender, RoutedEventArgs e)
    {
        if (_inspectorWindow is not null && _inspectorWindow.IsLoaded)
        {
            _inspectorWindow.Activate();
            return;
        }
        _inspectorWindow = new InspectorWindow(_profile.Name, _capturedNet, _recordedUi, _internalEvents, FetchResponseBodyAsync);
        _inspectorWindow.Closed += (_, _) => _inspectorWindow = null;
        _inspectorWindow.Show();
        foreach (var t in _tabs.ToList())
            await AttachInspectorToTabAsync(t);
    }

    private async Task<string> FetchResponseBodyAsync(string requestId)
    {
        if (ActiveCore is null) return "";
        try
        {
            var res = await ActiveCore.CallDevToolsProtocolMethodAsync("Network.getResponseBody", JsonSerializer.Serialize(new { requestId }));
            using var doc = JsonDocument.Parse(res);
            if (doc.RootElement.TryGetProperty("body", out var bEl))
                return bEl.GetString() ?? "";
        }
        catch { }
        return "(Response body not available or binary)";
    }

    private void AddInternalEvent(string category, string source, string detail)
    {
        if (_inspectorWindow is not null && !_inspectorWindow.IsCapturing) return;
        Dispatcher.BeginInvoke(() =>
        {
            _internalEvents.Insert(0, new InternalSecurityEvent
            {
                Time = DateTime.Now.ToString("HH:mm:ss"),
                Category = category,
                Source = source,
                Detail = detail
            });
            if (_internalEvents.Count > 500) _internalEvents.RemoveAt(_internalEvents.Count - 1);
        });
    }

    private static string FormatHeaders(JsonElement headersEl)
    {
        var sb = new StringBuilder();
        if (headersEl.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in headersEl.EnumerateObject())
                sb.AppendLine($"{prop.Name}: {prop.Value}");
        }
        return sb.ToString().TrimEnd();
    }

    private void TrayTabTools_Click(object sender, RoutedEventArgs e) => SetTrayTab("Tools");
    private void TrayTabBookmarks_Click(object sender, RoutedEventArgs e) { RefreshBookmarksUi(); SetTrayTab("Bookmarks"); }
    private void TrayTabHistory_Click(object sender, RoutedEventArgs e) { RefreshHistoryUi(); SetTrayTab("History"); }

    private void CbSearchEngine_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingEngineCombo || CbSearchEngine.SelectedIndex < 0) return;
        _profile.SearchEngine = SearchEngines.All[CbSearchEngine.SelectedIndex].Name;
        _saveStore();
        StatusText.Text = $"Default search engine set to {_profile.SearchEngine}";
    }

    // --------------------------------------------------------- 12-Layer Ultra Antidetect Fingerprint + Sync Hooks
    private string BuildFingerprintScript()
    {
        var plat = JsonSerializer.Serialize(_profile.Platform);
        var lang = JsonSerializer.Serialize(_profile.Language);
        var webglVendor = JsonSerializer.Serialize(string.IsNullOrWhiteSpace(_profile.WebGlVendor) ? "Google Inc. (NVIDIA)" : _profile.WebGlVendor);
        var webglRenderer = JsonSerializer.Serialize(string.IsNullOrWhiteSpace(_profile.WebGlRenderer) ? "ANGLE (NVIDIA, NVIDIA GeForce RTX 4060 Direct3D11 vs_5_0 ps_5_0, D3D11)" : _profile.WebGlRenderer);
        var exitIpJson = JsonSerializer.Serialize(_conn.ExitIp ?? "");
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
        double batLevel = Math.Round(0.55 + ((seed % 40) / 100.0), 2);
        string batCharging = _profile.IsMobile ? ((seed % 2 == 0) ? "true" : "false") : "true";

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

        string webglAndWebGpuBlock = _profile.WebGlSpoof ? $@"
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
  if (navigator.gpu && navigator.gpu.requestAdapter) {{
    const origReq = navigator.gpu.requestAdapter.bind(navigator.gpu);
    navigator.gpu.requestAdapter = async (...a) => {{
      const ad = await origReq(...a);
      if (ad) {{
        try {{
          Object.defineProperty(ad, 'info', {{
            get: () => ({{ vendor: {webglVendor}, architecture: 'common-3', device: '', description: {webglRenderer} }})
          }});
        }} catch (e) {{}}
      }}
      return ad;
    }};
  }}
}} catch (e) {{}}" : "";

        string audioBlock = _profile.AudioNoise ? $@"
try {{
  const aSeed = (({seed} % 97) + 1) * 1e-7;
  const origGetChannelData = AudioBuffer.prototype.getChannelData;
  AudioBuffer.prototype.getChannelData = function(channel) {{
    const data = origGetChannelData.call(this, channel);
    if (data && data.length > 0 && !data.__mhPatched) {{
      for (let i = 0; i < Math.min(data.length, 64); i += 16) data[i] = data[i] + aSeed;
      Object.defineProperty(data, '__mhPatched', {{ value: true }});
    }}
    return data;
  }};
}} catch (e) {{}}" : "";

        string clientRectsBlock = _profile.ClientRectsNoise ? $@"
try {{
  const rDelta = (({seed} % 7) + 1) * 0.00013;
  const origRect = Element.prototype.getBoundingClientRect;
  Element.prototype.getBoundingClientRect = function() {{
    const r = origRect.apply(this, arguments);
    return new DOMRect(r.x + rDelta, r.y + rDelta, r.width + rDelta, r.height + rDelta);
  }};
  const origRangeRect = Range.prototype.getBoundingClientRect;
  Range.prototype.getBoundingClientRect = function() {{
    const r = origRangeRect.apply(this, arguments);
    return new DOMRect(r.x + rDelta, r.y + rDelta, r.width + rDelta, r.height + rDelta);
  }};
}} catch (e) {{}}" : "";

        string fontBlock = _profile.FontMasking ? $@"
try {{
  const fDelta = (({seed} % 5) + 1) * 0.0011;
  const origMeasure = CanvasRenderingContext2D.prototype.measureText;
  CanvasRenderingContext2D.prototype.measureText = function(text) {{
    const m = origMeasure.apply(this, arguments);
    return new Proxy(m, {{
      get(target, prop) {{
        if (prop === 'width') return target.width + fDelta;
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }}
    }});
  }};
}} catch (e) {{}}" : "";

        string webrtcSpoofBlock = (_profile.WebRtcSpoofPublicIp && !string.IsNullOrWhiteSpace(_conn.ExitIp)) ? $@"
try {{
  const spoofIp = {exitIpJson};
  const OrigPC = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (OrigPC && spoofIp) {{
    const rewriteSdp = (sdp) => sdp ? sdp.replace(/(c=IN IP4 )([0-9.]+)/g, '$1' + spoofIp).replace(/(candidate:\S+ \d+ \S+ \d+ )([0-9.]+)/g, '$1' + spoofIp) : sdp;
    window.RTCPeerConnection = function(cfg, constraints) {{
      const pc = new OrigPC(cfg, constraints);
      const origCreateOffer = pc.createOffer.bind(pc);
      pc.createOffer = async (...a) => {{
        const offer = await origCreateOffer(...a);
        if (offer && offer.sdp) offer.sdp = rewriteSdp(offer.sdp);
        return offer;
      }};
      return pc;
    }};
    window.RTCPeerConnection.prototype = OrigPC.prototype;
  }}
}} catch (e) {{}}" : "";

        string prefCamJson = JsonSerializer.Serialize(_profile.PreferredCameraLabel ?? "");
        string prefMicJson = JsonSerializer.Serialize(_profile.PreferredMicLabel ?? "");
        string spoofMediaFlag = _profile.MediaDeviceSpoof ? "true" : "false";
        string mediaBlock = $@"
try {{
  window.__mhPreferredCam = {prefCamJson};
  window.__mhPreferredMic = {prefMicJson};
  if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {{
    const origEnum = navigator.mediaDevices.enumerateDevices.bind(navigator.mediaDevices);
    const origGUM = navigator.mediaDevices.getUserMedia ? navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices) : null;
    const sHex = '{seed:x8}';
    const spoofIds = {spoofMediaFlag};
    const fakeToReal = new Map();
    const mapConstraint = (track) => {{
      if (!track || typeof track !== 'object' || !track.deviceId) return track;
      const copy = Object.assign({{}}, track);
      const dev = copy.deviceId;
      if (typeof dev === 'string' && fakeToReal.has(dev)) copy.deviceId = fakeToReal.get(dev);
      else if (dev && typeof dev === 'object') {{
        const dCopy = Object.assign({{}}, dev);
        if (typeof dCopy.exact === 'string' && fakeToReal.has(dCopy.exact)) dCopy.exact = fakeToReal.get(dCopy.exact);
        if (typeof dCopy.ideal === 'string' && fakeToReal.has(dCopy.ideal)) dCopy.ideal = fakeToReal.get(dCopy.ideal);
        copy.deviceId = dCopy;
      }}
      return copy;
    }};
    navigator.mediaDevices.enumerateDevices = async () => {{
      const devs = await origEnum();
      if (!spoofIds) return devs;
      return devs.map((d, idx) => {{
        let outId = d.deviceId || '';
        if (outId && outId !== 'default' && outId !== 'communications') {{
          const fakeId = 'mh_' + sHex + '_' + idx;
          fakeToReal.set(fakeId, outId);
          outId = fakeId;
        }}
        return {{
          deviceId: outId,
          groupId: d.groupId ? ('grp_' + sHex + '_' + (idx % 2)) : '',
          kind: d.kind,
          label: d.label || '',
          toJSON() {{ return this; }}
        }};
      }});
    }};
    if (origGUM) {{
      navigator.mediaDevices.getUserMedia = async (constraints) => {{
        if (constraints && typeof constraints === 'object') {{
          const c = Object.assign({{}}, constraints);
          if (c.video) c.video = mapConstraint(c.video);
          if (c.audio) c.audio = mapConstraint(c.audio);
          // Apply user-selected preferred camera / mic from Site Permissions dropdown
          if ((c.video && window.__mhPreferredCam) || (c.audio && window.__mhPreferredMic)) {{
            try {{
              const realDevs = await origEnum();
              if (c.video && window.__mhPreferredCam) {{
                const cam = realDevs.find(d => d.kind === 'videoinput' && d.label === window.__mhPreferredCam);
                if (cam && cam.deviceId) {{
                  c.video = c.video === true ? {{ deviceId: {{ ideal: cam.deviceId }} }} : Object.assign({{}}, c.video, {{ deviceId: {{ ideal: cam.deviceId }} }});
                }}
              }}
              if (c.audio && window.__mhPreferredMic) {{
                const mic = realDevs.find(d => d.kind === 'audioinput' && d.label === window.__mhPreferredMic);
                if (mic && mic.deviceId) {{
                  c.audio = c.audio === true ? {{ deviceId: {{ ideal: mic.deviceId }} }} : Object.assign({{}}, c.audio, {{ deviceId: {{ ideal: mic.deviceId }} }});
                }}
              }}
            }} catch {{}}
          }}
          try {{
            return await origGUM(c);
          }} catch (err) {{
            if (err && (err.name === 'OverconstrainedError' || err.name === 'NotFoundError')) {{
              return await origGUM({{ video: !!c.video, audio: !!c.audio }});
            }}
            throw err;
          }}
        }}
        return await origGUM(constraints);
      }};
    }}
  }}
}} catch (e) {{}}";

        string batteryNetBlock = _profile.BatteryNetSpoof ? $@"
try {{
  navigator.getBattery = async () => ({{
    charging: {batCharging},
    chargingTime: {batCharging} ? 0 : 5400,
    dischargingTime: {batCharging} ? Infinity : 14400,
    level: {batLevel.ToString(System.Globalization.CultureInfo.InvariantCulture)},
    addEventListener: () => {{}},
    removeEventListener: () => {{}}
  }});
  if (navigator.connection) {{
    Object.defineProperty(navigator.connection, 'effectiveType', {{ get: () => '4g' }});
    Object.defineProperty(navigator.connection, 'rtt', {{ get: () => 50 }});
    Object.defineProperty(navigator.connection, 'downlink', {{ get: () => 10 }});
  }}
}} catch (e) {{}}" : "";

        string speechPluginsBlock = _profile.SpeechPluginsMask ? $@"
try {{
  if (window.speechSynthesis) {{
    const fakeVoices = [
      {{ voiceURI: 'Microsoft David - English (United States)', name: 'Microsoft David - English (United States)', lang: 'en-US', localService: true, default: true }},
      {{ voiceURI: 'Google US English', name: 'Google US English', lang: 'en-US', localService: false, default: false }}
    ];
    window.speechSynthesis.getVoices = () => fakeVoices;
  }}
}} catch (e) {{}}" : "";

        string mobileSensorBlock = _profile.IsMobile ? @"
try {
  window.addEventListener('load', () => {
    try {
      window.dispatchEvent(new DeviceOrientationEvent('deviceorientation', { alpha: 12.4, beta: 44.8, gamma: -2.1 }));
    } catch (e) {}
  });
} catch (e) {}" : "";

        string syncHookBlock = @"
try {
  const getCss = (el) => {
    if (!el || !el.tagName) return '';
    if (el.id) return '#' + el.id;
    const tag = el.tagName.toLowerCase();
    if (el.getAttribute('data-testid')) return tag + '[data-testid=""' + el.getAttribute('data-testid') + '""]';
    if (el.name) return tag + '[name=""' + el.name + '""]';
    if (el.className && typeof el.className === 'string') {
      const cls = el.className.trim().split(/\s+/).slice(0, 2).join('.');
      if (cls) return tag + '.' + cls;
    }
    return tag;
  };
  const getFullXPath = (el) => {
    if (!el || el.nodeType !== 1) return '';
    const parts = [];
    let cur = el;
    while (cur && cur.nodeType === 1) {
      let idx = 1;
      let sib = cur.previousElementSibling;
      while (sib) { if (sib.tagName === cur.tagName) idx++; sib = sib.previousElementSibling; }
      parts.unshift(cur.tagName.toLowerCase() + '[' + idx + ']');
      cur = cur.parentElement;
    }
    return '/' + parts.join('/');
  };
  const getSmartXPath = (el) => {
    if (!el || !el.tagName) return '';
    const tag = el.tagName.toLowerCase();
    if (el.id) return '//' + tag + '[@id=""' + el.id + '""]';
    if (el.getAttribute('data-testid')) return '//' + tag + '[@data-testid=""' + el.getAttribute('data-testid') + '""]';
    if (el.name) return '//' + tag + '[@name=""' + el.name + '""]';
    if (el.getAttribute('aria-label')) return '//' + tag + '[@aria-label=""' + el.getAttribute('aria-label') + '""]';
    const txt = (el.innerText || '').trim();
    if (txt && txt.length <= 40 && (tag === 'button' || tag === 'a' || tag === 'span'))
      return '//' + tag + '[normalize-space()=""' + txt.replace(/""/g, '') + '""]';
    return getFullXPath(el);
  };
  const sendUi = (action, el, val) => {
    if (!window.chrome || !window.chrome.webview || !el || !el.tagName) return;
    const r = el.getBoundingClientRect ? el.getBoundingClientRect() : { x:0, y:0, width:0, height:0 };
    window.chrome.webview.postMessage({
      type: 'ui_action',
      action: action,
      tag: el.tagName.toLowerCase(),
      selector: getCss(el),
      xpath: getSmartXPath(el),
      fullXpath: getFullXPath(el),
      id: el.id || '',
      name: el.name || '',
      aria: el.getAttribute('aria-label') || '',
      testid: el.getAttribute('data-testid') || el.getAttribute('data-cy') || '',
      bounds: Math.round(r.x) + ',' + Math.round(r.y) + ' (' + Math.round(r.width) + 'x' + Math.round(r.height) + ')',
      value: (val || '').toString().slice(0, 140),
      url: location.href
    });
  };
  let lastScrollSend = 0;
  window.addEventListener('click', (e) => {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage({ type: 'click', x: e.clientX, y: e.clientY });
      const el = e.target;
      sendUi('CLICK', el, el && (el.innerText || el.value || el.ariaLabel || ''));
    }
  }, true);
  window.addEventListener('dblclick', (e) => sendUi('DBLCLICK', e.target, e.target && e.target.innerText), true);
  window.addEventListener('change', (e) => {
    const el = e.target;
    if (!el || !el.tagName) return;
    const tag = el.tagName.toLowerCase();
    if (tag === 'select') sendUi('SELECT', el, el.value);
    else if (el.type === 'checkbox' || el.type === 'radio') sendUi('CHECK', el, String(el.checked));
    else sendUi('WRITE', el, el.value);
  }, true);
  window.addEventListener('submit', (e) => sendUi('SUBMIT', e.target, e.target && e.target.action), true);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === 'Tab' || e.key === 'Escape') sendUi('KEYPRESS', e.target, e.key);
  }, true);
  window.addEventListener('scroll', () => {
    const now = Date.now();
    if (now - lastScrollSend > 90 && window.chrome && window.chrome.webview) {
      lastScrollSend = now;
      window.chrome.webview.postMessage({ type: 'scroll', x: window.scrollX, y: window.scrollY });
    }
  }, true);

  // Observe navigator.sendBeacon
  if (navigator.sendBeacon) {
    const origBeacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = (url, data) => {
      try {
        window.chrome && window.chrome.webview && window.chrome.webview.postMessage({
          type: 'internal_event', category: 'BEACON', source: String(url), detail: String(data || '').slice(0, 200)
        });
      } catch (e) {}
      return origBeacon(url, data);
    };
  }
  // Observe window.postMessage (cross-window / iframe communication)
  window.addEventListener('message', (e) => {
    try {
      const payload = typeof e.data === 'string' ? e.data : JSON.stringify(e.data);
      window.chrome && window.chrome.webview && window.chrome.webview.postMessage({
        type: 'internal_event', category: 'POSTMESSAGE', source: e.origin || location.origin, detail: (payload || '').slice(0, 220)
      });
    } catch (err) {}
  }, true);
  // Observe LocalStorage writes
  const origSetItem = Storage.prototype.setItem;
  Storage.prototype.setItem = function(k, v) {
    try {
      window.chrome && window.chrome.webview && window.chrome.webview.postMessage({
        type: 'internal_event', category: 'STORAGE', source: location.hostname, detail: k + ' = ' + String(v || '').slice(0, 160)
      });
    } catch (e) {}
    return origSetItem.apply(this, arguments);
  };
  // Observe CSP violations
  document.addEventListener('securitypolicyviolation', (e) => {
    try {
      window.chrome && window.chrome.webview && window.chrome.webview.postMessage({
        type: 'internal_event', category: 'CSP', source: e.violatedDirective || 'CSP', detail: 'Blocked: ' + (e.blockedURI || '')
      });
    } catch (err) {}
  });
} catch (e) {}";

        string geoSpoofBlock = _geoSpoofActive ? $@"
try {{
  window.__mhGeo = {{
    enabled: true,
    lat: {_activeGeoLat.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)},
    lon: {_activeGeoLon.ToString("F6", System.Globalization.CultureInfo.InvariantCulture)},
    acc: {_activeGeoAcc.ToString("F1", System.Globalization.CultureInfo.InvariantCulture)}
  }};
  const makePos = (jitter) => {{
    const g = window.__mhGeo;
    const jLat = jitter ? (Math.random() - 0.5) * 0.00008 : 0;
    const jLon = jitter ? (Math.random() - 0.5) * 0.00008 : 0;
    return {{
      coords: {{
        latitude: g.lat + jLat,
        longitude: g.lon + jLon,
        accuracy: g.acc || 35,
        altitude: null,
        altitudeAccuracy: null,
        heading: null,
        speed: null
      }},
      timestamp: Date.now()
    }};
  }};
  if (navigator.geolocation) {{
    const origGet = navigator.geolocation.getCurrentPosition.bind(navigator.geolocation);
    const origWatch = navigator.geolocation.watchPosition.bind(navigator.geolocation);
    const origClear = navigator.geolocation.clearWatch.bind(navigator.geolocation);
    const mhWatches = new Map();
    let watchSeq = 90000;
    navigator.geolocation.getCurrentPosition = function(success, error, opts) {{
      if (window.__mhGeo && window.__mhGeo.enabled && typeof success === 'function') {{
        setTimeout(() => success(makePos(false)), 35);
        return;
      }}
      return origGet(success, error, opts);
    }};
    navigator.geolocation.watchPosition = function(success, error, opts) {{
      if (window.__mhGeo && window.__mhGeo.enabled && typeof success === 'function') {{
        const id = ++watchSeq;
        setTimeout(() => success(makePos(false)), 40);
        const timer = setInterval(() => {{
          if (window.__mhGeo && window.__mhGeo.enabled) success(makePos(true));
        }}, 4000);
        mhWatches.set(id, timer);
        return id;
      }}
      return origWatch(success, error, opts);
    }};
    navigator.geolocation.clearWatch = function(id) {{
      if (mhWatches.has(id)) {{ clearInterval(mhWatches.get(id)); mhWatches.delete(id); return; }}
      return origClear(id);
    }};
  }}
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
{webglAndWebGpuBlock}
{audioBlock}
{clientRectsBlock}
{fontBlock}
{webrtcSpoofBlock}
{mediaBlock}
{geoSpoofBlock}
{batteryNetBlock}
{speechPluginsBlock}
{mobileSensorBlock}
{syncHookBlock}";
    }

    private void SelectTab(int index)
    {
        if (index < 0 || index >= _tabs.Count) return;
        _activeIndex = index;
        for (int i = 0; i < _tabs.Count; i++)
            _tabs[i].WebView.Visibility = (i == index) ? Visibility.Visible : Visibility.Collapsed;
        UrlBox.Text = _tabs[index].Url;
        UpdateLoadingAnimation(_tabs[index].IsLoading);
        UpdateBookmarkStarState();
        RebuildTabStrip();
        PersistOpenTabs();
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
            if (_tabs[i].Favicon is not null)
            {
                sp.Children.Add(new System.Windows.Controls.Image
                {
                    Source = _tabs[i].Favicon,
                    Width = 14,
                    Height = 14,
                    Margin = new Thickness(0, 0, 6, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }
            else
            {
                sp.Children.Add(new System.Windows.Shapes.Path
                {
                    Data = (Geometry)FindResource("IconGlobe"),
                    Fill = (Brush)FindResource("Muted"),
                    Width = 13,
                    Height = 13,
                    Stretch = Stretch.Uniform,
                    Margin = new Thickness(0, 0, 6, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }
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

    private string NormalizeUrl(string input)
    {
        input = input.Trim();
        if (string.IsNullOrEmpty(input)) return "https://whoer.net";
        if (input.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("extension://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("chrome://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("edge://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("about:", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("file://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
            return input;
        if (!input.Contains(' ') && input.Contains('.'))
            return "https://" + input;
        return SearchEngines.BuildSearchUrl(_profile.SearchEngine, input);
    }

    private void NavigateCurrent(string input)
    {
        string url = NormalizeUrl(input);
        ActiveCore?.Navigate(url);
        WindowSyncManager.BroadcastNavigate(this, url);
    }

    private async void BtnNewTab_Click(object sender, RoutedEventArgs e)
    {
        string home = _profile.SearchEngine switch
        {
            "DuckDuckGo" => "https://duckduckgo.com",
            "Bing" => "https://www.bing.com",
            "Brave Search" => "https://search.brave.com",
            "Yahoo" => "https://search.yahoo.com",
            "Yandex" => "https://yandex.com",
            _ => "https://www.google.com"
        };
        await OpenNewTabAsync(home);
    }

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

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        if (ctrl && shift && e.Key == Key.V) { BtnHumanPaste_Click(sender, e); e.Handled = true; }
        else if (ctrl && e.Key == Key.T) { BtnNewTab_Click(sender, e); e.Handled = true; }
        else if (ctrl && e.Key == Key.W) { CloseTab(_activeIndex); e.Handled = true; }
        else if (ctrl && e.Key == Key.L) { UrlBox.Focus(); UrlBox.SelectAll(); e.Handled = true; }
        else if (ctrl && e.Key == Key.D) { BtnToggleBookmark_Click(sender, e); e.Handled = true; }
        else if (ctrl && e.Key == Key.H) { if (!_trayOpen) BtnToggleTray_Click(sender, e); SetTrayTab("History"); e.Handled = true; }
        else if (e.Key == Key.F5) { ActiveCore?.Reload(); e.Handled = true; }
        else if (e.Key == Key.F12) { ActiveCore?.OpenDevToolsWindow(); e.Handled = true; }
    }
}
