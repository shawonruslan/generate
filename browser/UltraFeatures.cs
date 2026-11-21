using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;

namespace MHBrowser;

public static class CdpPortAllocator
{
    public static int AllocateFreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }
}

public static class VirtualCamBridge
{
    private static readonly string CmdPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "MHVirtualCam", "remote_cmd.txt");

    public static bool SendCommand(string cmd)
    {
        try
        {
            var dir = Path.GetDirectoryName(CmdPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(CmdPath, cmd);
            return true;
        }
        catch { return false; }
    }
}

public static class CookieRobotDefaults
{
    public static readonly string[] TrustedSites =
    {
        "https://www.wikipedia.org/",
        "https://www.bbc.com/",
        "https://www.theguardian.com/",
        "https://www.imdb.com/",
        "https://www.amazon.com/",
        "https://www.reddit.com/",
        "https://github.com/",
        "https://weather.com/"
    };
}

/// <summary>
/// Multi-Window Synchronizer (Master -> Slave) + 1-Click Auto-Tile Grid.
/// </summary>
public static class WindowSyncManager
{
    private static readonly List<BrowserWindow> Windows = new();
    public static bool IsSyncEnabled { get; set; }
    public static BrowserWindow? MasterWindow { get; set; }

    public static void Register(BrowserWindow w)
    {
        if (!Windows.Contains(w)) Windows.Add(w);
        MasterWindow ??= w;
    }

    public static void Unregister(BrowserWindow w)
    {
        Windows.Remove(w);
        if (ReferenceEquals(MasterWindow, w))
            MasterWindow = Windows.FirstOrDefault();
    }

    public static int OpenCount => Windows.Count;

    public static void TileWindowsGrid()
    {
        var list = Windows.Where(w => w.IsLoaded).ToList();
        if (list.Count == 0) return;

        var area = SystemParameters.WorkArea;
        int cols = (int)Math.Ceiling(Math.Sqrt(list.Count));
        int rows = (int)Math.Ceiling((double)list.Count / cols);
        double w = area.Width / cols;
        double h = area.Height / rows;

        for (int i = 0; i < list.Count; i++)
        {
            int r = i / cols;
            int c = i % cols;
            var win = list[i];
            win.WindowState = WindowState.Normal;
            win.Left = area.Left + c * w;
            win.Top = area.Top + r * h;
            win.Width = w;
            win.Height = h;
            win.Activate();
        }
    }

    public static void BroadcastNavigate(BrowserWindow source, string url)
    {
        if (!IsSyncEnabled || !ReferenceEquals(MasterWindow, source)) return;
        foreach (var w in Windows.ToList())
        {
            if (ReferenceEquals(w, source) || !w.IsLoaded) continue;
            _ = Task.Run(async () =>
            {
                await Task.Delay(Random.Shared.Next(35, 110));
                _ = w.Dispatcher.BeginInvoke(() => w.SyncNavigateFromMaster(url));
            });
        }
    }

    public static void BroadcastAction(BrowserWindow source, string actionType, double x, double y, string text = "")
    {
        if (!IsSyncEnabled || !ReferenceEquals(MasterWindow, source)) return;
        foreach (var w in Windows.ToList())
        {
            if (ReferenceEquals(w, source) || !w.IsLoaded) continue;
            _ = Task.Run(async () =>
            {
                await Task.Delay(Random.Shared.Next(30, 105));
                _ = w.Dispatcher.BeginInvoke(() => w.SyncActionFromMaster(actionType, x, y, text));
            });
        }
    }
}

/// <summary>
/// AES-256-CBC + PBKDF2-SHA256 encrypted .mhprofile Backup / Export & Import.
/// </summary>
public static class ProfileBackupHelper
{
    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("MHPROF01");

    public static void ExportEncrypted(BrowserProfile profile, string outFile, string password)
    {
        string tmpZip = Path.Combine(Path.GetTempPath(), $"mhprof_{Guid.NewGuid():N}.zip");
        try
        {
            using (var zf = ZipFile.Open(tmpZip, ZipArchiveMode.Create))
            {
                var metaEntry = zf.CreateEntry("profile.json");
                using (var sw = new StreamWriter(metaEntry.Open(), Encoding.UTF8))
                    sw.Write(JsonSerializer.Serialize(profile, new JsonSerializerOptions { WriteIndented = true }));

                if (Directory.Exists(profile.UserDataDir))
                {
                    foreach (var file in Directory.EnumerateFiles(profile.UserDataDir, "*", SearchOption.AllDirectories))
                    {
                        try
                        {
                            string rel = Path.GetRelativePath(profile.UserDataDir, file);
                            // Skip locked Chromium cache / GPU shader temp files
                            if (rel.Contains("Cache", StringComparison.OrdinalIgnoreCase) ||
                                rel.EndsWith(".lock", StringComparison.OrdinalIgnoreCase) ||
                                rel.EndsWith("LOCK", StringComparison.OrdinalIgnoreCase))
                                continue;
                            zf.CreateEntryFromFile(file, "userdata/" + rel.Replace('\\', '/'), CompressionLevel.Fastest);
                        }
                        catch { }
                    }
                }
            }

            byte[] plain = File.ReadAllBytes(tmpZip);
            byte[] salt = RandomNumberGenerator.GetBytes(16);
            byte[] iv = RandomNumberGenerator.GetBytes(16);
            byte[] key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);

            using var aes = Aes.Create();
            aes.Key = key;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;

            using var fs = File.Create(outFile);
            fs.Write(Magic);
            fs.Write(salt);
            fs.Write(iv);
            using var cs = new CryptoStream(fs, aes.CreateEncryptor(), CryptoStreamMode.Write);
            cs.Write(plain);
            cs.FlushFinalBlock();
        }
        finally
        {
            try { if (File.Exists(tmpZip)) File.Delete(tmpZip); } catch { }
        }
    }

    public static BrowserProfile ImportEncrypted(string inFile, string password)
    {
        byte[] all = File.ReadAllBytes(inFile);
        if (all.Length < Magic.Length + 32 || !all.AsSpan(0, Magic.Length).SequenceEqual(Magic))
            throw new InvalidDataException("Invalid .mhprofile file.");

        byte[] salt = all.AsSpan(Magic.Length, 16).ToArray();
        byte[] iv = all.AsSpan(Magic.Length + 16, 16).ToArray();
        byte[] cipher = all.AsSpan(Magic.Length + 32).ToArray();
        byte[] key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);

        string tmpZip = Path.Combine(Path.GetTempPath(), $"mhprof_in_{Guid.NewGuid():N}.zip");
        try
        {
            using (var aes = Aes.Create())
            {
                aes.Key = key;
                aes.IV = iv;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                using var ms = new MemoryStream(cipher);
                using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
                using var outFs = File.Create(tmpZip);
                cs.CopyTo(outFs);
            }

            using var zf = ZipFile.OpenRead(tmpZip);
            var metaEntry = zf.GetEntry("profile.json") ?? throw new InvalidDataException("Missing profile.json inside archive.");
            BrowserProfile profile;
            using (var sr = new StreamReader(metaEntry.Open(), Encoding.UTF8))
                profile = JsonSerializer.Deserialize<BrowserProfile>(sr.ReadToEnd()) ?? new BrowserProfile();

            profile.Id = Guid.NewGuid().ToString("N")[..12];
            profile.Name += " (Imported)";
            Directory.CreateDirectory(profile.UserDataDir);

            foreach (var entry in zf.Entries)
            {
                if (!entry.FullName.StartsWith("userdata/", StringComparison.OrdinalIgnoreCase) || string.IsNullOrEmpty(entry.Name))
                    continue;
                string rel = entry.FullName["userdata/".Length..];
                string dest = Path.Combine(profile.UserDataDir, rel.Replace('/', Path.DirectorySeparatorChar));
                var d = Path.GetDirectoryName(dest);
                if (!string.IsNullOrEmpty(d)) Directory.CreateDirectory(d);
                entry.ExtractToFile(dest, overwrite: true);
            }
            return profile;
        }
        finally
        {
            try { if (File.Exists(tmpZip)) File.Delete(tmpZip); } catch { }
        }
    }
}
