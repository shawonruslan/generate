using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace MHBrowser;

/// <summary>
/// Per-profile local SOCKS5 proxy bound strictly to a specific Windows TAP/Wintun interface
/// via IP_UNICAST_IF + local tunnel IP bind, including tunnel-routed DNS resolution.
/// Keeps the host PC's main internet & IP completely untouched.
/// </summary>
public sealed class LocalInterfaceSocks5Proxy : IDisposable
{
    private const SocketOptionName IpUnicastIf = (SocketOptionName)31; // Windows IP_UNICAST_IF

    private readonly IPAddress _localTunIp;
    private readonly int _ifIndex;
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _cts = new();

    public int Port { get; }

    public LocalInterfaceSocks5Proxy(IPAddress localTunIp, int interfaceIndex)
    {
        _localTunIp = localTunIp;
        _ifIndex = interfaceIndex;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        _ = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(ct);
                client.NoDelay = true;
                _ = Task.Run(() => HandleClientAsync(client, ct), ct);
            }
            catch { break; }
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream();
                byte[] header = new byte[2];
                if (!await ReadExactAsync(stream, header, 0, 2, ct)) return;
                if (header[0] != 0x05) return;

                int nMethods = header[1];
                byte[] methods = new byte[nMethods];
                if (!await ReadExactAsync(stream, methods, 0, nMethods, ct)) return;

                await stream.WriteAsync(new byte[] { 0x05, 0x00 }, ct);

                byte[] req = new byte[4];
                if (!await ReadExactAsync(stream, req, 0, 4, ct)) return;
                if (req[0] != 0x05 || req[1] != 0x01)
                {
                    await stream.WriteAsync(new byte[] { 0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0 }, ct);
                    return;
                }

                IPAddress? targetIp = null;
                byte atyp = req[3];
                if (atyp == 0x01)
                {
                    byte[] addr = new byte[4];
                    if (!await ReadExactAsync(stream, addr, 0, 4, ct)) return;
                    targetIp = new IPAddress(addr);
                }
                else if (atyp == 0x03)
                {
                    byte[] lenBuf = new byte[1];
                    if (!await ReadExactAsync(stream, lenBuf, 0, 1, ct)) return;
                    byte[] hostBuf = new byte[lenBuf[0]];
                    if (!await ReadExactAsync(stream, hostBuf, 0, hostBuf.Length, ct)) return;
                    string host = Encoding.ASCII.GetString(hostBuf);
                    targetIp = await ResolveViaTunnelAsync(host, ct);
                }
                else if (atyp == 0x04)
                {
                    byte[] addr = new byte[16];
                    if (!await ReadExactAsync(stream, addr, 0, 16, ct)) return;
                    await stream.WriteAsync(new byte[] { 0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0 }, ct);
                    return;
                }

                byte[] portBuf = new byte[2];
                if (!await ReadExactAsync(stream, portBuf, 0, 2, ct)) return;
                int targetPort = (portBuf[0] << 8) | portBuf[1];

                if (targetIp is null)
                {
                    await stream.WriteAsync(new byte[] { 0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0 }, ct);
                    return;
                }

                using var remoteSock = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                remoteSock.NoDelay = true;
                remoteSock.SetSocketOption(SocketOptionLevel.IP, IpUnicastIf, IPAddress.HostToNetworkOrder(_ifIndex));
                remoteSock.Bind(new IPEndPoint(_localTunIp, 0));

                using var connCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                connCts.CancelAfter(TimeSpan.FromSeconds(15));
                await remoteSock.ConnectAsync(new IPEndPoint(targetIp, targetPort), connCts.Token);

                await stream.WriteAsync(new byte[] { 0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0 }, ct);

                using var remoteStream = new NetworkStream(remoteSock, ownsSocket: false);
                var t1 = stream.CopyToAsync(remoteStream, 16384, ct);
                var t2 = remoteStream.CopyToAsync(stream, 16384, ct);
                await Task.WhenAny(t1, t2);
            }
            catch { }
        }
    }

    private async Task<IPAddress?> ResolveViaTunnelAsync(string host, CancellationToken ct)
    {
        if (IPAddress.TryParse(host, out var parsed) && parsed.AddressFamily == AddressFamily.InterNetwork)
            return parsed;

        foreach (var dnsServer in new[] { "1.1.1.1", "8.8.8.8" })
        {
            var ip = await QueryDnsARecordViaTunnelAsync(host, IPAddress.Parse(dnsServer), ct);
            if (ip is not null) return ip;
        }

        try
        {
            var addrs = await Dns.GetHostAddressesAsync(host, ct);
            return addrs.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork);
        }
        catch { return null; }
    }

    private async Task<IPAddress?> QueryDnsARecordViaTunnelAsync(string domain, IPAddress dnsIp, CancellationToken ct)
    {
        try
        {
            using var udp = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            udp.SetSocketOption(SocketOptionLevel.IP, IpUnicastIf, IPAddress.HostToNetworkOrder(_ifIndex));
            udp.Bind(new IPEndPoint(_localTunIp, 0));

            using var ms = new MemoryStream();
            ushort txId = (ushort)Random.Shared.Next(1, 65535);
            ms.WriteByte((byte)(txId >> 8));
            ms.WriteByte((byte)(txId & 0xFF));
            ms.Write(new byte[] { 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
            foreach (var label in domain.Split('.', StringSplitOptions.RemoveEmptyEntries))
            {
                var bytes = Encoding.ASCII.GetBytes(label);
                ms.WriteByte((byte)bytes.Length);
                ms.Write(bytes);
            }
            ms.WriteByte(0x00);
            ms.Write(new byte[] { 0x00, 0x01, 0x00, 0x01 });

            var query = ms.ToArray();
            using var dnsCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            dnsCts.CancelAfter(TimeSpan.FromMilliseconds(2200));

            await udp.SendToAsync(query, SocketFlags.None, new IPEndPoint(dnsIp, 53), dnsCts.Token);
            byte[] resp = new byte[512];
            var res = await udp.ReceiveFromAsync(resp, SocketFlags.None, new IPEndPoint(IPAddress.Any, 0), dnsCts.Token);
            int len = res.ReceivedBytes;
            if (len < 12) return null;

            int anCount = (resp[6] << 8) | resp[7];
            if (anCount == 0) return null;

            int pos = 12;
            while (pos < len && resp[pos] != 0)
            {
                if ((resp[pos] & 0xC0) == 0xC0) { pos += 2; break; }
                pos += resp[pos] + 1;
            }
            if (pos < len && resp[pos] == 0) pos++;
            pos += 4;

            for (int i = 0; i < anCount && pos + 12 <= len; i++)
            {
                if ((resp[pos] & 0xC0) == 0xC0) pos += 2;
                else
                {
                    while (pos < len && resp[pos] != 0) pos += resp[pos] + 1;
                    pos++;
                }
                if (pos + 10 > len) break;
                int type = (resp[pos] << 8) | resp[pos + 1];
                int rdLen = (resp[pos + 8] << 8) | resp[pos + 9];
                pos += 10;
                if (type == 1 && rdLen == 4 && pos + 4 <= len)
                    return new IPAddress(new ReadOnlySpan<byte>(resp, pos, 4));
                pos += rdLen;
            }
        }
        catch { }
        return null;
    }

    private static async Task<bool> ReadExactAsync(Stream s, byte[] buf, int offset, int count, CancellationToken ct)
    {
        int total = 0;
        while (total < count)
        {
            int n = await s.ReadAsync(buf.AsMemory(offset + total, count - total), ct);
            if (n <= 0) return false;
            total += n;
        }
        return true;
    }

    public void Dispose()
    {
        try { _cts.Cancel(); } catch { }
        try { _listener.Stop(); } catch { }
        _cts.Dispose();
    }
}

/// <summary>
/// Manages an isolated, silent, per-profile VPN tunnel (OpenVPN via TAP-Windows6 or WireGuard via wireproxy)
/// exposed strictly as a local SOCKS5 proxy on 127.0.0.1:&lt;port&gt;. Zero CMD windows, zero PC-wide IP hijacking.
/// </summary>
public sealed class ProfileVpnSession : IDisposable
{
    private Process? _proc;
    private LocalInterfaceSocks5Proxy? _socksProxy;
    private string _tempConfigPath = "";
    private string _createdAdapterName = "";
    private string _tapCtlPath = "";

    public int LocalSocksPort { get; private set; }

    private static string VpnWorkDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MHAdvancedTool", "vpn");

    public async Task<(bool Ok, int SocksPort, string Message)> StartAsync(
        string profileId, string vpnType, string configPath, Action<string>? onStatus = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
            return (false, 0, "VPN config file not found. Check profile settings.");

        Directory.CreateDirectory(VpnWorkDir);

        return vpnType == "WireGuard"
            ? await StartWireGuardUserspaceAsync(profileId, configPath, onStatus, ct)
            : await StartOpenVpnIsolatedAsync(profileId, configPath, onStatus, ct);
    }

    private async Task<(bool Ok, int SocksPort, string Message)> StartWireGuardUserspaceAsync(
        string profileId, string confPath, Action<string>? onStatus, CancellationToken ct)
    {
        var wireproxy = VpnController.FindWireProxy();
        if (wireproxy is null)
            return (false, 0, "wireproxy.exe not found in app vpn/wireguard folder.");

        int port = FindFreeTcpPort();
        var copiedWg = Path.Combine(VpnWorkDir, $"wg_{profileId}.conf");
        File.Copy(confPath, copiedWg, overwrite: true);

        _tempConfigPath = Path.Combine(VpnWorkDir, $"wp_{profileId}.conf");
        File.WriteAllText(_tempConfigPath,
            $"WGConfig = {copiedWg}\r\n\r\n[Socks5]\r\nBindAddress = 127.0.0.1:{port}\r\n");

        onStatus?.Invoke($"Starting isolated WireGuard ({Path.GetFileName(confPath)})...");
        var logs = new List<string>();
        _proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = wireproxy,
                Arguments = $"-c \"{_tempConfigPath}\"",
                WorkingDirectory = Path.GetDirectoryName(wireproxy) ?? VpnWorkDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };
        _proc.OutputDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) lock (logs) logs.Add(e.Data); };
        _proc.ErrorDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) lock (logs) logs.Add(e.Data); };
        _proc.Start();
        _proc.BeginOutputReadLine();
        _proc.BeginErrorReadLine();

        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < 8000 && !ct.IsCancellationRequested)
        {
            if (_proc.HasExited)
            {
                string tail = string.Join("\n", logs.TakeLast(6));
                return (false, 0, $"WireGuard exited early:\n{tail}");
            }
            try
            {
                using var probe = new TcpClient();
                await probe.ConnectAsync(IPAddress.Loopback, port, ct);
                LocalSocksPort = port;
                return (true, port, $"WireGuard isolated on 127.0.0.1:{port}");
            }
            catch { await Task.Delay(250, ct); }
        }
        return (false, 0, "WireGuard tunnel timed out starting local proxy.");
    }

    private async Task<(bool Ok, int SocksPort, string Message)> StartOpenVpnIsolatedAsync(
        string profileId, string ovpnPath, Action<string>? onStatus, CancellationToken ct)
    {
        var ovpnExe = VpnController.FindOpenVpn();
        if (ovpnExe is null)
            return (false, 0, "openvpn.exe not found in app vpn/openvpn folder.");

        string ovpnDir = Path.GetDirectoryName(ovpnExe) ?? VpnWorkDir;
        _tapCtlPath = Path.Combine(ovpnDir, "tapctl.exe");

        // 1) Ensure a dedicated TAP-Windows6 adapter exists for this profile (created silently via tapctl.exe)
        string adapterNode = $"MHVPN_{profileId[..Math.Min(8, profileId.Length)]}";
        bool createdDedicatedAdapter = false;
        if (File.Exists(_tapCtlPath))
        {
            onStatus?.Invoke("Preparing isolated TAP tunnel adapter...");
            // Clean any stale leftover adapter with the same name first
            await RunHiddenAsync(_tapCtlPath, $"delete \"{adapterNode}\"", ovpnDir);
            var (okTap, _) = await RunHiddenAsync(_tapCtlPath, $"create --name \"{adapterNode}\" --hwid root\\tap0901", ovpnDir);
            if (!okTap)
                (okTap, _) = await RunHiddenAsync(_tapCtlPath, $"create --name \"{adapterNode}\"", ovpnDir);

            if (okTap)
            {
                createdDedicatedAdapter = true;
                _createdAdapterName = adapterNode;
                await Task.Delay(600, ct);
            }
        }

        // 2) Sanitize .ovpn so it NEVER hijacks the PC's main internet or DNS, and works with legacy CBC + modern GCM
        var lines = File.ReadAllLines(ovpnPath);
        var sb = new StringBuilder();
        bool hasDataCiphers = false;
        foreach (var raw in lines)
        {
            string trimmed = raw.Trim();
            if (trimmed.StartsWith("redirect-gateway", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("block-outside-dns", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("daemon", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("windows-driver", StringComparison.OrdinalIgnoreCase))
                continue;
            if (trimmed.StartsWith("data-ciphers", StringComparison.OrdinalIgnoreCase) &&
                !trimmed.StartsWith("data-ciphers-fallback", StringComparison.OrdinalIgnoreCase))
            {
                hasDataCiphers = true;
                sb.AppendLine("data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-256-CBC");
                continue;
            }
            sb.AppendLine(raw);
        }
        if (!hasDataCiphers)
            sb.AppendLine("data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-256-CBC");
        sb.AppendLine("data-ciphers-fallback AES-128-CBC");

        _tempConfigPath = Path.Combine(VpnWorkDir, $"ovpn_{profileId}.ovpn");
        File.WriteAllText(_tempConfigPath, sb.ToString());

        onStatus?.Invoke($"Connecting OpenVPN ({Path.GetFileName(ovpnPath)}) silently...");

        var connectedTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var logTail = new Queue<string>(14);
        string? detectedIpFromLog = null;

        string devNodeArg = createdDedicatedAdapter ? $"--dev-node \"{adapterNode}\" " : "";
        string args =
            $"--windows-driver tap-windows6 --dev tun {devNodeArg}" +
            $"--config \"{_tempConfigPath}\" " +
            "--pull-filter ignore \"redirect-gateway\" " +
            "--pull-filter ignore \"route 0.0.0.0\" " +
            "--pull-filter ignore \"route-ipv6\" " +
            "--pull-filter ignore \"dhcp-option DNS\" " +
            "--route-metric 9999 --route 0.0.0.0 0.0.0.0 vpn_gateway 9999 " +
            "--verb 3";

        _proc = new Process
        {
            EnableRaisingEvents = true,
            StartInfo = new ProcessStartInfo
            {
                FileName = ovpnExe,
                Arguments = args,
                WorkingDirectory = ovpnDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };

        void HandleLine(string? line)
        {
            if (string.IsNullOrWhiteSpace(line)) return;
            lock (logTail)
            {
                if (logTail.Count >= 12) logTail.Dequeue();
                logTail.Enqueue(line);
            }
            if (line.Contains("Peer Connection Initiated", StringComparison.OrdinalIgnoreCase))
                onStatus?.Invoke("OpenVPN: TLS handshake OK, negotiating tunnel...");
            else if (line.Contains("PUSH_REPLY", StringComparison.OrdinalIgnoreCase))
                onStatus?.Invoke("OpenVPN: Server accepted, configuring isolated tunnel...");

            if (line.Contains("Notified TAP", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("TAP-WIN", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("ifconfig", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("IP/Netmask", StringComparison.OrdinalIgnoreCase))
            {
                var m = Regex.Match(line, @"\b((?:10|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3})\b");
                if (m.Success) detectedIpFromLog = m.Groups[1].Value;
            }

            if (line.Contains("Initialization Sequence Completed", StringComparison.OrdinalIgnoreCase))
                connectedTcs.TrySetResult(true);
            else if (line.Contains("AUTH_FAILED", StringComparison.OrdinalIgnoreCase) ||
                     line.Contains("Exiting due to fatal error", StringComparison.OrdinalIgnoreCase))
                connectedTcs.TrySetResult(false);
        }

        _proc.OutputDataReceived += (_, e) => HandleLine(e.Data);
        _proc.ErrorDataReceived += (_, e) => HandleLine(e.Data);
        _proc.Exited += (_, _) => connectedTcs.TrySetResult(false);

        _proc.Start();
        _proc.BeginOutputReadLine();
        _proc.BeginErrorReadLine();

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(28));
        using var reg = timeoutCts.Token.Register(() => connectedTcs.TrySetResult(false));

        bool connected = await connectedTcs.Task;
        if (!connected)
        {
            string recentLogs;
            lock (logTail) recentLogs = string.Join("\n", logTail);
            Dispose();
            return (false, 0,
                $"OpenVPN could not connect.\n\nLast OpenVPN output:\n{(string.IsNullOrWhiteSpace(recentLogs) ? "(no output)" : recentLogs)}");
        }

        // Wait briefly for Windows IP stack to finish binding IPv4 on the TAP adapter
        IPAddress? tunIp = null;
        int ifIndex = -1;
        for (int attempt = 0; attempt < 20; attempt++)
        {
            (tunIp, ifIndex) = FindTunnelInterface(createdDedicatedAdapter ? adapterNode : "", detectedIpFromLog);
            if (tunIp is not null && ifIndex > 0) break;
            await Task.Delay(250, ct);
        }

        if (tunIp is null || ifIndex <= 0)
        {
            Dispose();
            return (false, 0, "OpenVPN connected, but could not locate TAP adapter IPv4 address.");
        }

        _socksProxy = new LocalInterfaceSocks5Proxy(tunIp, ifIndex);
        LocalSocksPort = _socksProxy.Port;
        return (true, LocalSocksPort, $"OpenVPN isolated ({tunIp}) -> 127.0.0.1:{LocalSocksPort}");
    }

    private static (IPAddress? Ip, int IfIndex) FindTunnelInterface(string adapterNode, string? preferredIp)
    {
        var nics = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up)
            .OrderByDescending(n => !string.IsNullOrEmpty(adapterNode) && n.Name.Equals(adapterNode, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(n => n.Description.Contains("TAP-Windows", StringComparison.OrdinalIgnoreCase) ||
                                   n.Description.Contains("Wintun", StringComparison.OrdinalIgnoreCase))
            .ToList();

        foreach (var nic in nics)
        {
            bool looksLikeOurs =
                (!string.IsNullOrEmpty(adapterNode) && nic.Name.Equals(adapterNode, StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrEmpty(preferredIp) && nic.GetIPProperties().UnicastAddresses
                    .Any(u => u.Address.ToString() == preferredIp)) ||
                nic.Description.Contains("TAP-Windows", StringComparison.OrdinalIgnoreCase) ||
                nic.Description.Contains("Wintun", StringComparison.OrdinalIgnoreCase);

            if (!looksLikeOurs) continue;

            var ipProps = nic.GetIPProperties();
            var ipv4Props = ipProps.GetIPv4Properties();
            var unicast = ipProps.UnicastAddresses
                .FirstOrDefault(u => u.Address.AddressFamily == AddressFamily.InterNetwork &&
                                     !IPAddress.IsLoopback(u.Address) &&
                                     !u.Address.ToString().StartsWith("169.254."));
            if (unicast is not null && ipv4Props is not null && ipv4Props.Index > 0)
                return (unicast.Address, ipv4Props.Index);
        }
        return (null, -1);
    }

    private static async Task<(bool Ok, string Output)> RunHiddenAsync(string fileName, string args, string workDir)
    {
        try
        {
            using var p = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = args,
                    WorkingDirectory = workDir,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                }
            };
            p.Start();
            string stdout = await p.StandardOutput.ReadToEndAsync();
            string stderr = await p.StandardError.ReadToEndAsync();
            await p.WaitForExitAsync();
            return (p.ExitCode == 0, stdout + "\n" + stderr);
        }
        catch (Exception ex) { return (false, ex.Message); }
    }

    private static int FindFreeTcpPort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    public void Dispose()
    {
        try { _socksProxy?.Dispose(); } catch { }
        _socksProxy = null;
        try
        {
            if (_proc is not null && !_proc.HasExited)
                _proc.Kill(entireProcessTree: true);
        }
        catch { }
        try { _proc?.Dispose(); } catch { }
        _proc = null;

        if (!string.IsNullOrEmpty(_createdAdapterName) && File.Exists(_tapCtlPath))
        {
            var name = _createdAdapterName;
            var ctl = _tapCtlPath;
            _createdAdapterName = "";
            _ = Task.Run(() => RunHiddenAsync(ctl, $"delete \"{name}\"", Path.GetDirectoryName(ctl) ?? VpnWorkDir));
        }
    }
}
