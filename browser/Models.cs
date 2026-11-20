using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace MHBrowser;

public sealed record UaPreset(string Label, string UserAgent, string Platform, int Cores, int MemoryGb);

public static class UaPresets
{
    public static readonly UaPreset[] All =
    {
        new("[Default] Windows 11 - Chrome 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "Win32", 8, 16),
        new("[PC] Windows 11 - Edge 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0", "Win32", 8, 16),
        new("[PC] Windows 11 - Firefox 133", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0", "Win32", 8, 16),
        new("[PC] macOS Sequoia - Safari 18", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15", "MacIntel", 10, 16),
        new("[PC] macOS Sequoia - Chrome 131", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "MacIntel", 10, 16),
        new("[PC] Ubuntu Linux - Chrome 131", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "Linux x86_64", 8, 16),
        new("[Mobile] iPhone 16 Pro (iOS 18 Safari)", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPhone", 6, 8),
        new("[Mobile] iPhone 15 (iOS 17 Chrome)", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 Mobile/15E148 Safari/604.1", "iPhone", 6, 6),
        new("[Mobile] Samsung Galaxy S25 Ultra (Android 15)", "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12),
        new("[Mobile] Google Pixel 9 Pro (Android 15)", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12),
        new("[Mobile] OnePlus 13 (Android 15)", "Mozilla/5.0 (Linux; Android 15; CPH2653) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12),
        new("[Mobile] Xiaomi 15 Pro (Android 15)", "Mozilla/5.0 (Linux; Android 15; 24101PNB7C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l", 8, 12),
        new("[Tablet] iPad Pro M4 (iPadOS 18)", "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPad", 8, 8),
        new("[TV] Samsung Tizen Smart TV", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 8.0) AppleWebKit/537.36 (KHTML, like Gecko) 108.0.5359.125/8.0 TV Safari/537.36", "Linux armv7l", 4, 4),
        new("[TV] LG webOS Smart TV", "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.5359.211 Safari/537.36 WebAppManager", "Linux armv7l", 4, 4),
        new("[TV] Android TV / Google TV", "Mozilla/5.0 (Linux; Android 14; Chromecast HD) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Linux armv8l", 4, 4),
        new("[TV] Amazon Fire TV Stick 4K", "Mozilla/5.0 (Linux; Android 11; AFTKA Build/RS8149) AppleWebKit/537.36 (KHTML, like Gecko) Silk/130.3.2 like Chrome/130.0.6723.102 Safari/537.36", "Linux armv8l", 4, 2),
        new("[Console] PlayStation 5 (PS5)", "Mozilla/5.0 (PlayStation; PlayStation 5/9.60) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", "PlayStation 5", 8, 16),
        new("[Console] PlayStation 4 (PS4)", "Mozilla/5.0 (PlayStation 4 11.50) AppleWebKit/605.1.15 (KHTML, like Gecko)", "PlayStation 4", 8, 8),
        new("[Console] Xbox Series X", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox Series X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edge/44.18363.8131", "Win32", 8, 16),
        new("[Console] Nintendo Switch", "Mozilla/5.0 (Nintendo Switch; WifiWebAuthApplet) AppleWebKit/609.4 (KHTML, like Gecko) NF/6.0.2.21.3 NintendoBrowser/5.1.0.22474", "Nintendo Switch", 4, 4),
        new("[Console] Valve Steam Deck", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Valve Steam GameOverlay/1730000000 Chrome/131.0.0.0 Safari/537.36", "Linux x86_64", 8, 16)
    };
}

public sealed class BrowserProfile : INotifyPropertyChanged
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..12];
    public string Name { get; set; } = "Profile 1";
    public string Notes { get; set; } = "";
    public string ProxyType { get; set; } = "Direct"; // Direct, HTTP, HTTPS, SOCKS5
    public string ProxyHost { get; set; } = "";
    public string ProxyPort { get; set; } = "";
    public string ProxyUser { get; set; } = "";
    public string ProxyPass { get; set; } = "";
    public int UaPresetIndex { get; set; } = 0;
    public string UserAgent { get; set; } = UaPresets.All[0].UserAgent;
    public string Platform { get; set; } = UaPresets.All[0].Platform;
    public int HardwareConcurrency { get; set; } = 8;
    public int DeviceMemoryGb { get; set; } = 16;
    public string Language { get; set; } = "en-US";
    public bool AutoTimezone { get; set; } = true;
    public string Timezone { get; set; } = "";
    public bool WebRtcProtect { get; set; } = true;
    public bool FingerprintNoise { get; set; } = true;
    public int NoiseSeed { get; set; } = Random.Shared.Next(1, 999999);
    public string StartUrl { get; set; } = "https://whoer.net";

    private bool _isRunning;
    public bool IsRunning
    {
        get => _isRunning;
        set { _isRunning = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusLabel)); }
    }

    public string StatusLabel => IsRunning ? "RUNNING" : "READY";
    public string ProxySummary => ProxyType == "Direct" || string.IsNullOrWhiteSpace(ProxyHost)
        ? "Direct / VPN"
        : $"{ProxyType}://{ProxyHost}:{ProxyPort}";
    public string DeviceSummary => UaPresetIndex >= 0 && UaPresetIndex < UaPresets.All.Length
        ? UaPresets.All[UaPresetIndex].Label
        : "Custom UA";
    public string TimezoneSummary => AutoTimezone
        ? (string.IsNullOrWhiteSpace(Timezone) ? "Auto (IP)" : $"Auto ({Timezone})")
        : (string.IsNullOrWhiteSpace(Timezone) ? "System" : Timezone);

    public string UserDataDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHVirtualCam", "BrowserProfiles", Id);

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
        UaPresetIndex = UaPresetIndex,
        UserAgent = UserAgent,
        Platform = Platform,
        HardwareConcurrency = HardwareConcurrency,
        DeviceMemoryGb = DeviceMemoryGb,
        Language = Language,
        AutoTimezone = AutoTimezone,
        Timezone = Timezone,
        WebRtcProtect = WebRtcProtect,
        FingerprintNoise = FingerprintNoise,
        NoiseSeed = Random.Shared.Next(1, 999999),
        StartUrl = StartUrl
    };

    public event PropertyChangedEventHandler? PropertyChanged;
    public void NotifyAll()
    {
        OnPropertyChanged(nameof(Name));
        OnPropertyChanged(nameof(Notes));
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
        "MHVirtualCam", "profiles.json");

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
            new() { Name = "iPhone 16 Pro", Notes = "Mobile Profile", UaPresetIndex = 6, UserAgent = UaPresets.All[6].UserAgent, Platform = UaPresets.All[6].Platform, HardwareConcurrency = 6, DeviceMemoryGb = 8, StartUrl = "https://whoer.net" }
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
    public static async Task<(bool Ok, string Ip, string Location, string Timezone)> DetectAsync(BrowserProfile? profile)
    {
        try
        {
            var handler = new HttpClientHandler();
            if (profile is not null && !string.IsNullOrWhiteSpace(profile.ProxyHost) && !string.IsNullOrWhiteSpace(profile.ProxyPort) &&
                profile.ProxyType is "HTTP" or "HTTPS")
            {
                var proxy = new WebProxy($"http://{profile.ProxyHost}:{profile.ProxyPort}");
                if (!string.IsNullOrWhiteSpace(profile.ProxyUser))
                    proxy.Credentials = new NetworkCredential(profile.ProxyUser, profile.ProxyPass);
                handler.Proxy = proxy;
                handler.UseProxy = true;
            }

            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(6) };
            var json = await client.GetStringAsync("http://ip-api.com/json/?fields=status,query,country,city,timezone");
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            string tz = root.TryGetProperty("timezone", out var tzEl) ? (tzEl.GetString() ?? "") : "";
            string ip = root.TryGetProperty("query", out var ipEl) ? (ipEl.GetString() ?? "") : "";
            string city = root.TryGetProperty("city", out var cEl) ? (cEl.GetString() ?? "") : "";
            string country = root.TryGetProperty("country", out var coEl) ? (coEl.GetString() ?? "") : "";
            string loc = string.IsNullOrEmpty(city) ? country : $"{city}, {country}";
            if (!string.IsNullOrEmpty(tz)) return (true, ip, loc, tz);
        }
        catch { }
        return (false, "", "", "");
    }
}

public static class VpnController
{
    private static string ExeDir => AppDomain.CurrentDomain.BaseDirectory;
    private static string VpnWorkDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHVirtualCam", "vpn");

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
                Arguments = $"--windows-driver wintun --config \"{dst}\"",
                WorkingDirectory = Path.GetDirectoryName(exe) ?? ExeDir,
                UseShellExecute = true,
                Verb = "runas"
            });
            return (true, $"OpenVPN connecting: {Path.GetFileName(ovpnFile)}");
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
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
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
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            });
            return (true, $"WireGuard tunnel activated: {Path.GetFileName(confFile)}");
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
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            });
            return (true, "WireGuard tunnel disconnected.");
        }
        catch (Exception ex) { return (false, ex.Message); }
    }
}
