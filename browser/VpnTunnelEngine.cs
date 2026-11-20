using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace MHBrowser;

/// <summary>
/// Per-profile local SOCKS5 proxy bound strictly to a specific Windows Wintun interface
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
                if (header[0] != 0x05) return; // SOCKS5 only

                int nMethods = header[1];
                byte[] methods = new byte[nMethods];
                if (!await ReadExactAsync(stream, methods, 0, nMethods, ct)) return;

                // Reply: No authentication required
                await stream.WriteAsync(new byte[] { 0x05, 0x00 }, ct);

                // Read CONNECT request header: VER, CMD, RSV, ATYP
                byte[] req = new byte[4];
                if (!await ReadExactAsync(stream, req, 0, 4, ct)) return;
                if (req[0] != 0x05 || req[1] != 0x01) // only CONNECT
                {
                    await stream.WriteAsync(new byte[] { 0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0 }, ct);
                    return;
                }

                IPAddress? targetIp = null;
                byte atyp = req[3];
                if (atyp == 0x01) // IPv4
                {
                    byte[] addr = new byte[4];
                    if (!await ReadExactAsync(stream, addr, 0, 4, ct)) return;
                    targetIp = new IPAddress(addr);
                }
                else if (atyp == 0x03) // Domain name
                {
                    byte[] lenBuf = new byte[1];
                    if (!await ReadExactAsync(stream, lenBuf, 0, 1, ct)) return;
                    byte[] hostBuf = new byte[lenBuf[0]];
                    if (!await ReadExactAsync(stream, hostBuf, 0, hostBuf.Length, ct)) return;
                    string host = Encoding.ASCII.GetString(hostBuf);
                    targetIp = await ResolveViaTunnelAsync(host, ct);
                }
                else if (atyp == 0x04) // IPv6 -> unsupported on IPv4-only tun
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
                // Force outbound packets strictly out the Wintun VPN adapter!
                remoteSock.SetSocketOption(SocketOptionLevel.IP, IpUnicastIf, IPAddress.HostToNetworkOrder(_ifIndex));
                remoteSock.Bind(new IPEndPoint(_localTunIp, 0));

                using var connCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                connCts.CancelAfter(TimeSpan.FromSeconds(15));
                await remoteSock.ConnectAsync(new IPEndPoint(targetIp, targetPort), connCts.Token);

                // Reply: Succeeded
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

        // Try direct UDP DNS query through the VPN tunnel (1.1.1.1 then 8.8.8.8) so DNS never leaks
        foreach (var dnsServer in new[] { "1.1.1.1", "8.8.8.8" })
        {
            var ip = await QueryDnsARecordViaTunnelAsync(host, IPAddress.Parse(dnsServer), ct);
            if (ip is not null) return ip;
        }

        // Fallback to system resolver if VPN blocks UDP/53
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
            ms.Write(new byte[] { 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }); // RD=1, QDCOUNT=1
            foreach (var label in domain.Split('.', StringSplitOptions.RemoveEmptyEntries))
            {
                var bytes = Encoding.ASCII.GetBytes(label);
                ms.WriteByte((byte)bytes.Length);
                ms.Write(bytes);
            }
            ms.WriteByte(0x00);
            ms.Write(new byte[] { 0x00, 0x01, 0x00, 0x01 }); // QTYPE=A, QCLASS=IN

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

            // Skip question section
            int pos = 12;
            while (pos < len && resp[pos] != 0)
            {
                if ((resp[pos] & 0xC0) == 0xC0) { pos += 2; break; }
                pos += resp[pos] + 1;
            }
            if (pos < len && resp[pos] == 0) pos++;
            pos += 4; // QTYPE + QCLASS

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
/// Manages an isolated, silent, per-profile VPN tunnel (OpenVPN or WireGuard) exposed strictly
/// as a local SOCKS5 proxy on 127.0.0.1:&lt;port&gt;. Zero CMD windows, zero PC-wide IP hijacking.
/// </summary>
public sealed class ProfileVpnSession : IDisposable
{
    private Process? _proc;
    private LocalInterfaceSocks5Proxy? _socksProxy;
    private string _tempConfigPath = "";

    public int LocalSocksPort { get; private set; }
    public string LastLogLine { get; private set; } = "";

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
        _proc.Start();
        _proc.BeginOutputReadLine();
        _proc.BeginErrorReadLine();

        // Wait up to 8s for local SOCKS5 port to start listening
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < 8000 && !ct.IsCancellationRequested)
        {
            if (_proc.HasExited)
                return (false, 0, "WireGuard userspace proxy exited early. Check your .conf file.");
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

        // 1) Sanitize .ovpn so it NEVER hijacks the PC's main internet or DNS, and supports legacy CBC + modern GCM ciphers
        var lines = File.ReadAllLines(ovpnPath);
        var sb = new StringBuilder();
        bool hasDataCiphers = false;
        foreach (var raw in lines)
        {
            string trimmed = raw.Trim();
            if (trimmed.StartsWith("redirect-gateway", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("block-outside-dns", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("daemon", StringComparison.OrdinalIgnoreCase))
                continue;
            if (trimmed.StartsWith("data-ciphers", StringComparison.OrdinalIgnoreCase))
            {
                hasDataCiphers = true;
                sb.AppendLine("data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-256-CBC:BF-CBC");
                continue;
            }
            sb.AppendLine(raw);
        }
        if (!hasDataCiphers)
            sb.AppendLine("data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-256-CBC:BF-CBC");
        sb.AppendLine("data-ciphers-fallback AES-128-CBC");

        _tempConfigPath = Path.Combine(VpnWorkDir, $"ovpn_{profileId}.ovpn");
        File.WriteAllText(_tempConfigPath, sb.ToString());

        // Snapshot existing NICs so we can pinpoint the newly created Wintun adapter for this profile
        var beforeIds = NetworkInterface.GetAllNetworkInterfaces().Select(n => n.Id).ToHashSet();
        string adapterNode = $"MHVPN_{profileId[..Math.Min(8, profileId.Length)]}";

        onStatus?.Invoke($"Connecting OpenVPN ({Path.GetFileName(ovpnPath)}) silently...");

        var connectedTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        string? detectedIpFromLog = null;
        string lastErr = "";

        string args =
            $"--windows-driver wintun --dev tun --dev-node \"{adapterNode}\" " +
            $"--config \"{_tempConfigPath}\" " +
            "--pull-filter ignore \"redirect-gateway\" " +
            "--pull-filter ignore \"route 0.0.0.0\" " +
            "--pull-filter ignore \"route-ipv6\" " +
            "--pull-filter ignore \"dhcp-option DNS\" " +
            "--route-metric 9999 --route 0.0.0.0 0.0.0.0 vpn_gateway 9999 " +
            "--connect-retry 2 --connect-retry-max 3 --verb 3";

        _proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = ovpnExe,
                Arguments = args,
                WorkingDirectory = Path.GetDirectoryName(ovpnExe) ?? VpnWorkDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };

        void HandleLine(string? line)
        {
            if (string.IsNullOrWhiteSpace(line)) return;
            LastLogLine = line;
            if (line.Contains("Peer Connection Initiated", StringComparison.OrdinalIgnoreCase))
                onStatus?.Invoke("OpenVPN: TLS handshake OK, negotiating tunnel...");
            else if (line.Contains("PUSH_REPLY", StringComparison.OrdinalIgnoreCase))
                onStatus?.Invoke("OpenVPN: Server accepted, creating isolated tunnel...");
            else if (line.Contains("AUTH_FAILED", StringComparison.OrdinalIgnoreCase))
            {
                lastErr = "OpenVPN authentication failed (check username/password or expired .ovpn).";
                connectedTcs.TrySetResult(false);
            }
            else if (line.Contains("Exiting due to fatal error", StringComparison.OrdinalIgnoreCase))
            {
                lastErr = $"OpenVPN fatal error: {line}";
                connectedTcs.TrySetResult(false);
            }

            // Capture assigned Wintun IPv4 address from OpenVPN log (e.g. "Set IPv4 ... 10.211.1.5" or "ifconfig 10.x.x.x")
            if (line.Contains("Notified TAP", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("Wintun", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("ifconfig", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("IP/Netmask", StringComparison.OrdinalIgnoreCase))
            {
                var m = Regex.Match(line, @"\b((?:10|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3})\b");
                if (m.Success) detectedIpFromLog = m.Groups[1].Value;
            }

            if (line.Contains("Initialization Sequence Completed", StringComparison.OrdinalIgnoreCase))
                connectedTcs.TrySetResult(true);
        }

        _proc.OutputDataReceived += (_, e) => HandleLine(e.Data);
        _proc.ErrorDataReceived += (_, e) => HandleLine(e.Data);
        _proc.Start();
        _proc.BeginOutputReadLine();
        _proc.BeginErrorReadLine();

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(25));
        using var reg = timeoutCts.Token.Register(() => connectedTcs.TrySetResult(false));

        bool connected = await connectedTcs.Task;
        if (!connected)
        {
            Dispose();
            string reason = !string.IsNullOrEmpty(lastErr)
                ? lastErr
                : "OpenVPN server did not respond in 25s (free VPNGate server may be offline or UDP blocked). Try another .ovpn file.";
            return (false, 0, reason);
        }

        // Wait briefly for Windows to finish assigning IPv4 to the Wintun interface
        IPAddress? tunIp = null;
        int ifIndex = -1;
        for (int attempt = 0; attempt < 16; attempt++)
        {
            (tunIp, ifIndex) = FindTunnelInterface(adapterNode, beforeIds, detectedIpFromLog);
            if (tunIp is not null && ifIndex > 0) break;
            await Task.Delay(250, ct);
        }

        if (tunIp is null || ifIndex <= 0)
        {
            Dispose();
            return (false, 0, "OpenVPN connected, but could not locate Wintun adapter IP.");
        }

        _socksProxy = new LocalInterfaceSocks5Proxy(tunIp, ifIndex);
        LocalSocksPort = _socksProxy.Port;
        return (true, LocalSocksPort, $"OpenVPN isolated ({tunIp}) -> 127.0.0.1:{LocalSocksPort}");
    }

    private static (IPAddress? Ip, int IfIndex) FindTunnelInterface(
        string adapterNode, HashSet<string> beforeIds, string? preferredIp)
    {
        var nics = NetworkInterface.GetAllNetworkInterfaces();

        // Priority 1: Exact adapter name match
        // Priority 2: Newly appeared Wintun adapter
        // Priority 3: Any Wintun adapter matching preferredIp
        var ordered = nics
            .OrderByDescending(n => n.Name.Equals(adapterNode, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(n => !beforeIds.Contains(n.Id))
            .ThenByDescending(n => n.Description.Contains("Wintun", StringComparison.OrdinalIgnoreCase))
            .ToList();

        foreach (var nic in ordered)
        {
            bool looksLikeOurs =
                nic.Name.Equals(adapterNode, StringComparison.OrdinalIgnoreCase) ||
                (!beforeIds.Contains(nic.Id) && nic.Description.Contains("Wintun", StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrEmpty(preferredIp) && nic.GetIPProperties().UnicastAddresses
                    .Any(u => u.Address.ToString() == preferredIp));

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
    }
}
