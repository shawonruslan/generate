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
            _ => 0
        };
        TxtProxyHost.Text = profile.ProxyHost;
        TxtProxyPort.Text = profile.ProxyPort;
        TxtProxyUser.Text = profile.ProxyUser;
        TxtProxyPass.Text = profile.ProxyPass;

        CbUaPreset.SelectedIndex = Math.Clamp(profile.UaPresetIndex, 0, UaPresets.All.Length - 1);
        TxtUserAgent.Text = profile.UserAgent;
        TxtPlatform.Text = profile.Platform;
        TxtLanguage.Text = profile.Language;

        ChkAutoTz.IsChecked = profile.AutoTimezone;
        TxtTimezone.Text = profile.Timezone;
        ChkWebRtc.IsChecked = profile.WebRtcProtect;
        ChkNoise.IsChecked = profile.FingerprintNoise;

        _loading = false;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
    }

    private void CbUaPreset_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || CbUaPreset.SelectedIndex < 0) return;
        var p = UaPresets.All[CbUaPreset.SelectedIndex];
        TxtUserAgent.Text = p.UserAgent;
        TxtPlatform.Text = p.Platform;
    }

    private async void BtnDetectTz_Click(object sender, RoutedEventArgs e)
    {
        TzDetectInfo.Text = "Checking IP & Timezone...";
        var temp = new BrowserProfile
        {
            ProxyType = GetSelectedProxyType(),
            ProxyHost = TxtProxyHost.Text.Trim(),
            ProxyPort = TxtProxyPort.Text.Trim(),
            ProxyUser = TxtProxyUser.Text.Trim(),
            ProxyPass = TxtProxyPass.Text
        };
        var (ok, ip, loc, tz) = await IpTimezoneDetector.DetectAsync(temp);
        if (ok)
        {
            TxtTimezone.Text = tz;
            TzDetectInfo.Text = $"Detected: {ip} ({loc}) -> {tz}";
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

        int uaIdx = Math.Clamp(CbUaPreset.SelectedIndex, 0, UaPresets.All.Length - 1);
        Profile.UaPresetIndex = uaIdx;
        Profile.UserAgent = TxtUserAgent.Text.Trim();
        Profile.Platform = string.IsNullOrWhiteSpace(TxtPlatform.Text) ? UaPresets.All[uaIdx].Platform : TxtPlatform.Text.Trim();
        Profile.HardwareConcurrency = UaPresets.All[uaIdx].Cores;
        Profile.DeviceMemoryGb = UaPresets.All[uaIdx].MemoryGb;
        Profile.Language = string.IsNullOrWhiteSpace(TxtLanguage.Text) ? "en-US" : TxtLanguage.Text.Trim();

        Profile.AutoTimezone = ChkAutoTz.IsChecked == true;
        Profile.Timezone = TxtTimezone.Text.Trim();
        Profile.WebRtcProtect = ChkWebRtc.IsChecked == true;
        Profile.FingerprintNoise = ChkNoise.IsChecked == true;

        Profile.NotifyAll();
        DialogResult = true;
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
