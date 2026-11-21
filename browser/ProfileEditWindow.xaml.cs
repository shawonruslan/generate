using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace MHBrowser;

public partial class ProfileEditWindow : Window
{
    public BrowserProfile Profile { get; }
    private readonly List<SavedProxy> _savedProxies;
    private readonly ObservableCollection<string> _extPaths = new();
    private bool _loading;

    private static readonly (string Vendor, string Renderer)[] DesktopGpus =
    {
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 4060 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 3070 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce GTX 1660 Ti Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) UHD Graphics 770 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon RX 6700 XT Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon RX 7600 Direct3D11 vs_5_0 ps_5_0, D3D11)")
    };

    private static readonly (int W, int H)[] DesktopScreens =
    {
        (1920, 1080), (2560, 1440), (1680, 1050), (1536, 864), (1440, 900), (1366, 768)
    };

    public ProfileEditWindow(BrowserProfile profile)
    {
        InitializeComponent();
        Profile = profile;
        _loading = true;

        CbUaPreset.ItemsSource = UaPresets.All.Select(u => u.Label).ToList();

        _savedProxies = ProxyStore.Load();
        var proxyLabels = new List<string> { "-- Custom / Manual --" };
        proxyLabels.AddRange(_savedProxies.Select(p => p.DisplayLabel));
        CbSavedProxies.ItemsSource = proxyLabels;
        CbSavedProxies.SelectedIndex = 0;

        TxtName.Text = profile.Name;
        TxtGroup.Text = string.IsNullOrWhiteSpace(profile.Group) ? "Default" : profile.Group;
        TxtNotes.Text = profile.Notes;
        TxtStartUrl.Text = profile.StartUrl;
        CbProxyType.SelectedIndex = profile.ProxyType switch
        {
            "HTTP" => 1,
            "HTTPS" => 2,
            "SOCKS5" => 3,
            "OpenVPN" => 4,
            "WireGuard" => 5,
            _ => 0
        };
        TxtProxyHost.Text = profile.ProxyHost;
        TxtProxyPort.Text = profile.ProxyPort;
        TxtProxyUser.Text = profile.ProxyUser;
        TxtProxyPass.Text = profile.ProxyPass;
        TxtVpnConfig.Text = profile.VpnConfigPath;

        CbUaPreset.SelectedIndex = Math.Clamp(profile.UaPresetIndex, 0, UaPresets.All.Length - 1);
        TxtUserAgent.Text = profile.UserAgent;
        TxtPlatform.Text = profile.Platform;
        TxtLanguage.Text = profile.Language;
        TxtScreenW.Text = profile.ScreenW.ToString();
        TxtScreenH.Text = profile.ScreenH.ToString();
        TxtWebGlVendor.Text = profile.WebGlVendor;
        TxtWebGlRenderer.Text = profile.WebGlRenderer;

        ChkAutoTz.IsChecked = profile.AutoTimezone;
        ChkAutoGeo.IsChecked = profile.AutoGeolocation;
        TxtTimezone.Text = profile.Timezone;
        ChkWebRtc.IsChecked = profile.WebRtcProtect;
        ChkWebRtcSpoof.IsChecked = profile.WebRtcSpoofPublicIp;
        ChkNoise.IsChecked = profile.FingerprintNoise;
        ChkWebGl.IsChecked = profile.WebGlSpoof;
        ChkAudio.IsChecked = profile.AudioNoise;
        ChkClientRects.IsChecked = profile.ClientRectsNoise;
        ChkFonts.IsChecked = profile.FontMasking;
        ChkMedia.IsChecked = profile.MediaDeviceSpoof;
        ChkBatteryNet.IsChecked = profile.BatteryNetSpoof;
        ChkSpeechPlugins.IsChecked = profile.SpeechPluginsMask;

        foreach (var ep in profile.ExtensionPaths ?? new List<string>()) _extPaths.Add(ep);
        ExtensionsList.ItemsSource = _extPaths;

        _loading = false;
        UpdateConnectionFieldStates();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
    }

    private void CbSavedProxies_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || CbSavedProxies.SelectedIndex <= 0) return;
        var sp = _savedProxies[CbSavedProxies.SelectedIndex - 1];
        CbProxyType.SelectedIndex = sp.Type switch { "HTTP" => 1, "HTTPS" => 2, "SOCKS5" => 3, _ => 3 };
        TxtProxyHost.Text = sp.Host;
        TxtProxyPort.Text = sp.Port;
        TxtProxyUser.Text = sp.User;
        TxtProxyPass.Text = sp.Pass;
        if (!string.IsNullOrWhiteSpace(sp.Timezone) && sp.Timezone != "-")
            TxtTimezone.Text = sp.Timezone;
        UpdateConnectionFieldStates();
    }

    private void CbProxyType_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        UpdateConnectionFieldStates();
    }

    private void UpdateConnectionFieldStates()
    {
        string mode = GetSelectedProxyType();
        bool isProxy = mode is "HTTP" or "HTTPS" or "SOCKS5";
        TxtProxyHost.IsEnabled = isProxy;
        TxtProxyPort.IsEnabled = isProxy;
        TxtProxyUser.IsEnabled = isProxy;
        TxtProxyPass.IsEnabled = isProxy;
    }

    private void BtnBrowseVpn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "VPN Configs (*.ovpn;*.conf)|*.ovpn;*.conf|OpenVPN (*.ovpn)|*.ovpn|WireGuard (*.conf)|*.conf|All Files|*.*",
            Title = "Select OpenVPN (.ovpn) or WireGuard (.conf) File"
        };
        if (dlg.ShowDialog() == true)
        {
            TxtVpnConfig.Text = dlg.FileName;
            string ext = Path.GetExtension(dlg.FileName).ToLowerInvariant();
            if (ext == ".ovpn") CbProxyType.SelectedIndex = 4;
            else if (ext == ".conf") CbProxyType.SelectedIndex = 5;
            UpdateConnectionFieldStates();
        }
    }

    private void BtnNewFingerprint_Click(object sender, RoutedEventArgs e)
    {
        Profile.NoiseSeed = Random.Shared.Next(1000, 999999);
        int idx = Math.Clamp(CbUaPreset.SelectedIndex, 0, UaPresets.All.Length - 1);
        var preset = UaPresets.All[idx];
        if (!preset.IsMobile && preset.Platform == "Win32")
        {
            var gpu = DesktopGpus[Random.Shared.Next(DesktopGpus.Length)];
            var scr = DesktopScreens[Random.Shared.Next(DesktopScreens.Length)];
            TxtWebGlVendor.Text = gpu.Vendor;
            TxtWebGlRenderer.Text = gpu.Renderer;
            TxtScreenW.Text = scr.W.ToString();
            TxtScreenH.Text = scr.H.ToString();
        }
        Profile.HardwareConcurrency = new[] { 4, 6, 8, 12, 16 }[Random.Shared.Next(5)];
        Profile.DeviceMemoryGb = new[] { 4, 8, 16, 32 }[Random.Shared.Next(4)];
        TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Accent");
        TzDetectInfo.Text = $"Generated new fingerprint seed #{Profile.NoiseSeed} ({Profile.HardwareConcurrency} cores, {Profile.DeviceMemoryGb}GB RAM, {TxtScreenW.Text}x{TxtScreenH.Text})";
    }

    private void BtnAddExtZip_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "Chrome Extension (*.zip;*.crx)|*.zip;*.crx|All Files|*.*",
            Title = "Upload Chrome Extension (.zip or .crx)"
        };
        if (dlg.ShowDialog() != true) return;

        var (ok, folder, msg) = ExtensionHelper.InstallExtension(dlg.FileName);
        if (!ok)
        {
            DarkDialog.ShowInfo(this, "Extension Error", msg);
            return;
        }
        if (!_extPaths.Contains(folder)) _extPaths.Add(folder);
        TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Green");
        TzDetectInfo.Text = $"Extension added: {msg}";
    }

    private void BtnAddExtFolder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Select Unpacked Chrome Extension Folder (containing manifest.json)" };
        if (dlg.ShowDialog() != true) return;
        var (ok, folder, msg) = ExtensionHelper.InstallExtension(dlg.FolderName);
        if (!ok)
        {
            DarkDialog.ShowInfo(this, "Extension Error", msg);
            return;
        }
        if (!_extPaths.Contains(folder)) _extPaths.Add(folder);
        TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Green");
        TzDetectInfo.Text = $"Extension added: {msg}";
    }

    private void BtnRemoveExt_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is string path)
            _extPaths.Remove(path);
    }

    private void CbUaPreset_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || CbUaPreset.SelectedIndex < 0) return;
        var p = UaPresets.All[CbUaPreset.SelectedIndex];
        TxtUserAgent.Text = p.UserAgent;
        TxtPlatform.Text = p.Platform;
        TxtWebGlVendor.Text = p.WebGlVendor;
        TxtWebGlRenderer.Text = p.WebGlRenderer;
        TxtScreenW.Text = p.ScreenW.ToString();
        TxtScreenH.Text = p.ScreenH.ToString();
    }

    private async void BtnDetectTz_Click(object sender, RoutedEventArgs e)
    {
        string mode = GetSelectedProxyType();
        string vpnPath = TxtVpnConfig.Text.Trim();
        TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Accent");

        if (mode is "OpenVPN" or "WireGuard")
        {
            if (string.IsNullOrWhiteSpace(vpnPath) || !File.Exists(vpnPath))
            {
                TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
                TzDetectInfo.Text = $"Select a valid {(mode == "OpenVPN" ? ".ovpn" : ".conf")} file first.";
                return;
            }

            using var tempVpn = new ProfileVpnSession();
            var (okVpn, port, msg) = await tempVpn.StartAsync(
                "probe_" + Guid.NewGuid().ToString("N")[..6],
                mode,
                vpnPath,
                s => Dispatcher.BeginInvoke(() => TzDetectInfo.Text = s));

            if (!okVpn)
            {
                TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
                TzDetectInfo.Text = $"VPN failed: {msg.Split('\n').FirstOrDefault()}";
                return;
            }

            TzDetectInfo.Text = "VPN connected! Detecting exit IP & Timezone...";
            var (okIp, ip, loc, tz, lat, lon) = await IpTimezoneDetector.DetectAsync(null, port);
            if (okIp)
            {
                TxtTimezone.Text = tz;
                TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Green");
                TzDetectInfo.Text = $"VPN Exit: {ip} ({loc}) | TZ: {tz} | Geo: {lat:F2}, {lon:F2}";
            }
            else
            {
                TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
                TzDetectInfo.Text = "VPN connected, but exit IP check failed (no internet through tunnel).";
            }
            return;
        }

        TzDetectInfo.Text = $"Testing {mode} connection & detecting IP/Timezone...";
        var temp = new BrowserProfile
        {
            ProxyType = mode,
            ProxyHost = TxtProxyHost.Text.Trim(),
            ProxyPort = TxtProxyPort.Text.Trim(),
            ProxyUser = TxtProxyUser.Text.Trim(),
            ProxyPass = TxtProxyPass.Text
        };
        var (ok, pIp, pLoc, pTz, pLat, pLon) = await IpTimezoneDetector.DetectAsync(temp);
        if (ok)
        {
            TxtTimezone.Text = pTz;
            TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Green");
            TzDetectInfo.Text = $"Detected: {pIp} ({pLoc}) | TZ: {pTz} | Geo: {pLat:F2}, {pLon:F2}";
        }
        else
        {
            TzDetectInfo.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
            TzDetectInfo.Text = "Could not connect through proxy (check host, port, username/password).";
        }
    }

    private string GetSelectedProxyType() => CbProxyType.SelectedIndex switch
    {
        1 => "HTTP",
        2 => "HTTPS",
        3 => "SOCKS5",
        4 => "OpenVPN",
        5 => "WireGuard",
        _ => "Direct"
    };

    private void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        Profile.Name = string.IsNullOrWhiteSpace(TxtName.Text) ? "Unnamed Profile" : TxtName.Text.Trim();
        Profile.Group = string.IsNullOrWhiteSpace(TxtGroup.Text) ? "Default" : TxtGroup.Text.Trim();
        Profile.Notes = TxtNotes.Text.Trim();
        Profile.StartUrl = string.IsNullOrWhiteSpace(TxtStartUrl.Text) ? "https://whoer.net" : TxtStartUrl.Text.Trim();
        Profile.ProxyType = GetSelectedProxyType();
        Profile.ProxyHost = TxtProxyHost.Text.Trim();
        Profile.ProxyPort = TxtProxyPort.Text.Trim();
        Profile.ProxyUser = TxtProxyUser.Text.Trim();
        Profile.ProxyPass = TxtProxyPass.Text;
        Profile.VpnConfigPath = TxtVpnConfig.Text.Trim();

        int uaIdx = Math.Clamp(CbUaPreset.SelectedIndex, 0, UaPresets.All.Length - 1);
        var preset = UaPresets.All[uaIdx];
        Profile.UaPresetIndex = uaIdx;
        Profile.UserAgent = TxtUserAgent.Text.Trim();
        Profile.Platform = string.IsNullOrWhiteSpace(TxtPlatform.Text) ? preset.Platform : TxtPlatform.Text.Trim();
        Profile.PixelRatio = preset.PixelRatio;
        Profile.IsMobile = preset.IsMobile;
        Profile.WebGlVendor = string.IsNullOrWhiteSpace(TxtWebGlVendor.Text) ? preset.WebGlVendor : TxtWebGlVendor.Text.Trim();
        Profile.WebGlRenderer = string.IsNullOrWhiteSpace(TxtWebGlRenderer.Text) ? preset.WebGlRenderer : TxtWebGlRenderer.Text.Trim();
        Profile.ScreenW = int.TryParse(TxtScreenW.Text.Trim(), out int sw) ? Math.Clamp(sw, 320, 7680) : preset.ScreenW;
        Profile.ScreenH = int.TryParse(TxtScreenH.Text.Trim(), out int sh) ? Math.Clamp(sh, 320, 4320) : preset.ScreenH;
        Profile.Language = string.IsNullOrWhiteSpace(TxtLanguage.Text) ? "en-US" : TxtLanguage.Text.Trim();

        Profile.AutoTimezone = ChkAutoTz.IsChecked == true;
        Profile.AutoGeolocation = ChkAutoGeo.IsChecked == true;
        Profile.Timezone = TxtTimezone.Text.Trim();
        Profile.WebRtcProtect = ChkWebRtc.IsChecked == true;
        Profile.WebRtcSpoofPublicIp = ChkWebRtcSpoof.IsChecked == true;
        Profile.FingerprintNoise = ChkNoise.IsChecked == true;
        Profile.WebGlSpoof = ChkWebGl.IsChecked == true;
        Profile.AudioNoise = ChkAudio.IsChecked == true;
        Profile.ClientRectsNoise = ChkClientRects.IsChecked == true;
        Profile.FontMasking = ChkFonts.IsChecked == true;
        Profile.MediaDeviceSpoof = ChkMedia.IsChecked == true;
        Profile.BatteryNetSpoof = ChkBatteryNet.IsChecked == true;
        Profile.SpeechPluginsMask = ChkSpeechPlugins.IsChecked == true;
        Profile.ExtensionPaths = _extPaths.ToList();

        Profile.NotifyAll();
        DialogResult = true;
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
