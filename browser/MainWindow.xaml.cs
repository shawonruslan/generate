using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace MHBrowser;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<BrowserProfile> _allProfiles = new();
    private readonly ObservableCollection<BrowserProfile> _filteredProfiles = new();
    private readonly Dictionary<string, BrowserWindow> _openWindows = new();

    public MainWindow()
    {
        InitializeComponent();
        foreach (var p in ProfileStore.Load()) _allProfiles.Add(p);
        ProfilesList.ItemsSource = _filteredProfiles;
        RefreshFilter();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
    }

    private void RefreshFilter()
    {
        string q = SearchBox?.Text?.Trim() ?? "";
        _filteredProfiles.Clear();
        foreach (var p in _allProfiles)
        {
            if (string.IsNullOrEmpty(q) ||
                p.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                p.Notes.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                p.ProxySummary.Contains(q, StringComparison.OrdinalIgnoreCase))
            {
                _filteredProfiles.Add(p);
            }
        }
        SidebarCountText.Text = $"{_allProfiles.Count} Profile{(_allProfiles.Count == 1 ? "" : "s")}";
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshFilter();

    private void NavProfiles_Click(object sender, RoutedEventArgs e)
    {
        ProfilesView.Visibility = Visibility.Visible;
        VpnView.Visibility = Visibility.Collapsed;
        PageTitleText.Text = "Browser Profiles";
        SearchBox.Visibility = Visibility.Visible;
        BtnCreateProfile.Visibility = Visibility.Visible;
    }

    private void NavVpn_Click(object sender, RoutedEventArgs e)
    {
        ProfilesView.Visibility = Visibility.Collapsed;
        VpnView.Visibility = Visibility.Visible;
        PageTitleText.Text = "VPN Manager (OpenVPN / WireGuard)";
        SearchBox.Visibility = Visibility.Collapsed;
        BtnCreateProfile.Visibility = Visibility.Collapsed;
    }

    private void BtnCreateProfile_Click(object sender, RoutedEventArgs e)
    {
        var p = new BrowserProfile { Name = $"Profile {_allProfiles.Count + 1}" };
        var dlg = new ProfileEditWindow(p) { Owner = this };
        if (dlg.ShowDialog() == true)
        {
            _allProfiles.Add(p);
            ProfileStore.Save(_allProfiles);
            RefreshFilter();
            StatusText.Text = $"Created profile: {p.Name}";
        }
    }

    private void BtnRunProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        if (_openWindows.TryGetValue(profile.Id, out var existing) && existing.IsLoaded)
        {
            existing.Activate();
            return;
        }
        var win = new BrowserWindow(profile);
        win.Closed += (_, _) => _openWindows.Remove(profile.Id);
        _openWindows[profile.Id] = win;
        win.Show();
        StatusText.Text = $"Launched isolated Chromium window for '{profile.Name}'";
    }

    private void BtnEditProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        var dlg = new ProfileEditWindow(profile) { Owner = this };
        if (dlg.ShowDialog() == true)
        {
            ProfileStore.Save(_allProfiles);
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
        RefreshFilter();
        StatusText.Text = $"Cloned profile: {copy.Name}";
    }

    private void BtnDeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not BrowserProfile profile) return;
        if (MessageBox.Show(this, $"Delete profile '{profile.Name}' and its browser data?", "Delete Profile",
            MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;

        if (_openWindows.TryGetValue(profile.Id, out var win)) { win.Close(); _openWindows.Remove(profile.Id); }
        _allProfiles.Remove(profile);
        ProfileStore.Save(_allProfiles);
        try { if (Directory.Exists(profile.UserDataDir)) Directory.Delete(profile.UserDataDir, true); } catch { }
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
        var (ok, ip, loc, tz) = await IpTimezoneDetector.DetectAsync(null);
        GlobalIpText.Text = ok ? $"IP: {ip}  |  {loc}  |  Timezone: {tz}" : "Could not detect IP/Timezone.";
    }
}
