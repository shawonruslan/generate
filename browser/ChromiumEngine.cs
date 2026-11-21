using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows;

namespace MHBrowser;

/// <summary>
/// Manages the bundled Real Chromium engine (Google Chrome for Testing Stable win64),
/// automatic background updates, and custom MH Browser icon stamping.
/// </summary>
public static class ChromiumManager
{
    private const string CftApiUrl = "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json";

    public static string BundledChromiumDir => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "chromium"));
    public static string LocalChromiumDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHAdvancedTool", "chromium");
    public static string PendingChromiumDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHAdvancedTool", "chromium_pending");

    public static string BrowserIconPath
    {
        get
        {
            string p1 = Path.Combine(AppContext.BaseDirectory, "browser.ico");
            if (File.Exists(p1)) return p1;
            string p2 = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "browser", "browser.ico"));
            return File.Exists(p2) ? p2 : "";
        }
    }

    public static void ApplyPendingUpdateIfSafe(bool anyProfileRunning)
    {
        if (anyProfileRunning || !Directory.Exists(PendingChromiumDir)) return;
        try
        {
            string pendingExe = FindExeInDir(PendingChromiumDir);
            if (string.IsNullOrEmpty(pendingExe)) return;
            if (Directory.Exists(LocalChromiumDir))
                Directory.Delete(LocalChromiumDir, recursive: true);
            Directory.Move(PendingChromiumDir, LocalChromiumDir);
        }
        catch { }
    }

    public static string? FindChromiumExe()
    {
        string local = FindExeInDir(LocalChromiumDir);
        if (!string.IsNullOrEmpty(local)) return local;
        string bundled = FindExeInDir(BundledChromiumDir);
        if (!string.IsNullOrEmpty(bundled)) return bundled;
        return null;
    }

    public static string GetInstalledVersion()
    {
        foreach (var dir in new[] { LocalChromiumDir, BundledChromiumDir })
        {
            string vf = Path.Combine(dir, "version.txt");
            if (File.Exists(vf))
            {
                string v = File.ReadAllText(vf).Trim();
                if (!string.IsNullOrWhiteSpace(v)) return v;
            }
        }
        var exe = FindChromiumExe();
        if (!string.IsNullOrEmpty(exe))
        {
            try { return FileVersionInfo.GetVersionInfo(exe).ProductVersion ?? "Installed"; }
            catch { }
        }
        return "Not installed";
    }

    private static string FindExeInDir(string dir)
    {
        if (!Directory.Exists(dir)) return "";
        string direct = Path.Combine(dir, "chrome.exe");
        if (File.Exists(direct)) return direct;
        string sub = Path.Combine(dir, "chrome-win64", "chrome.exe");
        if (File.Exists(sub)) return sub;
        return "";
    }

    /// <summary>
    /// Checks Google's Chrome for Testing Stable channel and automatically downloads/installs newer Chromium builds.
    /// </summary>
    public static async Task<(bool Updated, string Version, string Message)> CheckAndAutoUpdateAsync(
        Func<bool> isAnyProfileRunning,
        Action<string>? onStatus = null,
        CancellationToken ct = default)
    {
        try
        {
            ApplyPendingUpdateIfSafe(isAnyProfileRunning());
            string currentVer = GetInstalledVersion();
            onStatus?.Invoke("Checking for Chromium engine updates...");

            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("MHAdvancedTool/5.0");
            string json = await http.GetStringAsync(CftApiUrl, ct);
            using var doc = JsonDocument.Parse(json);

            var stable = doc.RootElement.GetProperty("channels").GetProperty("Stable");
            string latestVer = stable.GetProperty("version").GetString() ?? "";
            if (string.IsNullOrWhiteSpace(latestVer))
                return (false, currentVer, "Could not read latest Chromium version.");

            bool hasExe = !string.IsNullOrEmpty(FindChromiumExe());
            if (hasExe && currentVer.Equals(latestVer, StringComparison.OrdinalIgnoreCase))
                return (false, currentVer, $"Chromium v{currentVer} is up to date.");

            string? dlUrl = null;
            foreach (var item in stable.GetProperty("downloads").GetProperty("chrome").EnumerateArray())
            {
                if (item.TryGetProperty("platform", out var pf) && pf.GetString() == "win64")
                {
                    dlUrl = item.GetProperty("url").GetString();
                    break;
                }
            }
            if (string.IsNullOrWhiteSpace(dlUrl))
                return (false, currentVer, "win64 Chromium download URL not found.");

            string stageRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHAdvancedTool", "chromium_staging");
            if (Directory.Exists(stageRoot)) Directory.Delete(stageRoot, recursive: true);
            Directory.CreateDirectory(stageRoot);

            string zipPath = Path.Combine(stageRoot, "chrome-win64.zip");
            onStatus?.Invoke($"Downloading Real Chromium v{latestVer}...");

            using (var resp = await http.GetAsync(dlUrl, HttpCompletionOption.ResponseHeadersRead, ct))
            {
                resp.EnsureSuccessStatusCode();
                long total = resp.Content.Headers.ContentLength ?? -1;
                await using var netStream = await resp.Content.ReadAsStreamAsync(ct);
                await using var fs = File.Create(zipPath);
                byte[] buf = new byte[81920];
                long read = 0;
                int n;
                int lastPct = -1;
                while ((n = await netStream.ReadAsync(buf, ct)) > 0)
                {
                    await fs.WriteAsync(buf.AsMemory(0, n), ct);
                    read += n;
                    if (total > 0)
                    {
                        int pct = (int)(read * 100 / total);
                        if (pct != lastPct && pct % 5 == 0)
                        {
                            lastPct = pct;
                            onStatus?.Invoke($"Updating Chromium v{latestVer}... {pct}%");
                        }
                    }
                }
            }

            onStatus?.Invoke($"Extracting Chromium v{latestVer}...");
            string extDir = Path.Combine(stageRoot, "ext");
            ZipFile.ExtractToDirectory(zipPath, extDir, overwriteFiles: true);
            string extractedRoot = Directory.Exists(Path.Combine(extDir, "chrome-win64"))
                ? Path.Combine(extDir, "chrome-win64")
                : extDir;
            File.WriteAllText(Path.Combine(extractedRoot, "version.txt"), latestVer);

            if (isAnyProfileRunning())
            {
                if (Directory.Exists(PendingChromiumDir)) Directory.Delete(PendingChromiumDir, recursive: true);
                Directory.Move(extractedRoot, PendingChromiumDir);
                try { Directory.Delete(stageRoot, true); } catch { }
                return (true, latestVer, $"Chromium v{latestVer} downloaded — will activate on next browser launch.");
            }
            else
            {
                if (Directory.Exists(LocalChromiumDir)) Directory.Delete(LocalChromiumDir, recursive: true);
                Directory.Move(extractedRoot, LocalChromiumDir);
                try { Directory.Delete(stageRoot, true); } catch { }
                return (true, latestVer, $"Updated to Real Chromium v{latestVer}!");
            }
        }
        catch (Exception ex)
        {
            return (false, GetInstalledVersion(), $"Chromium update check skipped: {ex.Message}");
        }
    }
}

/// <summary>
/// Manages a single running Real Chromium browser process for a profile:
/// isolated user-data-dir, Zero-Leak proxy/VPN flags, MV3 companion stealth/GPS extension,
/// custom MH Browser taskbar/window icon stamping, auto-healing VPN watchdog, and on-demand CDP Inspector.
/// </summary>
public sealed class RealChromiumSession : IDisposable
{
    private const uint WM_SETICON = 0x0080;
    private const int ICON_SMALL = 0;
    private const int ICON_BIG = 1;
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x00000010;
    private const int SW_RESTORE = 9;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(IntPtr hInst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);
    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    public BrowserProfile Profile { get; }
    public VerifiedConnection Connection { get; }
    public int CdpPort { get; }
    public IntPtr MainHwnd { get; private set; }
    public bool IsRunning => _proc is not null && !_proc.HasExited;

    private Process? _proc;
    private readonly CancellationTokenSource _cts = new();
    private InspectorWindow? _inspectorWindow;
    private CdpInspectorBridge? _inspectorBridge;
    private readonly ObservableCollection<CapturedNetRequest> _capturedNet = new();
    private readonly ObservableCollection<RecordedUiAction> _recordedUi = new();
    private readonly ObservableCollection<InternalSecurityEvent> _internalEvents = new();
    private IntPtr _hIconBig;
    private IntPtr _hIconSmall;

    public event Action? Exited;

    public RealChromiumSession(BrowserProfile profile, VerifiedConnection conn)
    {
        Profile = profile;
        Connection = conn;
        CdpPort = CdpPortAllocator.AllocateFreePort();
    }

    public bool Launch(string chromiumExe, out string error)
    {
        error = "";
        try
        {
            Directory.CreateDirectory(Profile.UserDataDir);

            // 1) Generate per-profile MV3 companion stealth & GPS extension (runs at document_start in MAIN world)
            string envExtDir = BuildCompanionExtension();

            // 2) Collect all extensions to load (companion + user's Profile Editor extensions)
            var extDirs = new List<string> { envExtDir };
            if (Profile.ExtensionPaths is { Count: > 0 })
            {
                foreach (var ep in Profile.ExtensionPaths)
                {
                    if (Directory.Exists(ep))
                    {
                        string meta = Path.Combine(ep, "_metadata");
                        if (Directory.Exists(meta)) try { Directory.Delete(meta, true); } catch { }
                        extDirs.Add(ep);
                    }
                }
            }

            // 3) Build Real Chromium command-line arguments
            var args = new List<string>
            {
                $"--user-data-dir=\"{Profile.UserDataDir}\"",
                "--start-maximized",
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-default-apps",
                "--disable-blink-features=AutomationControlled",
                "--disable-quic",
                $"--lang={Profile.Language}",
                $"--remote-debugging-port={CdpPort}",
                $"--load-extension=\"{string.Join(",", extDirs)}\""
            };

            if (!string.IsNullOrWhiteSpace(Profile.UserAgent))
                args.Add($"--user-agent=\"{Profile.UserAgent}\"");

            // Hard Zero-Leak Network Shield
            if (Connection.LocalSocksPort > 0)
            {
                args.Add($"--proxy-server=\"socks5://127.0.0.1:{Connection.LocalSocksPort}\"");
                args.Add("--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE 127.0.0.1\"");
            }
            else if (Profile.ProxyType is "HTTP" or "HTTPS" &&
                     !string.IsNullOrWhiteSpace(Profile.ProxyHost) && !string.IsNullOrWhiteSpace(Profile.ProxyPort))
            {
                string scheme = Profile.ProxyType == "HTTPS" ? "https" : "http";
                args.Add($"--proxy-server=\"{scheme}://{Profile.ProxyHost}:{Profile.ProxyPort}\"");
                args.Add($"--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE {Profile.ProxyHost.Trim()}\"");
            }

            if (Profile.WebRtcProtect || Profile.ProxyType != "Direct")
                args.Add("--force-webrtc-ip-handling-policy=disable_non_proxied_udp");

            string startUrl = string.IsNullOrWhiteSpace(Profile.StartUrl) ? "https://whoer.net" : Profile.StartUrl.Trim();
            if (!startUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                !startUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                startUrl = "https://" + startUrl;
            args.Add($"\"{startUrl}\"");

            _proc = new Process
            {
                EnableRaisingEvents = true,
                StartInfo = new ProcessStartInfo
                {
                    FileName = chromiumExe,
                    Arguments = string.Join(" ", args),
                    WorkingDirectory = Path.GetDirectoryName(chromiumExe) ?? Environment.CurrentDirectory,
                    UseShellExecute = false
                }
            };
            _proc.Exited += (_, _) =>
            {
                Dispose();
                Exited?.Invoke();
            };
            _proc.Start();
            Profile.IsRunning = true;

            // 4) Stamp custom MH Browser Globe Icon + independent Taskbar AppUserModelID onto Chromium window
            _ = Task.Run(() => StampCustomBrowserIconLoopAsync(_cts.Token));

            // 5) One-shot CDP Timezone & Geolocation setup (disconnects immediately after applying)
            _ = Task.Run(() => ApplyInitialCdpEmulationAsync(_cts.Token));

            // 6) Auto-healing VPN tunnel monitor (reconnects OpenVPN/WireGuard on same LocalSocksPort if it drops)
            if (Connection.VpnSession is not null)
                _ = Task.Run(() => MonitorVpnAutoHealLoopAsync(_cts.Token));

            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    public void Activate()
    {
        if (MainHwnd != IntPtr.Zero)
        {
            ShowWindow(MainHwnd, SW_RESTORE);
            SetForegroundWindow(MainHwnd);
        }
    }

    public void MoveToBounds(int x, int y, int w, int h)
    {
        if (MainHwnd != IntPtr.Zero)
        {
            ShowWindow(MainHwnd, SW_RESTORE);
            MoveWindow(MainHwnd, x, y, w, h, true);
        }
    }

    public void OpenInspector()
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (_inspectorWindow is not null && _inspectorWindow.IsLoaded)
            {
                _inspectorWindow.Activate();
                return;
            }
            _inspectorBridge?.Dispose();
            _inspectorBridge = new CdpInspectorBridge(CdpPort, _capturedNet, _internalEvents);
            _inspectorWindow = new InspectorWindow(
                Profile.Name, _capturedNet, _recordedUi, _internalEvents,
                reqId => _inspectorBridge.FetchResponseBodyAsync(reqId));
            _inspectorWindow.Closed += (_, _) =>
            {
                _inspectorBridge?.Dispose();
                _inspectorBridge = null;
                _inspectorWindow = null;
            };
            _inspectorWindow.Show();
            _ = _inspectorBridge.StartAsync();
        });
    }

    public void CloseBrowser()
    {
        try
        {
            if (_proc is not null && !_proc.HasExited)
            {
                _proc.CloseMainWindow();
                if (!_proc.WaitForExit(2000))
                    _proc.Kill(entireProcessTree: true);
            }
        }
        catch { }
    }

    private async Task StampCustomBrowserIconLoopAsync(CancellationToken ct)
    {
        string icoPath = ChromiumManager.BrowserIconPath;
        if (!string.IsNullOrEmpty(icoPath) && File.Exists(icoPath))
        {
            _hIconBig = LoadImage(IntPtr.Zero, icoPath, IMAGE_ICON, 48, 48, LR_LOADFROMFILE);
            _hIconSmall = LoadImage(IntPtr.Zero, icoPath, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
        }

        // Chromium may spawn child processes; match by window title or process tree
        var stamped = new HashSet<IntPtr>();
        for (int attempt = 0; attempt < 30 && !ct.IsCancellationRequested && IsRunning; attempt++)
        {
            try
            {
                var chromePids = new HashSet<uint>();
                if (_proc is not null) chromePids.Add((uint)_proc.Id);
                foreach (var p in Process.GetProcessesByName("chrome"))
                {
                    try { chromePids.Add((uint)p.Id); } catch { }
                }

                EnumWindows((hwnd, _) =>
                {
                    if (!IsWindowVisible(hwnd)) return true;
                    GetWindowThreadProcessId(hwnd, out uint pid);
                    if (!chromePids.Contains(pid)) return true;
                    if (_proc is not null && pid == (uint)_proc.Id && MainHwnd == IntPtr.Zero)
                        MainHwnd = hwnd;

                    if (stamped.Add(hwnd))
                    {
                        if (MainHwnd == IntPtr.Zero) MainHwnd = hwnd;
                        if (_hIconBig != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)ICON_BIG, _hIconBig);
                        if (_hIconSmall != IntPtr.Zero) SendMessage(hwnd, WM_SETICON, (IntPtr)ICON_SMALL, _hIconSmall);
                        App.SetHwndAppUserModelId(hwnd, "MHAdvancedTool.Browser");
                    }
                    return true;
                }, IntPtr.Zero);

                if (MainHwnd != IntPtr.Zero && attempt >= 4) break;
            }
            catch { }
            await Task.Delay(400, ct);
        }
    }

    private async Task ApplyInitialCdpEmulationAsync(CancellationToken ct)
    {
        bool needTz = !string.IsNullOrWhiteSpace(Connection.Timezone);
        (bool hasGeo, double lat, double lon, double acc) = ResolveGeo();
        if (!needTz && !hasGeo) return;

        await Task.Delay(1800, ct);
        try
        {
            string? wsUrl = await CdpInspectorBridge.GetFirstPageWsUrlAsync(CdpPort, ct);
            if (string.IsNullOrEmpty(wsUrl)) return;

            using var ws = new ClientWebSocket();
            await ws.ConnectAsync(new Uri(wsUrl), ct);
            int id = 1;
            if (needTz)
            {
                string cmd = JsonSerializer.Serialize(new { id = id++, method = "Emulation.setTimezoneOverride", @params = new { timezoneId = Connection.Timezone } });
                await ws.SendAsync(Encoding.UTF8.GetBytes(cmd), WebSocketMessageType.Text, true, ct);
            }
            if (hasGeo)
            {
                string cmd = JsonSerializer.Serialize(new { id = id++, method = "Emulation.setGeolocationOverride", @params = new { latitude = lat, longitude = lon, accuracy = acc } });
                await ws.SendAsync(Encoding.UTF8.GetBytes(cmd), WebSocketMessageType.Text, true, ct);
            }
            await Task.Delay(250, ct);
            await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", ct);
        }
        catch { }
    }

    private async Task MonitorVpnAutoHealLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && IsRunning)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(15), ct);
                if (Connection.VpnSession is not null && !Connection.VpnSession.IsProcessAlive)
                {
                    await Connection.VpnSession.ReconnectInPlaceAsync(null, ct);
                }
            }
            catch { break; }
        }
    }

    private (bool Active, double Lat, double Lon, double Acc) ResolveGeo()
    {
        double acc = Profile.CustomGeoAccuracy > 0 ? Profile.CustomGeoAccuracy : 35;
        if (!Profile.AutoGeolocation && (Math.Abs(Profile.CustomGeoLat) > 0.0001 || Math.Abs(Profile.CustomGeoLon) > 0.0001))
            return (true, Profile.CustomGeoLat, Profile.CustomGeoLon, acc);
        if (Math.Abs(Connection.Lat) > 0.0001 || Math.Abs(Connection.Lon) > 0.0001)
            return (true, Connection.Lat, Connection.Lon, acc);
        if (Math.Abs(Profile.CustomGeoLat) > 0.0001 || Math.Abs(Profile.CustomGeoLon) > 0.0001)
            return (true, Profile.CustomGeoLat, Profile.CustomGeoLon, acc);
        return (false, 0, 0, acc);
    }

    private string BuildCompanionExtension()
    {
        string extDir = Path.Combine(Profile.UserDataDir, "_mh_env_ext");
        Directory.CreateDirectory(extDir);

        string manifest = """
        {
          "manifest_version": 3,
          "name": "MH Profile Environment",
          "version": "5.0.0",
          "description": "Per-profile fingerprint, WebGL, WebRTC, and GPS environment.",
          "content_scripts": [
            {
              "matches": ["<all_urls>"],
              "js": ["env.js"],
              "run_at": "document_start",
              "all_frames": true,
              "world": "MAIN"
            }
          ]
        }
        """;
        File.WriteAllText(Path.Combine(extDir, "manifest.json"), manifest);

        var (hasGeo, lat, lon, acc) = ResolveGeo();
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        uint seed = 2166136261u;
        foreach (char c in Profile.Id ?? "mh") seed = (seed ^ c) * 16777619u;
        int noiseR = (int)(seed % 3) - 1;
        string vendorJson = JsonSerializer.Serialize(Profile.WebGlVendor ?? "Google Inc. (NVIDIA)");
        string rendererJson = JsonSerializer.Serialize(Profile.WebGlRenderer ?? "ANGLE (NVIDIA, NVIDIA GeForce RTX 4060 Direct3D11 vs_5_0 ps_5_0, D3D11)");
        string exitIpJson = JsonSerializer.Serialize(Connection.ExitIp ?? "");
        string platJson = JsonSerializer.Serialize(Profile.Platform ?? "Win32");

        var sb = new StringBuilder();
        sb.AppendLine("(() => { 'use strict';");
        sb.AppendLine($"try {{ Object.defineProperty(navigator, 'webdriver', {{ get: () => undefined }}); }} catch {{}}");
        sb.AppendLine($"try {{ Object.defineProperty(navigator, 'platform', {{ get: () => {platJson} }}); }} catch {{}}");
        sb.AppendLine($"try {{ Object.defineProperty(navigator, 'hardwareConcurrency', {{ get: () => {Math.Max(2, Profile.CpuCores)} }}); }} catch {{}}");
        sb.AppendLine($"try {{ Object.defineProperty(navigator, 'deviceMemory', {{ get: () => {Math.Max(2, Profile.RamGb)} }}); }} catch {{}}");

        if (Profile.WebGlSpoof)
        {
            sb.AppendLine($@"
try {{
  const patchGl = (Ctor) => {{
    if (!Ctor || !Ctor.prototype) return;
    const orig = Ctor.prototype.getParameter;
    Ctor.prototype.getParameter = function(p) {{
      if (p === 37445) return {vendorJson};
      if (p === 37446) return {rendererJson};
      return orig.call(this, p);
    }};
  }};
  patchGl(window.WebGLRenderingContext);
  patchGl(window.WebGL2RenderingContext);
}} catch {{}}");
        }

        if (Profile.FingerprintNoise)
        {
            sb.AppendLine($@"
try {{
  const nr = {noiseR};
  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
  HTMLCanvasElement.prototype.toDataURL = function(...a) {{
    try {{
      const ctx = this.getContext('2d');
      if (ctx && this.width > 0 && this.height > 0 && this.width <= 512) {{
        const img = ctx.getImageData(0, 0, 1, 1);
        img.data[0] = (img.data[0] + nr + 256) % 256;
        ctx.putImageData(img, 0, 0);
      }}
    }} catch {{}}
    return origToDataURL.apply(this, a);
  }};
}} catch {{}}");
        }

        if (Profile.WebRtcSpoofPublicIp && !string.IsNullOrWhiteSpace(Connection.ExitIp))
        {
            sb.AppendLine($@"
try {{
  const spoofIp = {exitIpJson};
  const OrigPC = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (OrigPC && spoofIp) {{
    const rewrite = (s) => s ? s.replace(/(c=IN IP4 )([0-9.]+)/g, '$1' + spoofIp).replace(/(candidate:\S+ \d+ \S+ \d+ )([0-9.]+)/g, '$1' + spoofIp) : s;
    window.RTCPeerConnection = function(cfg, c) {{
      const pc = new OrigPC(cfg, c);
      const origOffer = pc.createOffer.bind(pc);
      pc.createOffer = async (...a) => {{
        const o = await origOffer(...a);
        if (o && o.sdp) o.sdp = rewrite(o.sdp);
        return o;
      }};
      return pc;
    }};
    window.RTCPeerConnection.prototype = OrigPC.prototype;
  }}
}} catch {{}}");
        }

        if (hasGeo)
        {
            sb.AppendLine($@"
try {{
  const gLat = {lat.ToString("F6", inv)}, gLon = {lon.ToString("F6", inv)}, gAcc = {acc.ToString("F1", inv)};
  const makePos = (jitter) => ({{
    coords: {{
      latitude: gLat + (jitter ? (Math.random() - 0.5) * 0.00008 : 0),
      longitude: gLon + (jitter ? (Math.random() - 0.5) * 0.00008 : 0),
      accuracy: gAcc, altitude: null, altitudeAccuracy: null, heading: null, speed: null
    }},
    timestamp: Date.now()
  }});
  if (navigator.geolocation) {{
    const watches = new Map();
    let seq = 90000;
    navigator.geolocation.getCurrentPosition = (ok) => {{ if (typeof ok === 'function') setTimeout(() => ok(makePos(false)), 30); }};
    navigator.geolocation.watchPosition = (ok) => {{
      const id = ++seq;
      if (typeof ok === 'function') {{
        setTimeout(() => ok(makePos(false)), 35);
        watches.set(id, setInterval(() => ok(makePos(true)), 4000));
      }}
      return id;
    }};
    navigator.geolocation.clearWatch = (id) => {{ if (watches.has(id)) {{ clearInterval(watches.get(id)); watches.delete(id); }} }};
  }}
}} catch {{}}");
        }

        sb.AppendLine("})();");
        File.WriteAllText(Path.Combine(extDir, "env.js"), sb.ToString());
        return extDir;
    }

    public void Dispose()
    {
        try { _cts.Cancel(); } catch { }
        try { _inspectorBridge?.Dispose(); } catch { }
        try { Connection.VpnSession?.Dispose(); } catch { }
        try { Connection.SocksForwarder?.Dispose(); } catch { }
        if (_hIconBig != IntPtr.Zero) { DestroyIcon(_hIconBig); _hIconBig = IntPtr.Zero; }
        if (_hIconSmall != IntPtr.Zero) { DestroyIcon(_hIconSmall); _hIconSmall = IntPtr.Zero; }
        Profile.IsRunning = false;
    }
}

/// <summary>
/// Pure .NET WebSocket Chrome DevTools Protocol (CDP) bridge connecting InspectorWindow
/// to a running Real Chromium profile on demand.
/// </summary>
public sealed class CdpInspectorBridge : IDisposable
{
    private readonly int _port;
    private readonly ObservableCollection<CapturedNetRequest> _net;
    private readonly ObservableCollection<InternalSecurityEvent> _internals;
    private readonly Dictionary<string, CapturedNetRequest> _byId = new();
    private readonly Dictionary<int, TaskCompletionSource<string>> _pendingRpc = new();
    private ClientWebSocket? _ws;
    private readonly CancellationTokenSource _cts = new();
    private int _rpcSeq = 10;

    public CdpInspectorBridge(int port, ObservableCollection<CapturedNetRequest> net, ObservableCollection<InternalSecurityEvent> internals)
    {
        _port = port;
        _net = net;
        _internals = internals;
    }

    public static async Task<string?> GetFirstPageWsUrlAsync(int port, CancellationToken ct)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
            string json = await http.GetStringAsync($"http://127.0.0.1:{port}/json", ct);
            using var doc = JsonDocument.Parse(json);
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                if (el.TryGetProperty("type", out var t) && t.GetString() == "page" &&
                    el.TryGetProperty("webSocketDebuggerUrl", out var ws))
                    return ws.GetString();
            }
        }
        catch { }
        return null;
    }

    public async Task StartAsync()
    {
        try
        {
            string? wsUrl = await GetFirstPageWsUrlAsync(_port, _cts.Token);
            if (string.IsNullOrEmpty(wsUrl)) return;

            _ws = new ClientWebSocket();
            await _ws.ConnectAsync(new Uri(wsUrl), _cts.Token);
            await SendRawAsync(JsonSerializer.Serialize(new { id = 1, method = "Network.enable", @params = new { } }));
            await SendRawAsync(JsonSerializer.Serialize(new { id = 2, method = "Audits.enable", @params = new { } }));

            _ = Task.Run(ReceiveLoopAsync);
        }
        catch { }
    }

    public async Task<string> FetchResponseBodyAsync(string requestId)
    {
        if (_ws is null || _ws.State != WebSocketState.Open) return "(Inspector not connected)";
        int id = Interlocked.Increment(ref _rpcSeq);
        var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_pendingRpc) _pendingRpc[id] = tcs;
        try
        {
            await SendRawAsync(JsonSerializer.Serialize(new { id, method = "Network.getResponseBody", @params = new { requestId } }));
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(4));
            using var reg = timeout.Token.Register(() => tcs.TrySetResult("(Timed out reading body)"));
            return await tcs.Task;
        }
        catch (Exception ex) { return $"({ex.Message})"; }
        finally { lock (_pendingRpc) _pendingRpc.Remove(id); }
    }

    private async Task SendRawAsync(string json)
    {
        if (_ws is null || _ws.State != WebSocketState.Open) return;
        await _ws.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, true, _cts.Token);
    }

    private async Task ReceiveLoopAsync()
    {
        var buf = new byte[65536];
        using var ms = new MemoryStream();
        while (_ws is not null && _ws.State == WebSocketState.Open && !_cts.IsCancellationRequested)
        {
            try
            {
                ms.SetLength(0);
                WebSocketReceiveResult res;
                do
                {
                    res = await _ws.ReceiveAsync(buf, _cts.Token);
                    if (res.MessageType == WebSocketMessageType.Close) return;
                    ms.Write(buf, 0, res.Count);
                } while (!res.EndOfMessage);

                HandleMessage(Encoding.UTF8.GetString(ms.ToArray()));
            }
            catch { break; }
        }
    }

    private void HandleMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("id", out var idEl) && idEl.TryGetInt32(out int rpcId))
            {
                TaskCompletionSource<string>? tcs = null;
                lock (_pendingRpc) _pendingRpc.TryGetValue(rpcId, out tcs);
                if (tcs is not null)
                {
                    string body = root.TryGetProperty("result", out var r) && r.TryGetProperty("body", out var b)
                        ? (b.GetString() ?? "")
                        : "(No response body)";
                    tcs.TrySetResult(body);
                }
                return;
            }

            if (!root.TryGetProperty("method", out var mEl)) return;
            string method = mEl.GetString() ?? "";
            if (!root.TryGetProperty("params", out var p)) return;

            if (method == "Network.requestWillBeSent" && p.TryGetProperty("request", out var reqEl))
            {
                string reqId = p.TryGetProperty("requestId", out var rId) ? (rId.GetString() ?? "") : "";
                string rUrl = reqEl.TryGetProperty("url", out var uEl) ? (uEl.GetString() ?? "") : "";
                string rMethod = reqEl.TryGetProperty("method", out var rmEl) ? (rmEl.GetString() ?? "GET") : "GET";
                string resType = p.TryGetProperty("type", out var rtEl) ? (rtEl.GetString() ?? "") : "";
                string postData = reqEl.TryGetProperty("postData", out var pdEl) ? (pdEl.GetString() ?? "") : "";
                string headers = reqEl.TryGetProperty("headers", out var hEl) ? FormatHeaders(hEl) : "";

                var item = new CapturedNetRequest
                {
                    RequestId = reqId,
                    Time = DateTime.Now.ToString("HH:mm:ss"),
                    Method = rMethod,
                    Url = rUrl,
                    ResourceType = resType,
                    RequestHeaders = headers,
                    PostData = postData,
                    StartTickMs = Environment.TickCount64
                };
                lock (_byId) _byId[reqId] = item;
                Application.Current.Dispatcher.BeginInvoke(() =>
                {
                    _net.Insert(0, item);
                    if (_net.Count > 800) _net.RemoveAt(_net.Count - 1);
                });
            }
            else if (method == "Network.responseReceived" && p.TryGetProperty("response", out var respEl))
            {
                string reqId = p.TryGetProperty("requestId", out var rId) ? (rId.GetString() ?? "") : "";
                CapturedNetRequest? item;
                lock (_byId) _byId.TryGetValue(reqId, out item);
                if (item is null) return;

                item.StatusCode = respEl.TryGetProperty("status", out var sEl) ? sEl.GetInt32() : 0;
                item.Protocol = respEl.TryGetProperty("protocol", out var prEl) ? (prEl.GetString() ?? "") : "";
                item.RemoteIp = respEl.TryGetProperty("remoteIPAddress", out var ipEl) ? (ipEl.GetString() ?? "") : "";
                if (respEl.TryGetProperty("headers", out var hEl)) item.ResponseHeaders = FormatHeaders(hEl);
                if (respEl.TryGetProperty("fromServiceWorker", out var swEl) && swEl.GetBoolean()) item.CacheSource = "SW";
                else if (respEl.TryGetProperty("fromDiskCache", out var dkEl) && dkEl.GetBoolean()) item.CacheSource = "DISK";
                if (respEl.TryGetProperty("securityDetails", out var secEl))
                {
                    string proto = secEl.TryGetProperty("protocol", out var sp) ? (sp.GetString() ?? "") : "";
                    string cipher = secEl.TryGetProperty("cipher", out var sc) ? (sc.GetString() ?? "") : "";
                    string subj = secEl.TryGetProperty("subjectName", out var ss) ? (ss.GetString() ?? "") : "";
                    string issuer = secEl.TryGetProperty("issuer", out var si) ? (si.GetString() ?? "") : "";
                    item.TlsInfo = $"Protocol: {proto} | Cipher: {cipher} | SNI/Subject: {subj} | Issuer: {issuer}";
                }
                item.DurationMs = Math.Max(1, Environment.TickCount64 - item.StartTickMs);
                Application.Current.Dispatcher.BeginInvoke(() => item.NotifyUpdate());
            }
            else if (method == "Audits.issueAdded" && p.TryGetProperty("issue", out var iss))
            {
                string code = iss.TryGetProperty("code", out var cEl) ? (cEl.GetString() ?? "AUDIT") : "AUDIT";
                string det = iss.TryGetProperty("details", out var dEl) ? dEl.ToString() : "";
                Application.Current.Dispatcher.BeginInvoke(() =>
                {
                    _internals.Insert(0, new InternalSecurityEvent
                    {
                        Time = DateTime.Now.ToString("HH:mm:ss"),
                        Category = code.ToUpperInvariant(),
                        Source = "Chromium CDP",
                        Detail = det.Length > 260 ? det[..260] + "..." : det
                    });
                    if (_internals.Count > 500) _internals.RemoveAt(_internals.Count - 1);
                });
            }
        }
        catch { }
    }

    private static string FormatHeaders(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object) return "";
        var sb = new StringBuilder();
        foreach (var prop in el.EnumerateObject())
            sb.AppendLine($"{prop.Name}: {prop.Value}");
        return sb.ToString().TrimEnd();
    }

    public void Dispose()
    {
        try { _cts.Cancel(); } catch { }
        try { _ws?.Dispose(); } catch { }
        _ws = null;
    }
}
