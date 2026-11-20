using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace MHBrowser;

public sealed record UaPreset(
    string Label, string UserAgent, string Platform,
    int Cores, int MemoryGb,
    string WebGlVendor, string WebGlRenderer,
    int ScreenW, int ScreenH, double PixelRatio, bool IsMobile);

public static class UaPresets
{
    public static readonly UaPreset[] All =
    {
        new("[PC] Windows 11 - Chrome 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "Win32", 8, 16, "Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 4060 Direct3D11 vs_5_0 ps_5_0, D3D11)", 1920, 1080, 1.0, false),
        new("[PC] Windows 11 - Edge 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0", "Win32", 8, 16, "Google Inc. (Intel)", "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics Direct3D11 vs_5_0 ps_5_0, D3D11)", 1920, 1080, 1.0, false),
        new("[PC] Windows 11 - Firefox 133", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0", "Win32", 12, 16, "Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon RX 6700 XT Direct3D11 vs_5_0 ps_5_0, D3D11)", 2560, 1440, 1.0, false),
        new("[PC] macOS Sequoia - Safari 18", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15", "MacIntel", 10, 16, "Apple Inc.", "Apple M3 Pro", 1728, 1117, 2.0, false),
        new("[PC] macOS Sequoia - Chrome 131", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "MacIntel", 10, 16, "Google Inc. (Apple)", "ANGLE (Apple, ANGLE Metal Renderer: Apple M3, Unspecified Version)", 1512, 982, 2.0, false),
        new("[PC] Ubuntu Linux - Chrome 131", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "Linux x86_64", 8, 16, "Mesa", "Mesa Intel(R) UHD Graphics 770 (ADL-S GT1)", 1920, 1080, 1.0, false),

        new("[Mobile] iPhone 16 Pro (iOS 18 Safari)", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPhone", 6, 8, "Apple Inc.", "Apple GPU", 402, 874, 3.0, true),
        new("[Mobile] iPhone 15 (iOS 17 Chrome)", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 Mobile/15E148 Safari/604.1", "iPhone", 6, 6, "Apple Inc.", "Apple GPU", 393, 852, 3.0, true),
        new("[Mobile] Samsung Galaxy S25 Ultra (Android 15)", "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12, "Qualcomm", "Adreno (TM) 830", 412, 915, 3.5, true),
        new("[Mobile] Google Pixel 9 Pro (Android 15)", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 16, "ARM", "Mali-G715", 412, 915, 3.0, true),
        new("[Mobile] OnePlus 13 (Android 15)", "Mozilla/5.0 (Linux; Android 15; CPH2653) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12, "Qualcomm", "Adreno (TM) 830", 412, 915, 3.0, true),
        new("[Mobile] Xiaomi 15 Pro (Android 15)", "Mozilla/5.0 (Linux; Android 15; 24101PNB7C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12, "Qualcomm", "Adreno (TM) 830", 412, 915, 3.0, true),
        new("[Tablet] iPad Pro M4 (iPadOS 18)", "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPad", 10, 8, "Apple Inc.", "Apple GPU", 1024, 1366, 2.0, true),

        new("[TV] Samsung Tizen Smart TV", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 8.0) AppleWebKit/537.36 (KHTML, like Gecko) 108.0.5359.125/8.0 TV Safari/537.36", "Linux armv7l", 4, 4, "ARM", "Mali-G52", 1920, 1080, 1.0, false),
        new("[TV] LG webOS Smart TV", "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.5359.211 Safari/537.36 WebAppManager", "Linux armv7l", 4, 4, "ARM", "Mali-G57", 1920, 1080, 1.0, false),
        new("[TV] Android TV / Google TV", "Mozilla/5.0 (Linux; Android 14; Chromecast HD) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Linux armv8l", 4, 2, "ARM", "Mali-G31", 1920, 1080, 1.0, false),
        new("[TV] Amazon Fire TV Stick 4K", "Mozilla/5.0 (Linux; Android 11; AFTKA Build/RS8149) AppleWebKit/537.36 (KHTML, like Gecko) Silk/130.3.2 like Chrome/130.0.6723.102 Safari/537.36", "Linux armv8l", 4, 2, "Imagination Technologies", "PowerVR Rogue GE8300", 1920, 1080, 1.0, false),

        new("[Console] PlayStation 5 (PS5)", "Mozilla/5.0 (PlayStation; PlayStation 5/9.60) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", "PlayStation 5", 8, 16, "AMD", "AMD Radeon RDNA 2", 1920, 1080, 1.0, false),
        new("[Console] PlayStation 4 (PS4)", "Mozilla/5.0 (PlayStation 4 11.50) AppleWebKit/605.1.15 (KHTML, like Gecko)", "PlayStation 4", 8, 8, "AMD", "AMD Radeon GCN", 1920, 1080, 1.0, false),
        new("[Console] Xbox Series X", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox Series X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edge/44.18363.8131", "Win32", 8, 16, "AMD", "AMD Radeon RDNA 2", 1920, 1080, 1.0, false),
        new("[Console] Nintendo Switch", "Mozilla/5.0 (Nintendo Switch; WifiWebAuthApplet) AppleWebKit/609.4 (KHTML, like Gecko) NF/6.0.2.21.3 NintendoBrowser/5.1.0.22474", "Nintendo Switch", 4, 4, "NVIDIA Corporation", "NVIDIA Tegra X1", 1280, 720, 1.0, false),
        new("[Console] Valve Steam Deck", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Valve Steam GameOverlay/1730000000 Chrome/131.0.0.0 Safari/537.36", "Linux x86_64", 8, 16, "AMD", "AMD Custom GPU 0405 (RADV VANGOGH)", 1280, 800, 1.0, false)
    };
}

public sealed class BookmarkItem
{
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";
}

public sealed class HistoryItem
{
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";
    public string VisitedAt { get; set; } = "";
}

public static class SearchEngines
{
    public static readonly (string Name, string UrlTemplate)[] All =
    {
        ("Google", "https://www.google.com/search?q={0}"),
        ("DuckDuckGo", "https://duckduckgo.com/?q={0}"),
        ("Bing", "https://www.bing.com/search?q={0}"),
        ("Brave Search", "https://search.brave.com/search?q={0}"),
        ("Yahoo", "https://search.yahoo.com/search?p={0}"),
        ("Yandex", "https://yandex.com/search/?text={0}")
    };

    public static string BuildSearchUrl(string engineName, string query)
    {
        var match = All.FirstOrDefault(e => e.Name.Equals(engineName, StringComparison.OrdinalIgnoreCase));
        string tpl = string.IsNullOrEmpty(match.UrlTemplate) ? All[0].UrlTemplate : match.UrlTemplate;
        return string.Format(tpl, Uri.EscapeDataString(query));
    }
}

public sealed class BrowserProfile : INotifyPropertyChanged
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..12];
    public string Name { get; set; } = "Profile 1";
    public string Notes { get; set; } = "";
    public string Group { get; set; } = "Default";
    public string ProxyType { get; set; } = "Direct"; // Direct, HTTP, HTTPS, SOCKS5, OpenVPN, WireGuard
    public string ProxyHost { get; set; } = "";
    public string ProxyPort { get; set; } = "";
    public string ProxyUser { get; set; } = "";
    public string ProxyPass { get; set; } = "";
    public string VpnConfigPath { get; set; } = "";   // .ovpn or .conf path per profile
    public int UaPresetIndex { get; set; } = 0;
    public string UserAgent { get; set; } = UaPresets.All[0].UserAgent;
    public string Platform { get; set; } = UaPresets.All[0].Platform;
    public int HardwareConcurrency { get; set; } = 8;
    public int DeviceMemoryGb { get; set; } = 16;
    public string WebGlVendor { get; set; } = UaPresets.All[0].WebGlVendor;
    public string WebGlRenderer { get; set; } = UaPresets.All[0].WebGlRenderer;
    public int ScreenW { get; set; } = 1920;
    public int ScreenH { get; set; } = 1080;
    public double PixelRatio { get; set; } = 1.0;
    public bool IsMobile { get; set; } = false;
    public string Language { get; set; } = "en-US";
    public bool AutoTimezone { get; set; } = true;
    public string Timezone { get; set; } = "";
    public bool AutoGeolocation { get; set; } = true;
    public bool WebRtcProtect { get; set; } = true;
    public bool FingerprintNoise { get; set; } = true;
    public bool WebGlSpoof { get; set; } = true;
    public bool AudioNoise { get; set; } = true;
    public bool FontMasking { get; set; } = true;
    public bool ClientRectsNoise { get; set; } = true;
    public bool WebRtcSpoofPublicIp { get; set; } = true;
    public bool MediaDeviceSpoof { get; set; } = true;
    public bool BatteryNetSpoof { get; set; } = true;
    public bool SpeechPluginsMask { get; set; } = true;
    public List<string> ExtensionPaths { get; set; } = new();
    public int NoiseSeed { get; set; } = Random.Shared.Next(1, 999999);
    public string StartUrl { get; set; } = "https://whoer.net";
    public string SearchEngine { get; set; } = "Google";
    public List<string> SavedTabs { get; set; } = new();
    public int ActiveTabIndex { get; set; } = 0;
    public List<BookmarkItem> Bookmarks { get; set; } = new();
    public List<HistoryItem> History { get; set; } = new();

    private bool _isRunning;
    public bool IsRunning
    {
        get => _isRunning;
        set { _isRunning = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusLabel)); }
    }

    public string StatusLabel => IsRunning ? "RUNNING" : "READY";
    public string ProxySummary
    {
        get
        {
            if (ProxyType is "OpenVPN" or "WireGuard")
                return string.IsNullOrWhiteSpace(VpnConfigPath) ? ProxyType : $"{ProxyType}: {Path.GetFileName(VpnConfigPath)}";
            if (ProxyType == "Direct" || string.IsNullOrWhiteSpace(ProxyHost))
                return "Direct";
            return $"{ProxyType}://{ProxyHost}:{ProxyPort}";
        }
    }
    public string DeviceSummary => UaPresetIndex >= 0 && UaPresetIndex < UaPresets.All.Length
        ? UaPresets.All[UaPresetIndex].Label
        : "Custom UA";
    public string TimezoneSummary => AutoTimezone
        ? (string.IsNullOrWhiteSpace(Timezone) ? "Auto (IP)" : $"Auto ({Timezone})")
        : (string.IsNullOrWhiteSpace(Timezone) ? "System" : Timezone);

    public string UserDataDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHAdvancedTool", "BrowserProfiles", Id);

    public BrowserProfile Clone() => new()
    {
        Id = Guid.NewGuid().ToString("N")[..12],
        Name = Name + " (Copy)",
        Notes = Notes,
        ProxyType = ProxyType,
        ProxyHost = ProxyHost,
        ProxyPort = ProxyPort,
        ProxyUser = ProxyUser,
        ProxyPass = ProxyPass,
        VpnConfigPath = VpnConfigPath,
        UaPresetIndex = UaPresetIndex,
        UserAgent = UserAgent,
        Platform = Platform,
        HardwareConcurrency = HardwareConcurrency,
        DeviceMemoryGb = DeviceMemoryGb,
        WebGlVendor = WebGlVendor,
        WebGlRenderer = WebGlRenderer,
        ScreenW = ScreenW,
        ScreenH = ScreenH,
        PixelRatio = PixelRatio,
        IsMobile = IsMobile,
        Language = Language,
        AutoTimezone = AutoTimezone,
        Timezone = Timezone,
        AutoGeolocation = AutoGeolocation,
        WebRtcProtect = WebRtcProtect,
        FingerprintNoise = FingerprintNoise,
        WebGlSpoof = WebGlSpoof,
        AudioNoise = AudioNoise,
        Group = Group,
        FontMasking = FontMasking,
        ClientRectsNoise = ClientRectsNoise,
        WebRtcSpoofPublicIp = WebRtcSpoofPublicIp,
        MediaDeviceSpoof = MediaDeviceSpoof,
        BatteryNetSpoof = BatteryNetSpoof,
        SpeechPluginsMask = SpeechPluginsMask,
        ExtensionPaths = new List<string>(ExtensionPaths),
        NoiseSeed = Random.Shared.Next(1, 999999),
        StartUrl = StartUrl,
        SearchEngine = SearchEngine
    };

    public event PropertyChangedEventHandler? PropertyChanged;
    public void NotifyAll()
    {
        OnPropertyChanged(nameof(Name));
        OnPropertyChanged(nameof(Notes));
        OnPropertyChanged(nameof(Group));
        OnPropertyChanged(nameof(ProxySummary));
        OnPropertyChanged(nameof(DeviceSummary));
        OnPropertyChanged(nameof(TimezoneSummary));
    }
    private void OnPropertyChanged([CallerMemberName] string? n = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
}

public static class ProfileStore
{
    private static readonly string StorePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHAdvancedTool", "profiles.json");

    public static List<BrowserProfile> Load()
    {
        try
        {
            if (File.Exists(StorePath))
            {
                var list = JsonSerializer.Deserialize<List<BrowserProfile>>(File.ReadAllText(StorePath));
                if (list is { Count: > 0 }) return list;
            }
        }
        catch { }
        return new List<BrowserProfile>
        {
            new() { Name = "Default Desktop", Notes = "Windows 11 Chrome + HD USB Webcam", StartUrl = "https://whoer.net" },
            new() { Name = "iPhone 16 Pro", Notes = "iOS 18 Mobile Fingerprint", UaPresetIndex = 6, UserAgent = UaPresets.All[6].UserAgent, Platform = UaPresets.All[6].Platform, HardwareConcurrency = 6, DeviceMemoryGb = 8, WebGlVendor = UaPresets.All[6].WebGlVendor, WebGlRenderer = UaPresets.All[6].WebGlRenderer, ScreenW = 402, ScreenH = 874, PixelRatio = 3.0, IsMobile = true, StartUrl = "https://whoer.net" }
        };
    }

    public static void Save(IEnumerable<BrowserProfile> profiles)
    {
        try
        {
            var dir = Path.GetDirectoryName(StorePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(profiles.ToList(), new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(StorePath, json);
        }
        catch { }
    }
}

public static class IpTimezoneDetector
{
    public static async Task<(bool Ok, string Ip, string Location, string Timezone, double Lat, double Lon)> DetectAsync(
        BrowserProfile? profile, int localSocksPort = 0)
    {
        try
        {
            var handler = new HttpClientHandler();
            if (localSocksPort > 0)
            {
                handler.Proxy = new WebProxy($"socks5://127.0.0.1:{localSocksPort}");
                handler.UseProxy = true;
            }
            else if (profile is not null && !string.IsNullOrWhiteSpace(profile.ProxyHost) && !string.IsNullOrWhiteSpace(profile.ProxyPort) &&
                     profile.ProxyType is "HTTP" or "HTTPS" or "SOCKS5")
            {
                if (profile.ProxyType == "SOCKS5" && int.TryParse(profile.ProxyPort, out int sp))
                {
                    using var fwd = new LocalSocks5AuthForwarder(profile.ProxyHost, sp, profile.ProxyUser, profile.ProxyPass);
                    return await DetectAsync(null, fwd.Port);
                }
                var proxy = new WebProxy($"http://{profile.ProxyHost}:{profile.ProxyPort}");
                if (!string.IsNullOrWhiteSpace(profile.ProxyUser))
                    proxy.Credentials = new NetworkCredential(profile.ProxyUser, profile.ProxyPass);
                handler.Proxy = proxy;
                handler.UseProxy = true;
            }

            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(10) };
            var json = await client.GetStringAsync("http://ip-api.com/json/?fields=status,query,country,city,timezone,lat,lon");
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            string tz = root.TryGetProperty("timezone", out var tzEl) ? (tzEl.GetString() ?? "") : "";
            string ip = root.TryGetProperty("query", out var ipEl) ? (ipEl.GetString() ?? "") : "";
            string city = root.TryGetProperty("city", out var cEl) ? (cEl.GetString() ?? "") : "";
            string country = root.TryGetProperty("country", out var coEl) ? (coEl.GetString() ?? "") : "";
            double lat = root.TryGetProperty("lat", out var latEl) && latEl.TryGetDouble(out var lv) ? lv : 0;
            double lon = root.TryGetProperty("lon", out var lonEl) && lonEl.TryGetDouble(out var lnv) ? lnv : 0;
            string loc = string.IsNullOrEmpty(city) ? country : $"{city}, {country}";
            if (!string.IsNullOrEmpty(tz)) return (true, ip, loc, tz, lat, lon);
        }
        catch { }
        return (false, "", "", "", 0, 0);
    }
}

public static class VpnController
{
    private static string ExeDir => AppDomain.CurrentDomain.BaseDirectory;
    private static string VpnWorkDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHAdvancedTool", "vpn");

    public static string? FindOpenVpn()
    {
        string[] paths =
        {
            Path.Combine(ExeDir, "vpn", "openvpn", "openvpn.exe"),
            Path.GetFullPath(Path.Combine(ExeDir, "..", "vpn", "openvpn", "openvpn.exe")),
            @"C:\Program Files\OpenVPN\bin\openvpn.exe",
            @"C:\Program Files (x86)\OpenVPN\bin\openvpn.exe"
        };
        return paths.FirstOrDefault(File.Exists);
    }

    public static string? FindWireProxy()
    {
        string[] paths =
        {
            Path.Combine(ExeDir, "vpn", "wireguard", "wireproxy.exe"),
            Path.GetFullPath(Path.Combine(ExeDir, "..", "vpn", "wireguard", "wireproxy.exe"))
        };
        return paths.FirstOrDefault(File.Exists);
    }

    public static string? FindWireGuard()
    {
        string[] paths =
        {
            Path.Combine(ExeDir, "vpn", "wireguard", "wireguard.exe"),
            Path.GetFullPath(Path.Combine(ExeDir, "..", "vpn", "wireguard", "wireguard.exe")),
            @"C:\Program Files\WireGuard\wireguard.exe",
            @"C:\Program Files (x86)\WireGuard\wireguard.exe"
        };
        return paths.FirstOrDefault(File.Exists);
    }

    public static (bool Ok, string Message) ConnectOpenVpn(string ovpnFile)
    {
        if (!File.Exists(ovpnFile)) return (false, "Select a valid .ovpn file first.");
        var exe = FindOpenVpn();
        if (exe is null) return (false, "OpenVPN binary not found in app folder.");
        Directory.CreateDirectory(VpnWorkDir);
        var dst = Path.Combine(VpnWorkDir, "active.ovpn");
        File.Copy(ovpnFile, dst, overwrite: true);
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = $"--windows-driver wintun --data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-256-CBC --data-ciphers-fallback AES-128-CBC --config \"{dst}\"",
                WorkingDirectory = Path.GetDirectoryName(exe) ?? ExeDir,
                UseShellExecute = false,
                CreateNoWindow = true
            });
            return (true, $"System OpenVPN connecting silently: {Path.GetFileName(ovpnFile)}");
        }
        catch (Exception ex) { return (false, $"OpenVPN launch failed: {ex.Message}"); }
    }

    public static (bool Ok, string Message) DisconnectOpenVpn()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "taskkill.exe",
                Arguments = "/F /IM openvpn.exe",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            return (true, "OpenVPN disconnected.");
        }
        catch (Exception ex) { return (false, ex.Message); }
    }

    public static (bool Ok, string Message) ConnectWireGuard(string confFile)
    {
        if (!File.Exists(confFile)) return (false, "Select a valid WireGuard .conf file first.");
        var exe = FindWireGuard();
        if (exe is null) return (false, "WireGuard binary not found in app folder.");
        Directory.CreateDirectory(VpnWorkDir);
        var dst = Path.Combine(VpnWorkDir, "mhbrowser_wg.conf");
        File.Copy(confFile, dst, overwrite: true);
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = $"/installtunnelservice \"{dst}\"",
                WorkingDirectory = Path.GetDirectoryName(exe) ?? ExeDir,
                UseShellExecute = false,
                CreateNoWindow = true
            });
            return (true, $"System WireGuard tunnel activated: {Path.GetFileName(confFile)}");
        }
        catch (Exception ex) { return (false, $"WireGuard failed: {ex.Message}"); }
    }

    public static (bool Ok, string Message) DisconnectWireGuard()
    {
        var exe = FindWireGuard();
        if (exe is null) return (false, "WireGuard binary not found.");
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "/uninstalltunnelservice mhbrowser_wg",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            return (true, "WireGuard tunnel disconnected.");
        }
        catch (Exception ex) { return (false, ex.Message); }
    }
}
