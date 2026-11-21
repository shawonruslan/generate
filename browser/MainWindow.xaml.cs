using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace MHBrowser;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<BrowserProfile> _allProfiles = new();
    private readonly ObservableCollection<BrowserProfile> _filteredProfiles = new();
    private readonly ObservableCollection<SavedProxy> _proxies = new();
    private readonly Dictionary<string, RealChromiumSession> _openSessions = new();
    private bool _updatingGroups;
    private CloudSyncConfig _cloudConfig = new();

    public MainWindow()
    {
        InitializeComponent();
        foreach (var p in ProfileStore.Load()) _allProfiles.Add(p);
        foreach (var px in ProxyStore.Load()) _proxies.Add(px);
        ProfilesList.ItemsSource = _filteredProfiles;
        ProxiesList.ItemsSource = _proxies;
        RefreshGroupsCombo();
        RefreshFilter();
        _cloudConfig = CloudSyncStore.Load();
        TxtR2Endpoint.Text = _cloudConfig.EndpointUrl;
        TxtR2Bucket.Text = string.IsNullOrWhiteSpace(_cloudConfig.BucketName) ? "mh-profiles" : _cloudConfig.BucketName;
        TxtR2AccessKey.Text = _cloudConfig.AccessKeyId;
        TxtR2SecretKey.Text = _cloudConfig.SecretAccessKey;
        TxtR2Password.Text = _cloudConfig.SyncPassword;
        ChkR2AutoSync.IsChecked = _cloudConfig.AutoSyncOnClose;
        ChromiumStatusText.Text = $"Chromium v{ChromiumManager.GetInstalledVersion()}";
        Loaded += async (_, _) => await RunChromiumAutoUpdateAsync(silent: true);
        SetActiveView("Apps");
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
        App.SetWindowAppUserModelId(this, "MHAdvancedTool.Hub");
    }

    private void RefreshGroupsCombo()
    {
        _updatingGroups = true;
        string prev = CbGroupFilter.SelectedItem as string ?? "All Groups";
        var groups = new List<string> { "All Groups" };
        groups.AddRange(_allProfiles.Select(p => string.IsNullOrWhiteSpace(p.Group) ? "Default" : p.Group)
            .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(g => g));
        CbGroupFilter.ItemsSource = groups;
        CbGroupFilter.SelectedItem = groups.Contains(prev) ? prev : "All Groups";
        _updatingGroups = false;
    }

    private void RefreshFilter()
    {
        string q = SearchBox?.Text?.Trim() ?? "";
        string grp = CbGroupFilter?.SelectedItem as string ?? "All Groups";
        _filteredProfiles.Clear();
        foreach (var p in _allProfiles)
        {
            bool grpOk = grp == "All Groups" ||
                         (string.IsNullOrWhiteSpace(p.Group) ? "Default" : p.Group).Equals(grp, StringComparison.OrdinalIgnoreCase);
            bool textOk = string.IsNullOrEmpty(q) ||
                          p.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          p.Notes.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          p.Group.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          p.ProxySummary.Contains(q, StringComparison.OrdinalIgnoreCase);
            if (grpOk && textOk) _filteredProfiles.Add(p);
        }
        SidebarCountText.Text = $"{_allProfiles.Count} Profile{(_allProfiles.Count == 1 ? "" : "s")} | {_proxies.Count} Proxies";
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshFilter();
    private void CbGroupFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_updatingGroups) RefreshFilter();
    }

    private void SetActiveView(string view)
    {
        AppsView.Visibility = view == "Apps" ? Visibility.Visible : Visibility.Collapsed;
        ProfilesView.Visibility = view == "Profiles" ? Visibility.Visible : Visibility.Collapsed;
        ProxiesView.Visibility = view == "Proxies" ? Visibility.Visible : Visibility.Collapsed;
        VpnView.Visibility = view == "Vpn" ? Visibility.Visible : Visibility.Collapsed;
        CloudView.Visibility = view == "Cloud" ? Visibility.Visible : Visibility.Collapsed;

        bool isProfiles = view == "Profiles";
        SearchBox.Visibility = isProfiles ? Visibility.Visible : Visibility.Collapsed;
        CbGroupFilter.Visibility = isProfiles ? Visibility.Visible : Visibility.Collapsed;
        ProfileTopActions.Visibility = isProfiles ? Visibility.Visible : Visibility.Collapsed;

        PageTitleText.Text = view switch
        {
            "Profiles" => "Antidetect Browser Profiles",
            "Proxies" => "Proxy Manager & Bulk Checker",
            "Vpn" => "VPN Manager (OpenVPN / WireGuard)",
            "Cloud" => "Cloud Sync (Cloudflare R2)",
            _ => "Applications"
        };

        var panelBrush = (Brush)FindResource("Panel");
        var transparent = Brushes.Transparent;
        NavApps.Background = view == "Apps" ? panelBrush : transparent;
        NavProfiles.Background = view == "Profiles" ? panelBrush : transparent;
        NavProxies.Background = view == "Proxies" ? panelBrush : transparent;
        NavVpn.Background = view == "Vpn" ? panelBrush : transparent;
        NavCloud.Background = view == "Cloud" ? panelBrush : transparent;
    }

    private void NavApps_Click(object sender, RoutedEventArgs e) => SetActiveView("Apps");
    private void NavProfiles_Click(object sender, RoutedEventArgs e) => SetActiveView("Profiles");
    private void NavProxies_Click(object sender, RoutedEventArgs e) => SetActiveView("Proxies");
    private void NavVpn_Click(object sender, RoutedEventArgs e) => SetActiveView("Vpn");
    private void NavCloud_Click(object sender, RoutedEventArgs e) => SetActiveView("Cloud");

    // --------------------------------------------------------- Proxy Manager Actions
    private void BtnImportProxies_Click(object sender, RoutedEventArgs e)
    {
        string defaultType = CbBulkProxyType.SelectedIndex switch { 1 => "HTTP", 2 => "HTTPS", _ => "SOCKS5" };
        var parsed = ProxyStore.ParseBulk(TxtBulkProxies.Text, defaultType);
        if (parsed.Count == 0)
        {
            DarkDialog.ShowInfo(this, "Proxy Import", "No valid proxies found. Use host:port:user:pass or socks5://user:pass@host:port (one per line).");
            return;
        }
        foreach (var px in parsed) _proxies.Add(px);
        ProxyStore.Save(_proxies);
        TxtBulkProxies.Text = "";
        RefreshFilter();
        StatusText.Text = $"Imported {parsed.Count} proxies.";
    }

    private async void BtnCheckAllProxies_Click(object sender, RoutedEventArgs e)
    {
        if (_proxies.Count == 0) return;
        StatusText.Text = $"Checking {_proxies.Count} proxies...";
        var tasks = _proxies.ToList().Select(p => ProxyStore.CheckAsync(p));
        await Task.WhenAll(tasks);
        ProxyStore.Save(_proxies);
        int live = _proxies.Count(p => p.Status == "LIVE");
        StatusText.Text = $"Proxy check complete: {live}/{_proxies.Count} LIVE.";
    }

    private void BtnRemoveDeadProxies_Click(object sender, RoutedEventArgs e)
    {
        var dead = _proxies.Where(p => p.Status == "DEAD").ToList();
        foreach (var d in dead) _proxies.Remove(d);
        ProxyStore.Save(_proxies);
        RefreshFilter();
        StatusText.Text = $"Removed {dead.Count} dead proxies.";
    }

    private void BtnDeleteProxy_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not SavedProxy px) return;
        _proxies.Remove(px);
        ProxyStore.Save(_proxies);
        RefreshFilter();
    }

    // --------------------------------------------------------- VirtualCam & Profile Launch
    private void BtnLaunchVirtualCam_Click(object sender, RoutedEventArgs e)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string[] candidates =
        {
            Path.GetFullPath(Path.Combine(baseDir, "..", "MHVirtualCam.exe")),
            Path.Combine(baseDir, "MHVirtualCam.exe")
        };
        var exe = candidates.FirstOrDefault(File.Exists);
        if (exe is null)
        {
            DarkDialog.ShowInfo(this, "MH Advanced Tool", "MHVirtualCam.exe was not found in the installation folder.");
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo { FileName = exe, WorkingDirectory = Path.GetDirectoryName(exe) ?? baseDir, UseShellExecute = true });
            StatusText.Text = "Launched MH Virtual Camera.";
        }
        catch (Exception ex) { StatusText.Text = $"Could not launch MH Virtual Camera: {ex.Message}"; }
    }

    private async void BtnQuickLaunchBrowser_Click(object sender, RoutedEventArgs e)
    {
        if (_allProfiles.Count == 0)
        {
            var def = new BrowserProfile { Name = "Default Desktop", Notes = "Windows 11 Chrome + HD USB Webcam" };
            _allProfiles.Add(def);
            ProfileStore.Save(_allProfiles);
            RefreshGroupsCombo();
            RefreshFilter();
        }
        await LaunchProfileAsync(_allProfiles[0]);
    }

    private async Task LaunchProfileAsync(BrowserProfile profile)
    {
        if (_openSessions.TryGetValue(profile.Id, out var existing) && existing.IsRunning)
        {
            existing.Activate();
            return;
        }

        ChromiumManager.ApplyPendingUpdateIfSafe(_openSessions.Values.Any(s => s.IsRunning));
        string? chromiumExe = ChromiumManager.FindChromiumExe();
        if (string.IsNullOrEmpty(chromiumExe))
        {
            var dlBusy = new DarkDialog("Downloading Real Chromium", "Downloading official Chromium engine (first-time setup)...", isBusy: true) { Owner = this };
            dlBusy.Show();
            var (_, ver, dlMsg) = await ChromiumManager.CheckAndAutoUpdateAsync(
                () => _openSessions.Values.Any(s => s.IsRunning),
                st => Dispatcher.Invoke(() => { dlBusy.UpdateMessage(st); ChromiumStatusText.Text = st; }));
            dlBusy.Close();
            chromiumExe = ChromiumManager.FindChromiumExe();
            ChromiumStatusText.Text = $"Chromium v{ver}";
            if (string.IsNullOrEmpty(chromiumExe))
            {
                DarkDialog.ShowInfo(this, "Chromium Engine Required", $"Could not locate or download Chromium:\n{dlMsg}");
                return;
            }
        }

        var busy = new DarkDialog($"Connecting '{profile.Name}'", "Preparing isolated profile connection...", isBusy: true) { Owner = this };
        busy.Show();

        ProfileVpnSession? vpnSession = null;
        LocalSocks5AuthForwarder? socksFwd = null;
        int localSocksPort = 0;

        try
        {
            if (profile.ProxyType is "OpenVPN" or "WireGuard")
            {
                vpnSession = new ProfileVpnSession();
                var (ok, port, msg) = await vpnSession.StartAsync(
                    profile.Id, profile.ProxyType, profile.VpnConfigPath,
                    s => busy.UpdateBusyMessage(s));

                if (!ok)
                {
                    busy.Close();
                    vpnSession.Dispose();
                    DarkDialog.ShowInfo(this, "Connection Failed", msg);
                    return;
                }
                localSocksPort = port;
            }
            else if (profile.ProxyType == "SOCKS5")
            {
                if (string.IsNullOrWhiteSpace(profile.ProxyHost) || !int.TryParse(profile.ProxyPort, out int sp) || sp <= 0)
                {
                    busy.Close();
                    DarkDialog.ShowInfo(this, "Invalid SOCKS5 Proxy", "Please enter a valid SOCKS5 Host and Port in profile settings.");
                    return;
                }
                busy.UpdateBusyMessage($"Starting SOCKS5 bridge to {profile.ProxyHost}:{sp}...");
                socksFwd = new LocalSocks5AuthForwarder(profile.ProxyHost, sp, profile.ProxyUser, profile.ProxyPass);
                localSocksPort = socksFwd.Port;
            }
            else if (profile.ProxyType is "HTTP" or "HTTPS")
            {
                if (string.IsNullOrWhiteSpace(profile.ProxyHost) || string.IsNullOrWhiteSpace(profile.ProxyPort))
                {
                    busy.Close();
                    DarkDialog.ShowInfo(this, "Invalid Proxy", $"Please enter a valid {profile.ProxyType} Host and Port.");
                    return;
                }
            }

            string exitIp = "", exitLoc = "", exitTz = profile.Timezone;
            double lat = 0, lon = 0;
            bool requiresVerify = profile.ProxyType != "Direct";

            if (requiresVerify || profile.AutoTimezone || profile.AutoGeolocation)
            {
                busy.UpdateBusyMessage($"Verifying {profile.ProxyType} exit IP & Timezone...");
                var (okIp, ip, loc, tz, dLat, dLon) = await IpTimezoneDetector.DetectAsync(
                    localSocksPort > 0 ? null : profile, localSocksPort);

                if (!okIp)
                {
                    if (requiresVerify)
                    {
                        busy.Close();
                        vpnSession?.Dispose();
                        socksFwd?.Dispose();
                        DarkDialog.ShowInfo(this, "Connection Not Ready",
                            $"The {profile.ProxyType} connection could not reach the internet.\n\nBrowser launch was cancelled to protect your real IP. Check your proxy credentials, port, or VPN config.");
                        return;
                    }
                }
                else
                {
                    exitIp = ip;
                    exitLoc = loc;
                    if (profile.AutoTimezone)
                    {
                        exitTz = tz;
                        profile.Timezone = tz;
                    }
                    lat = dLat;
                    lon = dLon;
                    profile.NotifyAll();
                    ProfileStore.Save(_allProfiles);
                }
            }

            busy.Close();

            var conn = new VerifiedConnection(vpnSession, socksFwd, localSocksPort, exitIp, exitLoc, exitTz, lat, lon);
            var session = new RealChromiumSession(profile, conn);
            if (!session.Launch(chromiumExe, out string launchErr))
            {
                session.Dispose();
                DarkDialog.ShowInfo(this, "Launch Failed", $"Could not start Real Chromium:\n{launchErr}");
                return;
            }
            session.Exited += () => Dispatcher.BeginInvoke(async () =>
            {
                _openSessions.Remove(profile.Id);
                profile.IsRunning = false;
                profile.NotifyAll();
                ProfileStore.Save(_allProfiles);
                ChromiumManager.ApplyPendingUpdateIfSafe(_openSessions.Values.Any(s => s.IsRunning));
                if (_cloudConfig.AutoSyncOnClose && _cloudConfig.IsConfigured)
                {
                    StatusText.Text = $"Auto-syncing '{profile.Name}' to Cloudflare R2...";
                    var (okSync, msgSync) = await CloudflareR2Sync.PushProfileAsync(_cloudConfig, profile);
                    StatusText.Text = okSync ? msgSync : $"Auto-sync warning: {msgSync}";
                }
            });
            _openSessions[profile.Id] = session;
            profile.NotifyAll();
            StatusText.Text = string.IsNullOrWhiteSpace(exitIp)
                ? $"Launched Real Chromium '{profile.Name}'"
                : $"Launched Real Chromium '{profile.Name}' | Exit IP: {exitIp} ({exitLoc})";
        }
        catch (Exception ex)
        {
            try { busy.Close(); } catch { }
            vpnSession?.Dispose();
            socksFwd?.Dispose();
            DarkDialog.ShowInfo(this, "Launch Error", ex.Message);
        }
    }

    private void BtnCreateProfile_Click(object sender, RoutedEventArgs e)
    {
        var p = new BrowserProfile { Name = $"Profile {_allProfiles.Count + 1}" };
        var dlg = new ProfileEditWindow(p) { Owner = this };
        if (dlg.ShowDialog() == true)
        {
            _allProfiles.Add(p);
            ProfileStore.Save(_allProfiles);
            RefreshGroupsCombo();
            RefreshFilter();
            SetActiveView("Profiles");
            StatusText.Text = $"Created profile: {p.Name}";
        }
    }

    private async void BtnRunProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        await LaunchProfileAsync(profile);
    }

    private void BtnEditProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        var dlg = new ProfileEditWindow(profile) { Owner = this };
        if (dlg.ShowDialog() == true)
        {
            ProfileStore.Save(_allProfiles);
            RefreshGroupsCombo();
            RefreshFilter();
            StatusText.Text = $"Updated profile: {profile.Name}";
        }
    }

    private void BtnCloneProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        var copy = profile.Clone();
        _allProfiles.Add(copy);
        ProfileStore.Save(_allProfiles);
        RefreshGroupsCombo();
        RefreshFilter();
        StatusText.Text = $"Cloned profile: {copy.Name}";
    }


    private void BtnTileAll_Click(object sender, RoutedEventArgs e)
    {
        WindowSyncManager.TileWindowsGrid();
        StatusText.Text = $"Tiled {WindowSyncManager.OpenCount} open browser window(s).";
    }

    private void BtnExportProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        string? pwd = DarkDialog.ShowInput(this, "Export Encrypted Profile",
            $"Enter a password to encrypt '{profile.Name}' (.mhprofile AES-256):", "Export");
        if (string.IsNullOrWhiteSpace(pwd)) return;

        var dlg = new SaveFileDialog
        {
            Filter = "MH Encrypted Profile (*.mhprofile)|*.mhprofile",
            FileName = $"{profile.Name}.mhprofile",
            Title = "Save Encrypted Profile Backup"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            ProfileBackupHelper.ExportEncrypted(profile, dlg.FileName, pwd);
            StatusText.Text = $"Exported encrypted backup: {Path.GetFileName(dlg.FileName)}";
            DarkDialog.ShowInfo(this, "Export Complete", $"Profile exported with AES-256 encryption:\n{dlg.FileName}");
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Export Failed", ex.Message); }
    }

    private void BtnImportProfile_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "MH Encrypted Profile (*.mhprofile)|*.mhprofile|All Files|*.*",
            Title = "Import Encrypted Profile Backup"
        };
        if (dlg.ShowDialog() != true) return;

        string? pwd = DarkDialog.ShowInput(this, "Decrypt Profile",
            $"Enter password to decrypt '{Path.GetFileName(dlg.FileName)}':", "Import");
        if (string.IsNullOrWhiteSpace(pwd)) return;

        try
        {
            var imported = ProfileBackupHelper.ImportEncrypted(dlg.FileName, pwd);
            _allProfiles.Add(imported);
            ProfileStore.Save(_allProfiles);
            RefreshGroupsCombo();
            RefreshFilter();
            StatusText.Text = $"Imported profile: {imported.Name}";
        }
        catch (Exception ex)
        {
            DarkDialog.ShowInfo(this, "Import Failed", $"Could not decrypt profile (wrong password or corrupted file).\n\n{ex.Message}");
        }
    }

    private void BtnDeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        if (!DarkDialog.ShowConfirm(this, "Delete Profile",
            $"Delete profile '{profile.Name}' and all its saved browser data?",
            yesText: "Delete", noText: "Cancel", danger: true)) return;

        if (_openSessions.TryGetValue(profile.Id, out var sess)) { sess.CloseBrowser(); sess.Dispose(); _openSessions.Remove(profile.Id); }
        _allProfiles.Remove(profile);
        ProfileStore.Save(_allProfiles);
        try { if (Directory.Exists(profile.UserDataDir)) Directory.Delete(profile.UserDataDir, true); } catch { }
        RefreshGroupsCombo();
        RefreshFilter();
        StatusText.Text = $"Deleted profile: {profile.Name}";
    }

    // --------------------------------------------------------- VPN actions
    private void BtnBrowseOvpn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "OpenVPN Config (*.ovpn)|*.ovpn|All Files|*.*", Title = "Select .ovpn File" };
        if (dlg.ShowDialog() == true) TxtOvpnPath.Text = dlg.FileName;
    }

    private void BtnConnectOvpn_Click(object sender, RoutedEventArgs e)
    {
        var (_, msg) = VpnController.ConnectOpenVpn(TxtOvpnPath.Text.Trim());
        StatusText.Text = msg;
    }

    private void BtnStopOvpn_Click(object sender, RoutedEventArgs e)
    {
        var (_, msg) = VpnController.DisconnectOpenVpn();
        StatusText.Text = msg;
    }

    private void BtnBrowseWg_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "WireGuard Config (*.conf)|*.conf|All Files|*.*", Title = "Select WireGuard .conf File" };
        if (dlg.ShowDialog() == true) TxtWgPath.Text = dlg.FileName;
    }

    private void BtnConnectWg_Click(object sender, RoutedEventArgs e)
    {
        var (_, msg) = VpnController.ConnectWireGuard(TxtWgPath.Text.Trim());
        StatusText.Text = msg;
    }

    private void BtnStopWg_Click(object sender, RoutedEventArgs e)
    {
        var (_, msg) = VpnController.DisconnectWireGuard();
        StatusText.Text = msg;
    }

    private async void BtnCheckGlobalIp_Click(object sender, RoutedEventArgs e)
    {
        GlobalIpText.Text = "Checking IP & Timezone...";
        var (ok, ip, loc, tz, lat, lon) = await IpTimezoneDetector.DetectAsync(null);
        GlobalIpText.Text = ok ? $"IP: {ip}  |  {loc}  |  TZ: {tz}  |  Geo: {lat:F2}, {lon:F2}" : "Could not detect IP/Timezone.";
    }

    // --------------------------------------------------------- Cloudflare R2 Cloud Sync
    private CloudSyncConfig ReadCloudConfigFromUi()
    {
        _cloudConfig = new CloudSyncConfig
        {
            EndpointUrl = TxtR2Endpoint.Text.Trim(),
            BucketName = TxtR2Bucket.Text.Trim(),
            AccessKeyId = TxtR2AccessKey.Text.Trim(),
            SecretAccessKey = TxtR2SecretKey.Text.Trim(),
            SyncPassword = TxtR2Password.Text,
            AutoSyncOnClose = ChkR2AutoSync.IsChecked == true
        };
        CloudSyncStore.Save(_cloudConfig);
        return _cloudConfig;
    }

    private async void BtnR2SaveTest_Click(object sender, RoutedEventArgs e)
    {
        var cfg = ReadCloudConfigFromUi();
        R2StatusText.Foreground = (Brush)FindResource("Accent");
        R2StatusText.Text = "Testing Cloudflare R2 connection...";
        var (ok, msg) = await CloudflareR2Sync.TestConnectionAsync(cfg);
        R2StatusText.Foreground = (Brush)FindResource(ok ? "Green" : "Danger");
        R2StatusText.Text = msg;
        StatusText.Text = msg;
    }

    private async void BtnR2PushAll_Click(object sender, RoutedEventArgs e)
    {
        var cfg = ReadCloudConfigFromUi();
        R2StatusText.Foreground = (Brush)FindResource("Accent");
        var (ok, msg) = await CloudflareR2Sync.PushAllAsync(cfg, _allProfiles, _proxies,
            s => Dispatcher.BeginInvoke(() => R2StatusText.Text = s));
        R2StatusText.Foreground = (Brush)FindResource(ok ? "Green" : "Danger");
        R2StatusText.Text = msg;
        StatusText.Text = msg;
    }

    private async void BtnR2PullAll_Click(object sender, RoutedEventArgs e)
    {
        var cfg = ReadCloudConfigFromUi();
        if (!DarkDialog.ShowConfirm(this, "Pull from Cloudflare R2",
            "Download and restore all profiles & proxies from Cloudflare R2? Existing matching profiles will be updated.",
            yesText: "Pull Now", noText: "Cancel")) return;

        R2StatusText.Foreground = (Brush)FindResource("Accent");
        var (ok, profiles, proxies, msg) = await CloudflareR2Sync.PullAllAsync(cfg,
            s => Dispatcher.BeginInvoke(() => R2StatusText.Text = s));
        R2StatusText.Foreground = (Brush)FindResource(ok ? "Green" : "Danger");
        R2StatusText.Text = msg;
        StatusText.Text = msg;
        if (!ok) return;

        _allProfiles.Clear();
        foreach (var p in profiles) _allProfiles.Add(p);
        ProfileStore.Save(_allProfiles);

        _proxies.Clear();
        foreach (var px in proxies) _proxies.Add(px);
        ProxyStore.Save(_proxies);

        RefreshGroupsCombo();
        RefreshFilter();
    }

    private async void BtnUpdateChromium_Click(object sender, RoutedEventArgs e) =>
        await RunChromiumAutoUpdateAsync(silent: false);

    private async Task RunChromiumAutoUpdateAsync(bool silent)
    {
        BtnUpdateChromium.IsEnabled = false;
        try
        {
            var (updated, ver, msg) = await ChromiumManager.CheckAndAutoUpdateAsync(
                () => _openSessions.Values.Any(s => s.IsRunning),
                st => Dispatcher.Invoke(() => { ChromiumStatusText.Text = st; StatusText.Text = st; }));
            ChromiumStatusText.Text = $"Chromium v{ver}";
            if (updated || !silent)
                StatusText.Text = msg;
            if (!silent && !updated)
                DarkDialog.ShowInfo(this, "Chromium Engine", msg);
        }
        finally
        {
            BtnUpdateChromium.IsEnabled = true;
        }
    }

    private void BtnInspectProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile p) return;
        if (_openSessions.TryGetValue(p.Id, out var session) && session.IsRunning)
        {
            session.OpenInspector();
            StatusText.Text = $"Opened Reqable/Fiddler Inspector for '{p.Name}' (CDP:{session.CdpPort})";
        }
        else
        {
            DarkDialog.ShowInfo(this, "Inspector", $"Launch '{p.Name}' first, then click Inspect to capture live network traffic.");
        }
    }

    private void TileRunningChromiumSessions()
    {
        var active = _openSessions.Values.Where(s => s.IsRunning).ToList();
        if (active.Count == 0) return;
        var wa = SystemParameters.WorkArea;
        int cols = (int)Math.Ceiling(Math.Sqrt(active.Count));
        int rows = (int)Math.Ceiling((double)active.Count / cols);
        int cellW = (int)(wa.Width / cols);
        int cellH = (int)(wa.Height / rows);
        for (int i = 0; i < active.Count; i++)
        {
            int c = i % cols;
            int r = i / cols;
            active[i].MoveToBounds((int)wa.Left + c * cellW, (int)wa.Top + r * cellH, cellW, cellH);
        }
        StatusText.Text = $"Tiled {active.Count} Real Chromium window(s).";
    }
}
