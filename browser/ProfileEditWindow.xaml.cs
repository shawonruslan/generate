using Microsoft.Win32;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace MHBrowser;

public partial class ProfileEditWindow : Window
{
    public BrowserProfile Profile { get; }
    private bool _loading;

    public ProfileEditWindow(BrowserProfile profile)
    {
        InitializeComponent();
        Profile = profile;
        _loading = true;

        CbUaPreset.ItemsSource = UaPresets.All.Select(u => u.Label).ToList();

        TxtName.Text = profile.Name;
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
        ChkNoise.IsChecked = profile.FingerprintNoise;
        ChkWebGl.IsChecked = profile.WebGlSpoof;
        ChkAudio.IsChecked = profile.AudioNoise;

        _loading = false;
        UpdateConnectionFieldStates();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
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
        TzDetectInfo.Text = "Checking IP, Timezone & Geolocation...";
        var temp = new BrowserProfile
        {
            ProxyType = GetSelectedProxyType(),
            ProxyHost = TxtProxyHost.Text.Trim(),
            ProxyPort = TxtProxyPort.Text.Trim(),
            ProxyUser = TxtProxyUser.Text.Trim(),
            ProxyPass = TxtProxyPass.Text
        };
        var (ok, ip, loc, tz, lat, lon) = await IpTimezoneDetector.DetectAsync(temp);
        if (ok)
        {
            TxtTimezone.Text = tz;
            TzDetectInfo.Text = $"Detected: {ip} ({loc}) | TZ: {tz} | Geo: {lat:F2}, {lon:F2}";
        }
        else
        {
            TzDetectInfo.Text = "Could not detect IP/Timezone (check internet or proxy).";
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
        Profile.HardwareConcurrency = preset.Cores;
        Profile.DeviceMemoryGb = preset.MemoryGb;
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
        Profile.FingerprintNoise = ChkNoise.IsChecked == true;
        Profile.WebGlSpoof = ChkWebGl.IsChecked == true;
        Profile.AudioNoise = ChkAudio.IsChecked == true;

        Profile.NotifyAll();
        DialogResult = true;
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
