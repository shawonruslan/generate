using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
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
    double Lon);

public partial class BrowserWindow : Window
{
    private sealed class TabState
    {
        public WebView2 WebView { get; init; } = new();
        public string Title { get; set; } = "New Tab";
        public string Url { get; set; } = "";
        public bool IsLoading { get; set; }
    }

    private readonly BrowserProfile _profile;
    private readonly Action _saveStore;
    private readonly VerifiedConnection _conn;
    private readonly List<TabState> _tabs = new();
    private readonly int _cdpPort;
    private int _activeIndex = -1;
    private CoreWebView2Environment? _env;
    private DispatcherTimer? _killSwitchTimer;
    private bool _killSwitchTripped;
    private bool _extensionsLoaded;
    private bool _trayOpen;
    private bool _loadingEngineCombo;
    private bool _cookieRobotRunning;

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

        RefreshBookmarksUi();
        RefreshHistoryUi();
        WindowSyncManager.Register(this);

        Loaded += async (_, _) => await InitEnvironmentAndRestoreTabsAsync();
    }

    protected override void OnClosed(EventArgs e)
    {
        _killSwitchTimer?.Stop();
        WindowSyncManager.Unregister(this);
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
        _killSwitchTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(18) };
        _killSwitchTimer.Tick += async (_, _) =>
        {
            if (_killSwitchTripped) return;
            var (ok, _, _, _, _, _) = await IpTimezoneDetector.DetectAsync(
                _conn.LocalSocksPort > 0 ? null : _profile, _conn.LocalSocksPort);
            if (!ok)
            {
                _killSwitchTripped = true;
                KillSwitchBanner.Visibility = Visibility.Visible;
                StatusText.Text = "KILL-SWITCH TRIGGERED: VPN/Proxy dropped. Traffic frozen.";
            }
        };
        _killSwitchTimer.Start();
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
            }

            if (_profile.WebRtcProtect)
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
        if (!_extensionsLoaded && _profile.ExtensionPaths is { Count: > 0 })
        {
            _extensionsLoaded = true;
            foreach (var extDir in _profile.ExtensionPaths)
            {
                if (Directory.Exists(extDir))
                {
                    try { await core.Profile.AddBrowserExtensionAsync(extDir); } catch { }
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(_profile.UserAgent))
            core.Settings.UserAgent = _profile.UserAgent;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;

        // Localhost Port-Scan Blocker + Live Kill-Switch Request Interceptor
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) =>
        {
            if (_killSwitchTripped)
            {
                e.Response = _env.CreateWebResourceResponse(null, 403, "Blocked by Kill-Switch", "");
                return;
            }
            // Block external websites from scanning localhost / 127.0.0.1 / 0.0.0.0 ports
            if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var reqUri) &&
                (reqUri.Host == "127.0.0.1" || reqUri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || reqUri.Host == "0.0.0.0"))
            {
                if (!string.IsNullOrEmpty(tab.Url) &&
                    !tab.Url.StartsWith("http://127.0.0.1", StringComparison.OrdinalIgnoreCase) &&
                    !tab.Url.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase))
                {
                    e.Response = _env.CreateWebResourceResponse(null, 403, "Blocked Port Scan", "");
                }
            }
        };

        // Receive Master window sync events (click / scroll) from JS
        core.WebMessageReceived += (_, e) =>
        {
            if (!WindowSyncManager.IsSyncEnabled || !ReferenceEquals(WindowSyncManager.MasterWindow, this)) return;
            try
            {
                using var doc = JsonDocument.Parse(e.WebMessageAsJson);
                var root = doc.RootElement;
                string type = root.GetProperty("type").GetString() ?? "";
                double x = root.TryGetProperty("x", out var xe) ? xe.GetDouble() : 0;
                double y = root.TryGetProperty("y", out var ye) ? ye.GetDouble() : 0;
                WindowSyncManager.BroadcastAction(this, type, x, y);
            }
            catch { }
        };

        if (!string.IsNullOrWhiteSpace(_conn.Timezone))
        {
            try
            {
                var tzPayload = JsonSerializer.Serialize(new { timezoneId = _conn.Timezone });
                await core.CallDevToolsProtocolMethodAsync("Emulation.setTimezoneOverride", tzPayload);
            }
            catch { }
        }

        if (_profile.AutoGeolocation && (Math.Abs(_conn.Lat) > 0.001 || Math.Abs(_conn.Lon) > 0.001))
        {
            try
            {
                var geoPayload = JsonSerializer.Serialize(new { latitude = _conn.Lat, longitude = _conn.Lon, accuracy = 100 });
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

        var (ok, folder, msg) = ExtensionHelper.InstallExtension(dlg.FileName);
        if (!ok)
        {
            DarkDialog.ShowInfo(this, "Extension Error", msg);
            return;
        }
        try
        {
            await ActiveCore.Profile.AddBrowserExtensionAsync(folder);
            _profile.ExtensionPaths ??= new List<string>();
            if (!_profile.ExtensionPaths.Contains(folder))
            {
                _profile.ExtensionPaths.Add(folder);
                _saveStore();
            }
            StatusText.Text = $"Extension loaded: {msg}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Extension Load Error", ex.Message); }
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
        var anim = new DoubleAnimation(_trayOpen ? 310 : 0, TimeSpan.FromMilliseconds(200))
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

        string mediaBlock = _profile.MediaDeviceSpoof ? $@"
try {{
  if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {{
    const origEnum = navigator.mediaDevices.enumerateDevices.bind(navigator.mediaDevices);
    const sHex = '{seed:x8}';
    navigator.mediaDevices.enumerateDevices = async () => {{
      const devs = await origEnum();
      return devs.map((d, idx) => ({{
        deviceId: d.deviceId === 'default' ? 'default' : ('mh_' + sHex + '_' + idx),
        groupId: 'grp_' + sHex + '_' + (idx % 2),
        kind: d.kind,
        label: d.label || (d.kind === 'videoinput' ? 'HD USB Webcam' : ''),
        toJSON() {{ return this; }}
      }}));
    }};
  }}
}} catch (e) {{}}" : "";

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
  let lastScrollSend = 0;
  window.addEventListener('click', (e) => {
    if (window.chrome && window.chrome.webview)
      window.chrome.webview.postMessage({ type: 'click', x: e.clientX, y: e.clientY });
  }, true);
  window.addEventListener('scroll', () => {
    const now = Date.now();
    if (now - lastScrollSend > 90 && window.chrome && window.chrome.webview) {
      lastScrollSend = now;
      window.chrome.webview.postMessage({ type: 'scroll', x: window.scrollX, y: window.scrollY });
    }
  }, true);
} catch (e) {}";

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
            input.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
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
