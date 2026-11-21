using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MHBrowser;

public sealed class CloudSyncConfig
{
    public string EndpointUrl { get; set; } = "";
    public string BucketName { get; set; } = "mh-profiles";
    public string AccessKeyId { get; set; } = "";
    public string SecretAccessKey { get; set; } = "";
    public string SyncPassword { get; set; } = "";
    public bool AutoSyncOnClose { get; set; } = true;

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(EndpointUrl) &&
        !string.IsNullOrWhiteSpace(BucketName) &&
        !string.IsNullOrWhiteSpace(AccessKeyId) &&
        !string.IsNullOrWhiteSpace(SecretAccessKey) &&
        !string.IsNullOrWhiteSpace(SyncPassword);
}

public static class CloudSyncStore
{
    private static readonly string ConfigPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHAdvancedTool", "cloud_sync.json");

    public static CloudSyncConfig Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
                return JsonSerializer.Deserialize<CloudSyncConfig>(File.ReadAllText(ConfigPath)) ?? new();
        }
        catch { }
        return new();
    }

    public static void Save(CloudSyncConfig cfg)
    {
        try
        {
            var dir = Path.GetDirectoryName(ConfigPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}

/// <summary>
/// Pure .NET 8 AWS Signature V4 client for Cloudflare R2 (and any S3-compatible bucket)
/// with End-to-End AES-256 encryption before upload.
/// </summary>
public static class CloudflareR2Sync
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(3) };

    private static (string BaseEndpoint, string Bucket) NormalizeEndpoint(CloudSyncConfig cfg)
    {
        string ep = cfg.EndpointUrl.Trim().TrimEnd('/');
        string bucket = cfg.BucketName.Trim().Trim('/');
        if (!ep.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
            !ep.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            ep = "https://" + ep;
        // If user pasted endpoint with /<bucket> already attached, strip it cleanly
        if (ep.EndsWith("/" + bucket, StringComparison.OrdinalIgnoreCase))
            ep = ep[..^(bucket.Length + 1)];
        return (ep, bucket);
    }

    private static HttpRequestMessage BuildSignedRequest(
        CloudSyncConfig cfg, HttpMethod method, string objectKey, string query, byte[] payload)
    {
        var (baseEp, bucket) = NormalizeEndpoint(cfg);
        string encodedKey = string.IsNullOrEmpty(objectKey)
            ? ""
            : "/" + string.Join("/", objectKey.Split('/').Select(Uri.EscapeDataString));
        string canonicalUri = $"/{Uri.EscapeDataString(bucket)}{encodedKey}";
        string fullUrl = $"{baseEp}{canonicalUri}" + (string.IsNullOrEmpty(query) ? "" : "?" + query);

        var uri = new Uri(fullUrl);
        string host = uri.IsDefaultPort ? uri.Host : $"{uri.Host}:{uri.Port}";
        var now = DateTime.UtcNow;
        string amzDate = now.ToString("yyyyMMddTHHmmssZ");
        string dateStamp = now.ToString("yyyyMMdd");
        string payloadHash = Sha256Hex(payload);

        string canonicalHeaders = $"host:{host}\nx-amz-content-sha256:{payloadHash}\nx-amz-date:{amzDate}\n";
        const string signedHeaders = "host;x-amz-content-sha256;x-amz-date";
        string canonicalRequest = $"{method.Method}\n{canonicalUri}\n{query}\n{canonicalHeaders}\n{signedHeaders}\n{payloadHash}";

        string scope = $"{dateStamp}/auto/s3/aws4_request";
        string stringToSign = $"AWS4-HMAC-SHA256\n{amzDate}\n{scope}\n{Sha256Hex(Encoding.UTF8.GetBytes(canonicalRequest))}";

        byte[] kDate = HmacSha256(Encoding.UTF8.GetBytes("AWS4" + cfg.SecretAccessKey.Trim()), dateStamp);
        byte[] kRegion = HmacSha256(kDate, "auto");
        byte[] kService = HmacSha256(kRegion, "s3");
        byte[] kSigning = HmacSha256(kService, "aws4_request");
        string signature = Convert.ToHexString(HmacSha256(kSigning, stringToSign)).ToLowerInvariant();

        var req = new HttpRequestMessage(method, fullUrl);
        req.Headers.TryAddWithoutValidation("x-amz-date", amzDate);
        req.Headers.TryAddWithoutValidation("x-amz-content-sha256", payloadHash);
        req.Headers.TryAddWithoutValidation("Authorization",
            $"AWS4-HMAC-SHA256 Credential={cfg.AccessKeyId.Trim()}/{scope}, SignedHeaders={signedHeaders}, Signature={signature}");

        if (payload.Length > 0 || method == HttpMethod.Put)
        {
            req.Content = new ByteArrayContent(payload);
            req.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
        }
        return req;
    }

    public static async Task<(bool Ok, string Message)> TestConnectionAsync(CloudSyncConfig cfg)
    {
        if (!cfg.IsConfigured)
            return (false, "Fill in Endpoint URL, Bucket Name, Access Key ID, Secret Access Key, and Sync Password.");
        try
        {
            using var req = BuildSignedRequest(cfg, HttpMethod.Get, "", "list-type=2&max-keys=1", Array.Empty<byte>());
            using var resp = await Http.SendAsync(req);
            if (resp.IsSuccessStatusCode)
                return (true, $"Connected to Cloudflare R2 bucket '{cfg.BucketName}' successfully!");
            string body = await resp.Content.ReadAsStringAsync();
            return (false, $"R2 returned HTTP {(int)resp.StatusCode}: {body[..Math.Min(220, body.Length)]}");
        }
        catch (Exception ex) { return (false, $"Connection error: {ex.Message}"); }
    }

    public static async Task<(bool Ok, string Message)> PushProfileAsync(CloudSyncConfig cfg, BrowserProfile profile)
    {
        if (!cfg.IsConfigured) return (false, "Cloud Sync not configured.");
        string tmp = Path.Combine(Path.GetTempPath(), $"r2_push_{profile.Id}_{Guid.NewGuid():N}.mhprofile");
        try
        {
            ProfileBackupHelper.ExportEncrypted(profile, tmp, cfg.SyncPassword);
            byte[] data = await File.ReadAllBytesAsync(tmp);
            using var req = BuildSignedRequest(cfg, HttpMethod.Put, $"mh-sync/profiles/{profile.Id}.mhprofile", "", data);
            using var resp = await Http.SendAsync(req);
            if (!resp.IsSuccessStatusCode)
                return (false, $"Upload failed for '{profile.Name}' (HTTP {(int)resp.StatusCode}).");
            return (true, $"Synced '{profile.Name}' ({data.Length / 1024} KB) to R2.");
        }
        catch (Exception ex) { return (false, ex.Message); }
        finally { try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
    }

    private sealed class CloudIndexPayload
    {
        public List<BrowserProfile> Profiles { get; set; } = new();
        public List<SavedProxy> Proxies { get; set; } = new();
        public string UpdatedUtc { get; set; } = "";
    }

    public static async Task<(bool Ok, string Message)> PushAllAsync(
        CloudSyncConfig cfg, IList<BrowserProfile> profiles, IList<SavedProxy> proxies, Action<string>? onProgress = null)
    {
        if (!cfg.IsConfigured) return (false, "Configure Cloudflare R2 credentials first.");
        try
        {
            int done = 0;
            foreach (var p in profiles)
            {
                done++;
                onProgress?.Invoke($"Uploading profile {done}/{profiles.Count}: {p.Name}...");
                var (okP, msgP) = await PushProfileAsync(cfg, p);
                if (!okP) return (false, msgP);
            }

            onProgress?.Invoke("Uploading encrypted profiles & proxies index...");
            var idxPayload = new CloudIndexPayload
            {
                Profiles = profiles.ToList(),
                Proxies = proxies.ToList(),
                UpdatedUtc = DateTime.UtcNow.ToString("O")
            };
            byte[] encIndex = EncryptBytes(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(idxPayload)), cfg.SyncPassword);
            using var req = BuildSignedRequest(cfg, HttpMethod.Put, "mh-sync/index.enc", "", encIndex);
            using var resp = await Http.SendAsync(req);
            if (!resp.IsSuccessStatusCode)
                return (false, $"Index upload failed (HTTP {(int)resp.StatusCode}).");

            return (true, $"Uploaded {profiles.Count} profile(s) & {proxies.Count} proxies to Cloudflare R2.");
        }
        catch (Exception ex) { return (false, $"Push failed: {ex.Message}"); }
    }

    public static async Task<(bool Ok, List<BrowserProfile> Profiles, List<SavedProxy> Proxies, string Message)> PullAllAsync(
        CloudSyncConfig cfg, Action<string>? onProgress = null)
    {
        if (!cfg.IsConfigured) return (false, new(), new(), "Configure Cloudflare R2 credentials first.");
        try
        {
            onProgress?.Invoke("Downloading encrypted index from Cloudflare R2...");
            using var idxReq = BuildSignedRequest(cfg, HttpMethod.Get, "mh-sync/index.enc", "", Array.Empty<byte>());
            using var idxResp = await Http.SendAsync(idxReq);
            if (!idxResp.IsSuccessStatusCode)
                return (false, new(), new(), $"No cloud backup found yet (HTTP {(int)idxResp.StatusCode}). Push from a PC first.");

            byte[] encIndex = await idxResp.Content.ReadAsByteArrayAsync();
            string json = Encoding.UTF8.GetString(DecryptBytes(encIndex, cfg.SyncPassword));
            var index = JsonSerializer.Deserialize<CloudIndexPayload>(json) ?? new CloudIndexPayload();

            var restored = new List<BrowserProfile>();
            int count = 0;
            foreach (var meta in index.Profiles)
            {
                count++;
                onProgress?.Invoke($"Downloading profile {count}/{index.Profiles.Count}: {meta.Name}...");
                string tmp = Path.Combine(Path.GetTempPath(), $"r2_pull_{meta.Id}_{Guid.NewGuid():N}.mhprofile");
                try
                {
                    using var pReq = BuildSignedRequest(cfg, HttpMethod.Get, $"mh-sync/profiles/{meta.Id}.mhprofile", "", Array.Empty<byte>());
                    using var pResp = await Http.SendAsync(pReq);
                    if (pResp.IsSuccessStatusCode)
                    {
                        await File.WriteAllBytesAsync(tmp, await pResp.Content.ReadAsByteArrayAsync());
                        var imported = ProfileBackupHelper.ImportEncrypted(tmp, cfg.SyncPassword);
                        // Preserve original cloud ID & clean name (without "(Imported)" suffix)
                        string srcDir = imported.UserDataDir;
                        imported.Id = meta.Id;
                        imported.Name = meta.Name;
                        if (!srcDir.Equals(imported.UserDataDir, StringComparison.OrdinalIgnoreCase))
                        {
                            if (Directory.Exists(imported.UserDataDir)) Directory.Delete(imported.UserDataDir, true);
                            Directory.Move(srcDir, imported.UserDataDir);
                        }
                        restored.Add(imported);
                    }
                    else
                    {
                        restored.Add(meta);
                    }
                }
                finally { try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
            }

            return (true, restored, index.Proxies ?? new(), $"Pulled {restored.Count} profile(s) & {index.Proxies?.Count ?? 0} proxies from Cloudflare R2.");
        }
        catch (CryptographicException)
        {
            return (false, new(), new(), "Decryption failed — wrong Sync Encryption Password.");
        }
        catch (Exception ex)
        {
            return (false, new(), new(), $"Pull failed: {ex.Message}");
        }
    }

    private static byte[] EncryptBytes(byte[] plain, string password)
    {
        byte[] salt = RandomNumberGenerator.GetBytes(16);
        byte[] iv = RandomNumberGenerator.GetBytes(16);
        byte[] key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
        using var aes = Aes.Create();
        aes.Key = key; aes.IV = iv; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
        using var ms = new MemoryStream();
        ms.Write(salt);
        ms.Write(iv);
        using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
        {
            cs.Write(plain);
            cs.FlushFinalBlock();
        }
        return ms.ToArray();
    }

    private static byte[] DecryptBytes(byte[] data, string password)
    {
        byte[] salt = data.AsSpan(0, 16).ToArray();
        byte[] iv = data.AsSpan(16, 16).ToArray();
        byte[] cipher = data.AsSpan(32).ToArray();
        byte[] key = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
        using var aes = Aes.Create();
        aes.Key = key; aes.IV = iv; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
        using var ms = new MemoryStream(cipher);
        using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
        using var outMs = new MemoryStream();
        cs.CopyTo(outMs);
        return outMs.ToArray();
    }

    private static string Sha256Hex(byte[] data) =>
        Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    private static byte[] HmacSha256(byte[] key, string data)
    {
        using var h = new HMACSHA256(key);
        return h.ComputeHash(Encoding.UTF8.GetBytes(data));
    }
}
