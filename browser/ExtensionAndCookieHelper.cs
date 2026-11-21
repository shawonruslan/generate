using Microsoft.Web.WebView2.Core;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace MHBrowser;

public sealed class SavedProxy : INotifyPropertyChanged
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..10];
    public string Type { get; set; } = "SOCKS5"; // HTTP, HTTPS, SOCKS5
    public string Host { get; set; } = "";
    public string Port { get; set; } = "";
    public string User { get; set; } = "";
    public string Pass { get; set; } = "";
    public string Country { get; set; } = "-";
    public string ExitIp { get; set; } = "-";
    public string Timezone { get; set; } = "-";
    public string Status { get; set; } = "UNCHECKED"; // UNCHECKED, CHECKING, LIVE, DEAD
    public string Latency { get; set; } = "-";

    public string DisplayLabel => $"{Type}://{Host}:{Port}" + (string.IsNullOrEmpty(Country) || Country == "-" ? "" : $" ({Country})");

    public event PropertyChangedEventHandler? PropertyChanged;
    public void NotifyAll()
    {
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(Country));
        OnPropertyChanged(nameof(ExitIp));
        OnPropertyChanged(nameof(Timezone));
        OnPropertyChanged(nameof(Latency));
        OnPropertyChanged(nameof(DisplayLabel));
    }
    private void OnPropertyChanged([CallerMemberName] string? n = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
}

public static class ProxyStore
{
    private static readonly string StorePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHAdvancedTool", "proxies.json");

    public static List<SavedProxy> Load()
    {
        try
        {
            if (File.Exists(StorePath))
                return JsonSerializer.Deserialize<List<SavedProxy>>(File.ReadAllText(StorePath)) ?? new();
        }
        catch { }
        return new();
    }

    public static void Save(IEnumerable<SavedProxy> proxies)
    {
        try
        {
            var dir = Path.GetDirectoryName(StorePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(StorePath, JsonSerializer.Serialize(proxies.ToList(), new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    /// <summary>
    /// Parses bulk lines in formats:
    ///   socks5://user:pass@host:port
    ///   http://host:port
    ///   host:port:user:pass
    ///   host:port
    /// </summary>
    public static List<SavedProxy> ParseBulk(string rawText, string defaultType = "SOCKS5")
    {
        var list = new List<SavedProxy>();
        foreach (var rawLine in rawText.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            string line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith("#")) continue;

            string type = defaultType;
            string host = "", port = "", user = "", pass = "";

            if (line.Contains("://"))
            {
                if (Uri.TryCreate(line, UriKind.Absolute, out var uri))
                {
                    type = uri.Scheme.ToUpperInvariant() switch
                    {
                        "HTTPS" => "HTTPS",
                        "HTTP" => "HTTP",
                        _ => "SOCKS5"
                    };
                    host = uri.Host;
                    port = uri.Port.ToString();
                    if (!string.IsNullOrEmpty(uri.UserInfo))
                    {
                        var ui = uri.UserInfo.Split(':', 2);
                        user = Uri.UnescapeDataString(ui[0]);
                        if (ui.Length > 1) pass = Uri.UnescapeDataString(ui[1]);
                    }
                }
            }
            else
            {
                var parts = line.Split(':');
                if (parts.Length >= 2)
                {
                    host = parts[0].Trim();
                    port = parts[1].Trim();
                    if (parts.Length >= 4)
                    {
                        user = parts[2].Trim();
                        pass = string.Join(":", parts.Skip(3)).Trim();
                    }
                }
            }

            if (!string.IsNullOrWhiteSpace(host) && int.TryParse(port, out int p) && p > 0)
            {
                list.Add(new SavedProxy { Type = type, Host = host, Port = port, User = user, Pass = pass });
            }
        }
        return list;
    }

    public static async Task CheckAsync(SavedProxy proxy)
    {
        proxy.Status = "CHECKING";
        proxy.NotifyAll();
        var sw = Stopwatch.StartNew();
        var tempProfile = new BrowserProfile
        {
            ProxyType = proxy.Type,
            ProxyHost = proxy.Host,
            ProxyPort = proxy.Port,
            ProxyUser = proxy.User,
            ProxyPass = proxy.Pass
        };
        var (ok, ip, loc, tz, _, _) = await IpTimezoneDetector.DetectAsync(tempProfile);
        sw.Stop();
        if (ok)
        {
            proxy.Status = "LIVE";
            proxy.ExitIp = ip;
            proxy.Country = loc;
            proxy.Timezone = tz;
            proxy.Latency = $"{sw.ElapsedMilliseconds} ms";
        }
        else
        {
            proxy.Status = "DEAD";
            proxy.ExitIp = "-";
            proxy.Country = "-";
            proxy.Timezone = "-";
            proxy.Latency = "-";
        }
        proxy.NotifyAll();
    }
}

public static class ExtensionHelper
{
    public static string ExtensionsRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHAdvancedTool", "Extensions");

    /// <summary>
    /// Installs a Chrome extension from a .zip archive, .crx file, or unpacked folder.
    /// Returns (Ok, UnpackedManifestFolder, ExtensionNameOrError).
    /// </summary>
    public static (bool Ok, string FolderPath, string Message) InstallExtension(string sourcePath)
    {
        try
        {
            Directory.CreateDirectory(ExtensionsRoot);
            if (Directory.Exists(sourcePath))
            {
                var manifestDir = FindManifestDirectory(sourcePath);
                if (manifestDir is null)
                    return (false, "", "manifest.json was not found inside the selected folder.");
                return (true, manifestDir, ReadExtensionName(manifestDir));
            }

            if (!File.Exists(sourcePath))
                return (false, "", "Selected extension file does not exist.");

            string ext = Path.GetExtension(sourcePath).ToLowerInvariant();
            string baseName = Path.GetFileNameWithoutExtension(sourcePath);
            string destDir = Path.Combine(ExtensionsRoot, $"{Sanitize(baseName)}_{Guid.NewGuid().ToString("N")[..6]}");
            Directory.CreateDirectory(destDir);

            if (ext == ".zip")
            {
                ZipFile.ExtractToDirectory(sourcePath, destDir, overwriteFiles: true);
            }
            else if (ext == ".crx")
            {
                byte[] bytes = File.ReadAllBytes(sourcePath);
                int zipOffset = GetCrxZipOffset(bytes);
                if (zipOffset < 0 || zipOffset >= bytes.Length)
                    return (false, "", "Invalid .crx file (embedded ZIP payload not found).");
                using var ms = new MemoryStream(bytes, zipOffset, bytes.Length - zipOffset);
                using var archive = new ZipArchive(ms, ZipArchiveMode.Read);
                archive.ExtractToDirectory(destDir, overwriteFiles: true);
            }
            else
            {
                return (false, "", "Unsupported format. Select a .zip, .crx, or unpacked extension folder.");
            }

            var found = FindManifestDirectory(destDir);
            if (found is null)
                return (false, "", "manifest.json was not found inside the uploaded archive.");

            // Strip _metadata folder from CRX/Web Store extracts so Chromium accepts it as an unpacked extension
            try
            {
                string metaDir = Path.Combine(found, "_metadata");
                if (Directory.Exists(metaDir)) Directory.Delete(metaDir, recursive: true);
            }
            catch { }

            return (true, found, ReadExtensionName(found));
        }
        catch (Exception ex)
        {
            return (false, "", $"Extension install failed: {ex.Message}");
        }
    }

    public static string ReadExtensionName(string folder)
    {
        try
        {
            var mf = Path.Combine(folder, "manifest.json");
            if (File.Exists(mf))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(mf));
                if (doc.RootElement.TryGetProperty("name", out var nEl))
                {
                    var name = nEl.GetString();
                    if (!string.IsNullOrWhiteSpace(name) && !name.StartsWith("__MSG_"))
                        return name;
                }
            }
        }
        catch { }
        return Path.GetFileName(folder);
    }

    private static string? FindManifestDirectory(string dir)
    {
        if (File.Exists(Path.Combine(dir, "manifest.json"))) return dir;
        foreach (var sub in Directory.GetDirectories(dir, "*", SearchOption.AllDirectories))
        {
            if (File.Exists(Path.Combine(sub, "manifest.json"))) return sub;
        }
        return null;
    }

    public static string? GetPopupOrOptionsPage(string folder)
    {
        try
        {
            var mf = Path.Combine(folder, "manifest.json");
            if (!File.Exists(mf)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(mf));
            var root = doc.RootElement;
            foreach (var key in new[] { "action", "browser_action", "page_action" })
            {
                if (root.TryGetProperty(key, out var act) && act.TryGetProperty("default_popup", out var pop))
                {
                    var p = pop.GetString();
                    if (!string.IsNullOrWhiteSpace(p)) return p.TrimStart('/');
                }
            }
            if (root.TryGetProperty("side_panel", out var sp) && sp.TryGetProperty("default_path", out var spPath))
            {
                var p = spPath.GetString();
                if (!string.IsNullOrWhiteSpace(p)) return p.TrimStart('/');
            }
            if (root.TryGetProperty("options_ui", out var optUi) && optUi.TryGetProperty("page", out var optPage))
            {
                var p = optPage.GetString();
                if (!string.IsNullOrWhiteSpace(p)) return p.TrimStart('/');
            }
            if (root.TryGetProperty("options_page", out var optDirect))
            {
                var p = optDirect.GetString();
                if (!string.IsNullOrWhiteSpace(p)) return p.TrimStart('/');
            }
        }
        catch { }
        return null;
    }

    private static int GetCrxZipOffset(byte[] data)
    {
        // Proper CRX2 / CRX3 header parsing ("Cr24")
        if (data.Length >= 16 && data[0] == 'C' && data[1] == 'r' && data[2] == '2' && data[3] == '4')
        {
            uint ver = BitConverter.ToUInt32(data, 4);
            if (ver == 3)
            {
                uint hdrLen = BitConverter.ToUInt32(data, 8);
                int off = 12 + (int)hdrLen;
                if (off > 0 && off < data.Length - 4 && data[off] == 0x50 && data[off + 1] == 0x4B)
                    return off;
            }
            else if (ver == 2)
            {
                uint pubLen = BitConverter.ToUInt32(data, 8);
                uint sigLen = BitConverter.ToUInt32(data, 12);
                int off = 16 + (int)pubLen + (int)sigLen;
                if (off > 0 && off < data.Length - 4 && data[off] == 0x50 && data[off + 1] == 0x4B)
                    return off;
            }
        }
        return FindPkSignature(data);
    }

    private static int FindPkSignature(byte[] data)
    {
        for (int i = 0; i < data.Length - 4; i++)
        {
            if (data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 0x03 && data[i + 3] == 0x04)
                return i;
        }
        return -1;
    }

    private static string Sanitize(string s)
    {
        var sb = new StringBuilder();
        foreach (char c in s) sb.Append(char.IsLetterOrDigit(c) ? c : '_');
        return sb.Length == 0 ? "ext" : sb.ToString();
    }
}

public static class CookieHelper
{
    public sealed class CookieDto
    {
        public string name { get; set; } = "";
        public string value { get; set; } = "";
        public string domain { get; set; } = "";
        public string path { get; set; } = "/";
        public double? expirationDate { get; set; }
        public bool secure { get; set; }
        public bool httpOnly { get; set; }
    }

    public static async Task<int> ExportCookiesAsync(CoreWebView2CookieManager mgr, string filePath)
    {
        var cookies = await mgr.GetCookiesAsync("");
        if (filePath.EndsWith(".txt", StringComparison.OrdinalIgnoreCase))
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Netscape HTTP Cookie File - Exported by MH Advanced Tool");
            foreach (var c in cookies)
            {
                string includeSub = c.Domain.StartsWith(".") ? "TRUE" : "FALSE";
                string secure = c.IsSecure ? "TRUE" : "FALSE";
                long exp = c.IsSession ? 0 : new DateTimeOffset(c.Expires).ToUnixTimeSeconds();
                sb.AppendLine($"{c.Domain}\t{includeSub}\t{c.Path}\t{secure}\t{exp}\t{c.Name}\t{c.Value}");
            }
            File.WriteAllText(filePath, sb.ToString());
        }
        else
        {
            var list = cookies.Select(c => new CookieDto
            {
                name = c.Name,
                value = c.Value,
                domain = c.Domain,
                path = c.Path,
                expirationDate = c.IsSession ? null : new DateTimeOffset(c.Expires).ToUnixTimeSeconds(),
                secure = c.IsSecure,
                httpOnly = c.IsHttpOnly
            }).ToList();
            File.WriteAllText(filePath, JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true }));
        }
        return cookies.Count;
    }

    public static int ImportCookies(CoreWebView2CookieManager mgr, string filePath)
    {
        string raw = File.ReadAllText(filePath).Trim();
        int count = 0;
        if (raw.StartsWith("["))
        {
            var list = JsonSerializer.Deserialize<List<CookieDto>>(raw, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
            foreach (var dto in list)
            {
                if (string.IsNullOrWhiteSpace(dto.name) || string.IsNullOrWhiteSpace(dto.domain)) continue;
                var cookie = mgr.CreateCookie(dto.name, dto.value ?? "", dto.domain, string.IsNullOrWhiteSpace(dto.path) ? "/" : dto.path);
                cookie.IsSecure = dto.secure;
                cookie.IsHttpOnly = dto.httpOnly;
                if (dto.expirationDate is > 0)
                    cookie.Expires = DateTimeOffset.FromUnixTimeSeconds((long)dto.expirationDate.Value).UtcDateTime;
                mgr.AddOrUpdateCookie(cookie);
                count++;
            }
        }
        else
        {
            // Netscape cookies.txt format
            foreach (var line in raw.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.StartsWith("#")) continue;
                var parts = line.Split('\t');
                if (parts.Length < 7) continue;
                var cookie = mgr.CreateCookie(parts[5], parts[6], parts[0], parts[2]);
                cookie.IsSecure = parts[3].Equals("TRUE", StringComparison.OrdinalIgnoreCase);
                if (long.TryParse(parts[4], out long exp) && exp > 0)
                    cookie.Expires = DateTimeOffset.FromUnixTimeSeconds(exp).UtcDateTime;
                mgr.AddOrUpdateCookie(cookie);
                count++;
            }
        }
        return count;
    }
}
