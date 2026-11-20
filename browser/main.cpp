// main.cpp - MH Browser (Gecko Engine + Proxy / OpenVPN / WireGuard + UA Switcher + Auto IP Timezone)
// Native C++17 Win32 dark-mode Network, Fingerprint & Browser launcher for Mozilla Gecko:
//   - HTTP / HTTPS / SOCKS5 Proxy (with Remote DNS & WebRTC IP leak protection)
//   - Built-in Portable OpenVPN (.ovpn) & WireGuard (.conf) Connect / Disconnect
//   - Professional User-Agent Switcher (PC, Mobile, Smart TV, Gaming Console + Custom)
//   - Auto Timezone Sync from active VPN / Proxy IP (via Gecko TZ env variable)
//   - Isolated Gecko profile with MH dark theme & Live WebRTC Camera Tester
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commdlg.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <winhttp.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <algorithm>

namespace fs = std::filesystem;

enum {
    IDC_PROXY_TYPE = 101,
    IDC_PROXY_HOST,
    IDC_PROXY_PORT,
    IDC_PROXY_USER,
    IDC_PROXY_PASS,
    IDC_CHK_REMOTE_DNS,
    IDC_CHK_WEBRTC_PROTECT,
    IDC_OVPN_PATH,
    IDC_BTN_OVPN_BROWSE,
    IDC_BTN_OVPN_CONNECT,
    IDC_BTN_OVPN_DISCONNECT,
    IDC_WG_PATH,
    IDC_BTN_WG_BROWSE,
    IDC_BTN_WG_CONNECT,
    IDC_BTN_WG_DISCONNECT,
    IDC_UA_PRESET,
    IDC_UA_CUSTOM,
    IDC_CHK_AUTO_TZ,
    IDC_TZ_OVERRIDE,
    IDC_BTN_CHECK_IP_TZ,
    IDC_BTN_LAUNCH,
    IDC_BTN_SAVE_ONLY,
    IDC_STATUS_LABEL
};

struct UaPreset {
    const wchar_t* label;
    const char* ua;
    const char* platform;
};

static const UaPreset kUaPresets[] = {
    { L"[Default] Native Gecko (No Override)", "", "" },

    // PC / Desktop
    { L"[PC] Windows 11 - Chrome 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "Win32" },
    { L"[PC] Windows 11 - Firefox 133", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0", "Win32" },
    { L"[PC] Windows 11 - Edge 131", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0", "Win32" },
    { L"[PC] macOS Sequoia - Safari 18", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15", "MacIntel" },
    { L"[PC] macOS Sequoia - Chrome 131", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "MacIntel" },
    { L"[PC] Ubuntu Linux - Firefox 133", "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0", "Linux x86_64" },

    // Mobile / Tablet
    { L"[Mobile] iPhone 16 Pro (iOS 18 Safari)", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPhone" },
    { L"[Mobile] iPhone 15 (iOS 17 Chrome)", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 Mobile/15E148 Safari/604.1", "iPhone" },
    { L"[Mobile] Samsung Galaxy S25 Ultra (Android 15)", "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l" },
    { L"[Mobile] Google Pixel 9 Pro (Android 15)", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l" },
    { L"[Mobile] OnePlus 13 (Android 15 Firefox)", "Mozilla/5.0 (Android 15; Mobile; rv:133.0) Gecko/133.0 Firefox/133.0", "Linux armv8l" },
    { L"[Mobile] Xiaomi 15 Pro (Android 15 Chrome)", "Mozilla/5.0 (Linux; Android 15; 24101PNB7C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.81 Mobile Safari/537.36", "Linux armv8l" },
    { L"[Tablet] iPad Pro M4 (iPadOS 18 Safari)", "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", "iPad" },

    // Smart TV
    { L"[TV] Samsung Tizen Smart TV", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 8.0) AppleWebKit/537.36 (KHTML, like Gecko) 108.0.5359.125/8.0 TV Safari/537.36", "Linux armv7l" },
    { L"[TV] LG webOS Smart TV", "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.5359.211 Safari/537.36 WebAppManager", "Linux armv7l" },
    { L"[TV] Android TV / Google TV", "Mozilla/5.0 (Linux; Android 14; Chromecast HD) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Linux armv8l" },
    { L"[TV] Amazon Fire TV Stick 4K", "Mozilla/5.0 (Linux; Android 11; AFTKA Build/RS8149) AppleWebKit/537.36 (KHTML, like Gecko) Silk/130.3.2 like Chrome/130.0.6723.102 Safari/537.36", "Linux armv8l" },

    // Gaming Consoles
    { L"[Console] PlayStation 5 (PS5)", "Mozilla/5.0 (PlayStation; PlayStation 5/9.60) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", "PlayStation 5" },
    { L"[Console] PlayStation 4 (PS4)", "Mozilla/5.0 (PlayStation 4 11.50) AppleWebKit/605.1.15 (KHTML, like Gecko)", "PlayStation 4" },
    { L"[Console] Xbox Series X (Edge)", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox Series X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edge/44.18363.8131", "Win32" },
    { L"[Console] Nintendo Switch", "Mozilla/5.0 (Nintendo Switch; WifiWebAuthApplet) AppleWebKit/609.4 (KHTML, like Gecko) NF/6.0.2.21.3 NintendoBrowser/5.1.0.22474", "Nintendo Switch" },
    { L"[Console] Valve Steam Deck (SteamOS)", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Valve Steam GameOverlay/1730000000 Chrome/131.0.0.0 Safari/537.36", "Linux x86_64" }
};
static const int kUaPresetCount = (int)(sizeof(kUaPresets) / sizeof(kUaPresets[0]));

struct NetworkConfig {
    int proxyType = 0; // 0=Direct, 1=HTTP, 2=HTTPS, 3=SOCKS5
    std::wstring proxyHost;
    std::wstring proxyPort;
    std::wstring proxyUser;
    std::wstring proxyPass;
    bool socksRemoteDns = true;
    bool webrtcProtect = true;
    std::wstring ovpnPath;
    std::wstring wgPath;
    int uaIndex = 0;
    std::wstring customUa;
    std::wstring uaPlatform;
    bool autoTimezone = true;
    std::wstring tzOverride; // auto-filled or manual IANA timezone e.g. America/New_York
};

static NetworkConfig g_cfg;
static std::wstring g_detectedIp;
static std::wstring g_detectedLocation;
static HWND g_hwnd = nullptr;
static HWND g_cbProxyType = nullptr, g_edHost = nullptr, g_edPort = nullptr;
static HWND g_edUser = nullptr, g_edPass = nullptr;
static HWND g_chkRemoteDns = nullptr, g_chkWebRtc = nullptr;
static HWND g_edOvpn = nullptr, g_edWg = nullptr;
static HWND g_cbUa = nullptr, g_edUaCustom = nullptr;
static HWND g_chkAutoTz = nullptr, g_edTz = nullptr;
static HWND g_lblStatus = nullptr;
static HFONT g_fontUi = nullptr, g_fontBold = nullptr, g_fontTitle = nullptr;
static HBRUSH g_brBg = nullptr, g_brSurface = nullptr, g_brEdit = nullptr;

static std::wstring GetLocalAppDataDir() {
    wchar_t buf[MAX_PATH] = {};
    DWORD len = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
    return (len > 0 && len < MAX_PATH) ? std::wstring(buf) : L"C:\\Users\\Public";
}

static std::wstring GetExeDir() {
    wchar_t buf[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, buf, MAX_PATH);
    return fs::path(buf).parent_path().wstring();
}

static fs::path GetProfileDir() { return fs::path(GetLocalAppDataDir()) / L"MHVirtualCam" / L"MHBrowserGeckoProfile"; }
static fs::path GetVpnDir() { return fs::path(GetLocalAppDataDir()) / L"MHVirtualCam" / L"vpn"; }

static std::string WideToUtf8(const std::wstring& w) {
    if (w.empty()) return "";
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    if (n <= 0) return "";
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

static std::wstring Utf8ToWide(const std::string& s) {
    if (s.empty()) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    if (n <= 0) return L"";
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

static std::wstring GetEditText(HWND h) {
    int len = GetWindowTextLengthW(h);
    if (len <= 0) return L"";
    std::wstring s((size_t)len, L'\0');
    GetWindowTextW(h, s.data(), len + 1);
    return s;
}

static void SetStatus(const std::wstring& msg) {
    if (g_lblStatus) SetWindowTextW(g_lblStatus, msg.c_str());
}

static void WriteTextFile(const fs::path& path, const std::string& content) {
    std::error_code ec;
    fs::create_directories(path.parent_path(), ec);
    std::ofstream ofs(path, std::ios::binary | std::ios::trunc);
    if (ofs) ofs.write(content.data(), (std::streamsize)content.size());
}

static std::string EscapeJs(const std::string& in) {
    std::string out;
    for (char c : in) {
        if (c == '\\' || c == '"') out.push_back('\\');
        out.push_back(c);
    }
    return out;
}

static void SaveConfig() {
    fs::path ini = GetProfileDir() / L"network.ini";
    std::ostringstream oss;
    oss << "proxyType=" << g_cfg.proxyType << "\n"
        << "proxyHost=" << WideToUtf8(g_cfg.proxyHost) << "\n"
        << "proxyPort=" << WideToUtf8(g_cfg.proxyPort) << "\n"
        << "proxyUser=" << WideToUtf8(g_cfg.proxyUser) << "\n"
        << "proxyPass=" << WideToUtf8(g_cfg.proxyPass) << "\n"
        << "socksRemoteDns=" << (g_cfg.socksRemoteDns ? 1 : 0) << "\n"
        << "webrtcProtect=" << (g_cfg.webrtcProtect ? 1 : 0) << "\n"
        << "ovpnPath=" << WideToUtf8(g_cfg.ovpnPath) << "\n"
        << "wgPath=" << WideToUtf8(g_cfg.wgPath) << "\n"
        << "uaIndex=" << g_cfg.uaIndex << "\n"
        << "customUa=" << WideToUtf8(g_cfg.customUa) << "\n"
        << "uaPlatform=" << WideToUtf8(g_cfg.uaPlatform) << "\n"
        << "autoTimezone=" << (g_cfg.autoTimezone ? 1 : 0) << "\n"
        << "tzOverride=" << WideToUtf8(g_cfg.tzOverride) << "\n";
    WriteTextFile(ini, oss.str());
}

static void LoadConfig() {
    fs::path ini = GetProfileDir() / L"network.ini";
    std::ifstream ifs(ini);
    if (!ifs) return;
    std::string line;
    while (std::getline(ifs, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = line.substr(0, eq);
        std::string v = line.substr(eq + 1);
        if (k == "proxyType") g_cfg.proxyType = atoi(v.c_str());
        else if (k == "proxyHost") g_cfg.proxyHost = Utf8ToWide(v);
        else if (k == "proxyPort") g_cfg.proxyPort = Utf8ToWide(v);
        else if (k == "proxyUser") g_cfg.proxyUser = Utf8ToWide(v);
        else if (k == "proxyPass") g_cfg.proxyPass = Utf8ToWide(v);
        else if (k == "socksRemoteDns") g_cfg.socksRemoteDns = (v != "0");
        else if (k == "webrtcProtect") g_cfg.webrtcProtect = (v != "0");
        else if (k == "ovpnPath") g_cfg.ovpnPath = Utf8ToWide(v);
        else if (k == "wgPath") g_cfg.wgPath = Utf8ToWide(v);
        else if (k == "uaIndex") g_cfg.uaIndex = std::clamp(atoi(v.c_str()), 0, kUaPresetCount - 1);
        else if (k == "customUa") g_cfg.customUa = Utf8ToWide(v);
        else if (k == "uaPlatform") g_cfg.uaPlatform = Utf8ToWide(v);
        else if (k == "autoTimezone") g_cfg.autoTimezone = (v != "0");
        else if (k == "tzOverride") g_cfg.tzOverride = Utf8ToWide(v);
    }
}

static void ReadUiToConfig() {
    g_cfg.proxyType = std::clamp((int)SendMessageW(g_cbProxyType, CB_GETCURSEL, 0, 0), 0, 3);
    g_cfg.proxyHost = GetEditText(g_edHost);
    g_cfg.proxyPort = GetEditText(g_edPort);
    g_cfg.proxyUser = GetEditText(g_edUser);
    g_cfg.proxyPass = GetEditText(g_edPass);
    g_cfg.socksRemoteDns = (SendMessageW(g_chkRemoteDns, BM_GETCHECK, 0, 0) == BST_CHECKED);
    g_cfg.webrtcProtect = (SendMessageW(g_chkWebRtc, BM_GETCHECK, 0, 0) == BST_CHECKED);
    g_cfg.ovpnPath = GetEditText(g_edOvpn);
    g_cfg.wgPath = GetEditText(g_edWg);
    g_cfg.uaIndex = std::clamp((int)SendMessageW(g_cbUa, CB_GETCURSEL, 0, 0), 0, kUaPresetCount - 1);
    g_cfg.customUa = GetEditText(g_edUaCustom);
    g_cfg.uaPlatform = Utf8ToWide(kUaPresets[g_cfg.uaIndex].platform);
    g_cfg.autoTimezone = (SendMessageW(g_chkAutoTz, BM_GETCHECK, 0, 0) == BST_CHECKED);
    g_cfg.tzOverride = GetEditText(g_edTz);
}

// ------------------------------------------------ IP & Timezone Auto-Detection
static std::string ExtractJsonField(const std::string& json, const std::string& key) {
    std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return "";
    size_t colon = json.find(':', pos + needle.size());
    if (colon == std::string::npos) return "";
    size_t q1 = json.find('"', colon + 1);
    if (q1 == std::string::npos) return "";
    size_t q2 = json.find('"', q1 + 1);
    if (q2 == std::string::npos) return "";
    return json.substr(q1 + 1, q2 - q1 - 1);
}

static bool DetectIpTimezone(std::wstring& outTz, std::wstring& outIp, std::wstring& outLoc) {
    DWORD accessType = WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY;
    std::wstring proxyStr;
    if ((g_cfg.proxyType == 1 || g_cfg.proxyType == 2) && !g_cfg.proxyHost.empty() && !g_cfg.proxyPort.empty()) {
        accessType = WINHTTP_ACCESS_TYPE_NAMED_PROXY;
        proxyStr = g_cfg.proxyHost + L":" + g_cfg.proxyPort;
    }

    HINTERNET hSession = WinHttpOpen(L"MHBrowser/1.9", accessType,
        proxyStr.empty() ? WINHTTP_NO_PROXY_NAME : proxyStr.c_str(), WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) return false;
    WinHttpSetTimeouts(hSession, 4500, 4500, 5000, 5000);

    HINTERNET hConn = WinHttpConnect(hSession, L"ip-api.com", INTERNET_DEFAULT_HTTP_PORT, 0);
    bool ok = false;
    if (hConn) {
        HINTERNET hReq = WinHttpOpenRequest(hConn, L"GET",
            L"/json/?fields=status,query,country,city,timezone",
            nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
        if (hReq) {
            if (!proxyStr.empty() && !g_cfg.proxyUser.empty()) {
                WinHttpSetCredentials(hReq, WINHTTP_AUTH_TARGET_PROXY, WINHTTP_AUTH_SCHEME_BASIC,
                    g_cfg.proxyUser.c_str(), g_cfg.proxyPass.c_str(), nullptr);
            }
            if (WinHttpSendRequest(hReq, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
                WinHttpReceiveResponse(hReq, nullptr)) {
                std::string body;
                DWORD avail = 0;
                while (WinHttpQueryDataAvailable(hReq, &avail) && avail > 0 && body.size() < 16384) {
                    size_t old = body.size();
                    body.resize(old + avail);
                    DWORD read = 0;
                    if (!WinHttpReadData(hReq, body.data() + old, avail, &read) || read == 0) { body.resize(old); break; }
                    body.resize(old + read);
                }
                std::string tz = ExtractJsonField(body, "timezone");
                std::string ip = ExtractJsonField(body, "query");
                std::string country = ExtractJsonField(body, "country");
                std::string city = ExtractJsonField(body, "city");
                if (!tz.empty()) {
                    outTz = Utf8ToWide(tz);
                    outIp = Utf8ToWide(ip);
                    outLoc = Utf8ToWide(city.empty() ? country : (city + ", " + country));
                    ok = true;
                }
            }
            WinHttpCloseHandle(hReq);
        }
        WinHttpCloseHandle(hConn);
    }
    WinHttpCloseHandle(hSession);
    return ok;
}

static std::wstring FindExecutable(const std::vector<std::wstring>& candidates, const wchar_t* regAppPath = nullptr) {
    for (const auto& c : candidates)
        if (GetFileAttributesW(c.c_str()) != INVALID_FILE_ATTRIBUTES) return c;
    if (regAppPath) {
        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, regAppPath, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            wchar_t buf[MAX_PATH] = {};
            DWORD sz = sizeof(buf);
            if (RegQueryValueExW(hKey, nullptr, nullptr, nullptr, (LPBYTE)buf, &sz) == ERROR_SUCCESS) {
                RegCloseKey(hKey);
                if (GetFileAttributesW(buf) != INVALID_FILE_ATTRIBUTES) return std::wstring(buf);
            } else RegCloseKey(hKey);
        }
    }
    return L"";
}

static std::wstring FindGeckoRuntime() {
    std::wstring exeDir = GetExeDir(), localApp = GetLocalAppDataDir();
    return FindExecutable({
        exeDir + L"\\gecko\\firefox.exe",
        L"C:\\Program Files\\Mozilla Firefox\\firefox.exe",
        L"C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe",
        localApp + L"\\Mozilla Firefox\\firefox.exe",
        L"C:\\Program Files\\Firefox Developer Edition\\firefox.exe",
        L"C:\\Program Files\\LibreWolf\\librewolf.exe",
        L"C:\\Program Files\\Waterfox\\waterfox.exe"
    }, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\firefox.exe");
}

static std::wstring FindOpenVpnExe() {
    std::wstring exeDir = GetExeDir();
    return FindExecutable({
        exeDir + L"\\vpn\\openvpn\\openvpn.exe",
        L"C:\\Program Files\\OpenVPN\\bin\\openvpn.exe",
        L"C:\\Program Files (x86)\\OpenVPN\\bin\\openvpn.exe"
    });
}

static std::wstring FindWireGuardExe() {
    std::wstring exeDir = GetExeDir();
    return FindExecutable({
        exeDir + L"\\vpn\\wireguard\\wireguard.exe",
        L"C:\\Program Files\\WireGuard\\wireguard.exe",
        L"C:\\Program Files (x86)\\WireGuard\\wireguard.exe"
    });
}

static std::wstring BrowseFile(const wchar_t* filter, const wchar_t* title) {
    wchar_t file[MAX_PATH] = {};
    OPENFILENAMEW ofn = {};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_hwnd;
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = title;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    return GetOpenFileNameW(&ofn) ? std::wstring(file) : L"";
}

static bool RunElevated(const std::wstring& exe, const std::wstring& params, bool hidden = false, const std::wstring& workDir = L"") {
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb = L"runas";
    sei.lpFile = exe.c_str();
    sei.lpParameters = params.c_str();
    sei.lpDirectory = workDir.empty() ? nullptr : workDir.c_str();
    sei.nShow = hidden ? SW_HIDE : SW_SHOWNORMAL;
    if (!ShellExecuteExW(&sei)) return false;
    if (sei.hProcess) CloseHandle(sei.hProcess);
    return true;
}

static void ConnectOpenVpn() {
    ReadUiToConfig(); SaveConfig();
    if (g_cfg.ovpnPath.empty() || GetFileAttributesW(g_cfg.ovpnPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        SetStatus(L"Select a valid .ovpn config file first."); return;
    }
    std::wstring ovpnExe = FindOpenVpnExe();
    if (ovpnExe.empty()) {
        int r = MessageBoxW(g_hwnd, L"OpenVPN binary not found.\nOpen official OpenVPN download page?", L"OpenVPN", MB_YESNO | MB_ICONINFORMATION);
        if (r == IDYES) ShellExecuteW(nullptr, L"open", L"https://openvpn.net/community-downloads/", nullptr, nullptr, SW_SHOWNORMAL);
        return;
    }
    fs::path vpnDir = GetVpnDir(); std::error_code ec; fs::create_directories(vpnDir, ec);
    fs::path dst = vpnDir / L"active.ovpn";
    fs::copy_file(g_cfg.ovpnPath, dst, fs::copy_options::overwrite_existing, ec);
    std::wstring ovpnDir = fs::path(ovpnExe).parent_path().wstring();
    std::wstring params = L"--windows-driver wintun --config \"" + dst.wstring() + L"\"";
    if (RunElevated(ovpnExe, params, false, ovpnDir))
        SetStatus(L"OpenVPN connecting (Wintun): " + fs::path(g_cfg.ovpnPath).filename().wstring());
    else SetStatus(L"OpenVPN launch cancelled or failed.");
}

static void DisconnectOpenVpn() {
    if (RunElevated(L"taskkill.exe", L"/F /IM openvpn.exe", true)) SetStatus(L"OpenVPN disconnected.");
    else SetStatus(L"Could not stop OpenVPN.");
}

static void ConnectWireGuard() {
    ReadUiToConfig(); SaveConfig();
    if (g_cfg.wgPath.empty() || GetFileAttributesW(g_cfg.wgPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        SetStatus(L"Select a valid WireGuard .conf file first."); return;
    }
    std::wstring wgExe = FindWireGuardExe();
    if (wgExe.empty()) {
        int r = MessageBoxW(g_hwnd, L"WireGuard binary not found.\nOpen official WireGuard download page?", L"WireGuard", MB_YESNO | MB_ICONINFORMATION);
        if (r == IDYES) ShellExecuteW(nullptr, L"open", L"https://www.wireguard.com/install/", nullptr, nullptr, SW_SHOWNORMAL);
        return;
    }
    fs::path vpnDir = GetVpnDir(); std::error_code ec; fs::create_directories(vpnDir, ec);
    fs::path dst = vpnDir / L"mhbrowser_wg.conf";
    fs::copy_file(g_cfg.wgPath, dst, fs::copy_options::overwrite_existing, ec);
    std::wstring wgDir = fs::path(wgExe).parent_path().wstring();
    std::wstring params = L"/installtunnelservice \"" + dst.wstring() + L"\"";
    if (RunElevated(wgExe, params, true, wgDir))
        SetStatus(L"WireGuard tunnel activated: " + fs::path(g_cfg.wgPath).filename().wstring());
    else SetStatus(L"WireGuard activation cancelled or failed.");
}

static void DisconnectWireGuard() {
    std::wstring wgExe = FindWireGuardExe();
    if (wgExe.empty()) { SetStatus(L"WireGuard not found."); return; }
    if (RunElevated(wgExe, L"/uninstalltunnelservice mhbrowser_wg", true)) SetStatus(L"WireGuard tunnel disconnected.");
    else SetStatus(L"Could not disconnect WireGuard tunnel.");
}

static std::string BuildProxyBadgeText() {
    if (g_cfg.proxyType == 0 || g_cfg.proxyHost.empty()) return "Direct / VPN";
    std::string mode = (g_cfg.proxyType == 1) ? "HTTP" : (g_cfg.proxyType == 2 ? "HTTPS" : "SOCKS5");
    return mode + ": " + WideToUtf8(g_cfg.proxyHost) + ":" + WideToUtf8(g_cfg.proxyPort);
}

static std::string BuildHomeHtml(const std::wstring& activeTz) {
    std::string netBadge = BuildProxyBadgeText();
    std::string tzBadge = activeTz.empty() ? "System Timezone" : ("TZ: " + WideToUtf8(activeTz));
    return R"HTML(<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>MH Browser</title>
<style>
  :root { --bg:#111; --surface:#171717; --panel:#1f1f1f; --border:#333; --text:#f2f2f2; --muted:#9a9a9a; --accent:#e6b800; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--text); font-family:"Segoe UI",system-ui,sans-serif; min-height:100vh; display:flex; flex-direction:column; align-items:center; padding:34px 20px; }
  .brand { display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin-bottom:8px; }
  .badge { background:#383010; color:var(--accent); border:1px solid var(--accent); font-size:11px; font-weight:600; padding:2px 9px; border-radius:99px; }
  h1 { font-size:28px; font-weight:600; }
  .meta-box { width:100%; max-width:820px; background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:12px 16px; margin-bottom:20px; font-size:12px; color:var(--muted); line-height:1.6; }
  .meta-box b { color:var(--text); }
  .search-box { width:100%; max-width:640px; display:flex; gap:8px; margin-bottom:22px; }
  .search-box input { flex:1; background:var(--panel); color:var(--text); border:1px solid var(--border); border-radius:8px; padding:12px 16px; font-size:14px; outline:none; }
  .search-box input:focus { border-color:var(--accent); }
  .search-box button, .btn { background:var(--accent); color:#111; border:none; border-radius:8px; padding:10px 18px; font-weight:600; font-size:13px; cursor:pointer; }
  .btn-dark { background:var(--panel); color:var(--text); border:1px solid var(--border); }
  .grid { width:100%; max-width:820px; display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin-bottom:22px; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:14px; text-decoration:none; color:var(--text); }
  .card:hover { border-color:var(--accent); }
  .card b { display:block; font-size:14px; margin-bottom:4px; }
  .card span { color:var(--muted); font-size:11.5px; }
  .cam-panel { width:100%; max-width:820px; background:var(--surface); border:1px solid var(--border); border-radius:12px; padding:18px; }
  .cam-head { display:flex; flex-wrap:wrap; gap:10px; align-items:center; justify-content:space-between; margin-bottom:12px; }
  select { background:var(--panel); color:var(--text); border:1px solid var(--border); border-radius:6px; padding:7px 10px; font-size:12.5px; }
  video { width:100%; max-height:360px; background:#000; border-radius:8px; border:1px solid var(--border); display:block; }
  .status { color:var(--muted); font-size:12px; margin-top:8px; }
</style>
</head>
<body>
  <div class="brand">
    <h1>MH Browser</h1>
    <span class="badge">Gecko + WebRTC</span>
    <span class="badge">)HTML" + netBadge + R"HTML(</span>
    <span class="badge">)HTML" + tzBadge + R"HTML(</span>
  </div>

  <div class="meta-box">
    <div><b>Active User-Agent:</b> <span id="uaOut"></span></div>
    <div><b>Browser Timezone:</b> <span id="tzOut"></span> &nbsp;|&nbsp; <b>Local Time:</b> <span id="timeOut"></span></div>
  </div>

  <form class="search-box" id="searchForm">
    <input id="q" type="text" placeholder="Search the web or enter URL..." autofocus/>
    <button type="submit">Go</button>
  </form>

  <div class="grid">
    <a class="card" href="https://whoer.net"><b>Whoer / IP &amp; TZ</b><span>Verify IP, UA &amp; Timezone</span></a>
    <a class="card" href="https://ipleak.net"><b>IP &amp; WebRTC Leak</b><span>Check Proxy / VPN</span></a>
    <a class="card" href="https://meet.google.com"><b>Google Meet</b><span>WebRTC Video Calls</span></a>
    <a class="card" href="https://www.youtube.com"><b>YouTube</b><span>Full HTML5 &amp; JS</span></a>
    <a class="card" href="https://webcamtests.com"><b>Webcam Test</b><span>Verify HD USB Webcam</span></a>
  </div>

  <div class="cam-panel">
    <div class="cam-head">
      <div><strong>Live WebRTC Camera Tester</strong></div>
      <div style="display:flex;gap:8px;align-items:center;">
        <select id="camSelect"><option value="">Click "Start Camera Test"</option></select>
        <button class="btn" id="btnStart">Start Camera Test</button>
        <button class="btn btn-dark" id="btnStop">Stop</button>
      </div>
    </div>
    <video id="preview" autoplay playsinline muted></video>
    <div class="status" id="camStatus">Ready. Start MH Virtualcam first, then click "Start Camera Test".</div>
  </div>
<script>
  document.getElementById('uaOut').textContent = navigator.userAgent;
  document.getElementById('tzOut').textContent = Intl.DateTimeFormat().resolvedOptions().timeZone;
  document.getElementById('timeOut').textContent = new Date().toLocaleString();
  document.getElementById('searchForm').addEventListener('submit', e => {
    e.preventDefault();
    const v = document.getElementById('q').value.trim();
    if (!v) return;
    if (/^https?:\/\//i.test(v)) location.href = v;
    else if (!v.includes(' ') && v.includes('.')) location.href = 'https://' + v;
    else location.href = 'https://duckduckgo.com/?q=' + encodeURIComponent(v);
  });
  let stream = null;
  const video = document.getElementById('preview'), sel = document.getElementById('camSelect'), st = document.getElementById('camStatus');
  async function refreshDevices() {
    const devs = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === 'videoinput');
    const prev = sel.value; sel.innerHTML = '';
    devs.forEach((c, i) => {
      const opt = document.createElement('option'); opt.value = c.deviceId; opt.textContent = c.label || ('Camera ' + (i + 1));
      if (opt.textContent.includes('HD USB Webcam') && !prev) opt.selected = true;
      sel.appendChild(opt);
    });
    if (prev) sel.value = prev;
  }
  async function startCam(deviceId) {
    stopCam();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: deviceId ? { deviceId: { exact: deviceId } } : true, audio: false });
      video.srcObject = stream; await refreshDevices();
      const tr = stream.getVideoTracks()[0], s = tr.getSettings();
      st.textContent = 'LIVE: ' + tr.label + ' (' + (s.width || '?') + 'x' + (s.height || '?') + ')';
    } catch (err) { st.textContent = 'Camera error: ' + err.message; }
  }
  function stopCam() { if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; } video.srcObject = null; st.textContent = 'Camera stopped.'; }
  document.getElementById('btnStart').onclick = () => startCam(sel.value);
  document.getElementById('btnStop').onclick = stopCam;
  sel.onchange = () => { if (stream) startCam(sel.value); };
</script>
</body>
</html>)HTML";
}

static std::string BuildUserChromeCss() {
    return R"CSS(:root {
  --toolbar-bgcolor: #171717 !important; --toolbar-color: #f2f2f2 !important;
  --lwt-accent-color: #111111 !important; --lwt-text-color: #f2f2f2 !important;
  --toolbar-field-background-color: #242424 !important; --toolbar-field-color: #f2f2f2 !important;
  --toolbar-field-border-color: #333333 !important; --toolbar-field-focus-border-color: #e6b800 !important;
  --tab-selected-bgcolor: #1f1f1f !important; --arrowpanel-background: #1a1a1a !important;
  --arrowpanel-color: #f2f2f2 !important; --arrowpanel-border-color: #333333 !important;
}
#navigator-toolbox { background-color: #111111 !important; border-bottom: 1px solid #333333 !important; }
.tabbrowser-tab[selected="true"] .tab-background { background: #1f1f1f !important; border-top: 2px solid #e6b800 !important; box-shadow: none !important; }
#urlbar-background { background-color: #242424 !important; border: 1px solid #333333 !important; border-radius: 6px !important; }
#urlbar[focused="true"] > #urlbar-background { border-color: #e6b800 !important; }
menupopup { --panel-background: #1a1a1a !important; --panel-color: #f2f2f2 !important; --panel-border-color: #333333 !important; }
)CSS";
}

static std::string PathToFileUrl(const fs::path& p) {
    std::string s = p.u8string();
    for (char& c : s) if (c == '\\') c = '/';
    std::string out = "file:///";
    for (unsigned char c : s) { if (c == ' ') out += "%20"; else out.push_back((char)c); }
    return out;
}

static std::string BuildUserJs(const std::string& homeFileUrl) {
    std::ostringstream js;
    js << "// MH Browser Gecko + Proxy + User-Agent Configuration\n"
       << "user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);\n"
       << "user_pref(\"browser.startup.homepage\", \"" << EscapeJs(homeFileUrl) << "\");\n"
       << "user_pref(\"browser.startup.page\", 1);\n"
       << "user_pref(\"browser.newtabpage.enabled\", false);\n"
       << "user_pref(\"browser.shell.checkDefaultBrowser\", false);\n"
       << "user_pref(\"datareporting.policy.dataSubmissionEnabled\", false);\n"
       << "user_pref(\"toolkit.telemetry.enabled\", false);\n"
       << "user_pref(\"ui.systemUsesDarkTheme\", 1);\n"
       << "user_pref(\"layout.css.prefers-color-scheme.content-override\", 0);\n"
       << "user_pref(\"media.peerconnection.enabled\", true);\n"
       << "user_pref(\"media.navigator.enabled\", true);\n"
       << "user_pref(\"media.navigator.video.enabled\", true);\n"
       << "user_pref(\"browser.tabs.inTitlebar\", 1);\n"
       << "user_pref(\"browser.toolbars.bookmarks.visibility\", \"always\");\n";

    // Proxy prefs
    std::string host = EscapeJs(WideToUtf8(g_cfg.proxyHost));
    int port = _wtoi(g_cfg.proxyPort.c_str());
    if (g_cfg.proxyType == 0 || host.empty() || port <= 0) {
        js << "user_pref(\"network.proxy.type\", 0);\n";
    } else {
        js << "user_pref(\"network.proxy.type\", 1);\n"
           << "user_pref(\"network.proxy.share_proxy_settings\", false);\n"
           << "user_pref(\"network.proxy.http\", \"\");\n"
           << "user_pref(\"network.proxy.http_port\", 0);\n"
           << "user_pref(\"network.proxy.ssl\", \"\");\n"
           << "user_pref(\"network.proxy.ssl_port\", 0);\n"
           << "user_pref(\"network.proxy.socks\", \"\");\n"
           << "user_pref(\"network.proxy.socks_port\", 0);\n";
        if (g_cfg.proxyType == 1 || g_cfg.proxyType == 2) {
            js << "user_pref(\"network.proxy.http\", \"" << host << "\");\n"
               << "user_pref(\"network.proxy.http_port\", " << port << ");\n"
               << "user_pref(\"network.proxy.ssl\", \"" << host << "\");\n"
               << "user_pref(\"network.proxy.ssl_port\", " << port << ");\n";
        } else if (g_cfg.proxyType == 3) {
            js << "user_pref(\"network.proxy.socks\", \"" << host << "\");\n"
               << "user_pref(\"network.proxy.socks_port\", " << port << ");\n"
               << "user_pref(\"network.proxy.socks_version\", 5);\n"
               << "user_pref(\"network.proxy.socks_remote_dns\", " << (g_cfg.socksRemoteDns ? "true" : "false") << ");\n";
        }
        js << "user_pref(\"signon.autologin.proxy\", true);\n";
    }

    // WebRTC IP leak protection
    js << "user_pref(\"media.peerconnection.ice.default_address_only\", " << (g_cfg.webrtcProtect ? "true" : "false") << ");\n"
       << "user_pref(\"media.peerconnection.ice.proxy_only_if_behind_proxy\", " << (g_cfg.webrtcProtect ? "true" : "false") << ");\n";

    // User-Agent & Platform override
    std::string ua = WideToUtf8(g_cfg.customUa);
    if (ua.empty() && g_cfg.uaIndex > 0 && g_cfg.uaIndex < kUaPresetCount)
        ua = kUaPresets[g_cfg.uaIndex].ua;

    if (!ua.empty()) {
        js << "user_pref(\"general.useragent.override\", \"" << EscapeJs(ua) << "\");\n";
        std::string plat = WideToUtf8(g_cfg.uaPlatform);
        if (!plat.empty())
            js << "user_pref(\"general.platform.override\", \"" << EscapeJs(plat) << "\");\n";
    } else {
        js << "user_pref(\"general.useragent.override\", \"\");\n"
           << "user_pref(\"general.platform.override\", \"\");\n";
    }
    return js.str();
}

static void LaunchGeckoBrowser(const std::wstring& extraUrl = L"") {
    std::wstring geckoExe = FindGeckoRuntime();
    if (geckoExe.empty()) {
        int res = MessageBoxW(g_hwnd,
            L"MH Browser uses Mozilla's Gecko engine (Firefox) for full JavaScript & WebRTC support.\n\n"
            L"Firefox/Gecko runtime was not found on this PC.\n"
            L"Would you like to open the official Mozilla Firefox download page?",
            L"MH Browser - Gecko Engine Required", MB_YESNO | MB_ICONINFORMATION);
        if (res == IDYES)
            ShellExecuteW(nullptr, L"open", L"https://www.mozilla.org/firefox/new/", nullptr, nullptr, SW_SHOWNORMAL);
        return;
    }

    std::wstring activeTz = g_cfg.tzOverride;
    if (g_cfg.autoTimezone) {
        SetStatus(L"Detecting IP & Timezone from active VPN / Proxy...");
        std::wstring tz, ip, loc;
        if (DetectIpTimezone(tz, ip, loc)) {
            activeTz = tz;
            g_detectedIp = ip;
            g_detectedLocation = loc;
            if (g_edTz) SetWindowTextW(g_edTz, tz.c_str());
        }
    }

    fs::path profileDir = GetProfileDir();
    fs::path homePath = profileDir / L"home.html";
    WriteTextFile(homePath, BuildHomeHtml(activeTz));
    WriteTextFile(profileDir / L"chrome" / L"userChrome.css", BuildUserChromeCss());
    WriteTextFile(profileDir / L"user.js", BuildUserJs(PathToFileUrl(homePath)));

    // Set TZ environment variable so Gecko adopts the VPN/Proxy timezone natively without altering Windows clock!
    if (!activeTz.empty()) SetEnvironmentVariableW(L"TZ", activeTz.c_str());
    else SetEnvironmentVariableW(L"TZ", nullptr);

    std::wstring startUrl = !extraUrl.empty() ? extraUrl : (L"\"" + homePath.wstring() + L"\"");
    std::wstring cmdLine = L"\"" + geckoExe + L"\" --no-remote --new-instance --profile \"" + profileDir.wstring() + L"\" " + startUrl;

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {};
    if (CreateProcessW(geckoExe.c_str(), cmdLine.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi)) {
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        std::wstring msg = L"Launched MH Browser | " + Utf8ToWide(BuildProxyBadgeText());
        if (!activeTz.empty()) msg += L" | TZ: " + activeTz;
        SetStatus(msg);
    } else {
        SetStatus(L"Failed to launch Gecko runtime (error " + std::to_wstring(GetLastError()) + L").");
    }
}

static HWND MakeLabel(HWND parent, const wchar_t* text, int x, int y, int w, int h, HFONT f) {
    HWND hw = CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE, x, y, w, h, parent, nullptr, nullptr, nullptr);
    SendMessageW(hw, WM_SETFONT, (WPARAM)f, TRUE);
    return hw;
}

static HWND MakeEdit(HWND parent, int id, const wchar_t* text, int x, int y, int w, int h, bool pwd = false) {
    DWORD st = WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | WS_BORDER | (pwd ? ES_PASSWORD : 0);
    HWND hw = CreateWindowExW(0, L"EDIT", text, st, x, y, w, h, parent, (HMENU)(INT_PTR)id, nullptr, nullptr);
    SendMessageW(hw, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
    return hw;
}

static HWND MakeBtn(HWND parent, int id, const wchar_t* text, int x, int y, int w, int h, bool bold = false) {
    HWND hw = CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, x, y, w, h, parent, (HMENU)(INT_PTR)id, nullptr, nullptr);
    SendMessageW(hw, WM_SETFONT, (WPARAM)(bold ? g_fontBold : g_fontUi), TRUE);
    return hw;
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        g_hwnd = hwnd;
        int dark = 1;
        if (DwmSetWindowAttribute(hwnd, 20, &dark, sizeof(int)) != 0)
            DwmSetWindowAttribute(hwnd, 19, &dark, sizeof(int));
        int cap = 0x00171717; DwmSetWindowAttribute(hwnd, 35, &cap, sizeof(int));
        int txt = 0x00F2F2F2; DwmSetWindowAttribute(hwnd, 36, &txt, sizeof(int));

        g_fontUi = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
        g_fontBold = CreateFontW(-14, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
        g_fontTitle = CreateFontW(-19, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
        g_brBg = CreateSolidBrush(RGB(17, 17, 17));
        g_brSurface = CreateSolidBrush(RGB(23, 23, 23));
        g_brEdit = CreateSolidBrush(RGB(38, 38, 38));

        LoadConfig();

        MakeLabel(hwnd, L"MH Browser  -  Network, VPN, User-Agent & Timezone", 20, 12, 580, 26, g_fontTitle);

        // --- PROXY SECTION ---
        MakeLabel(hwnd, L"PROXY SETTINGS (HTTP / HTTPS / SOCKS5)", 20, 48, 400, 18, g_fontBold);
        MakeLabel(hwnd, L"Type:", 20, 76, 46, 20, g_fontUi);
        g_cbProxyType = CreateWindowExW(0, L"COMBOBOX", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST, 70, 72, 175, 160, hwnd, (HMENU)IDC_PROXY_TYPE, nullptr, nullptr);
        SendMessageW(g_cbProxyType, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
        SendMessageW(g_cbProxyType, CB_ADDSTRING, 0, (LPARAM)L"Direct (No Proxy)");
        SendMessageW(g_cbProxyType, CB_ADDSTRING, 0, (LPARAM)L"HTTP Proxy");
        SendMessageW(g_cbProxyType, CB_ADDSTRING, 0, (LPARAM)L"HTTPS Proxy");
        SendMessageW(g_cbProxyType, CB_ADDSTRING, 0, (LPARAM)L"SOCKS5 Proxy");
        SendMessageW(g_cbProxyType, CB_SETCURSEL, g_cfg.proxyType, 0);

        MakeLabel(hwnd, L"Host:", 256, 76, 42, 20, g_fontUi);
        g_edHost = MakeEdit(hwnd, IDC_PROXY_HOST, g_cfg.proxyHost.c_str(), 300, 72, 185, 24);
        MakeLabel(hwnd, L"Port:", 495, 76, 36, 20, g_fontUi);
        g_edPort = MakeEdit(hwnd, IDC_PROXY_PORT, g_cfg.proxyPort.c_str(), 533, 72, 72, 24);

        MakeLabel(hwnd, L"User:", 20, 108, 46, 20, g_fontUi);
        g_edUser = MakeEdit(hwnd, IDC_PROXY_USER, g_cfg.proxyUser.c_str(), 70, 104, 175, 24);
        MakeLabel(hwnd, L"Pass:", 256, 108, 42, 20, g_fontUi);
        g_edPass = MakeEdit(hwnd, IDC_PROXY_PASS, g_cfg.proxyPass.c_str(), 300, 104, 185, 24, true);

        g_chkRemoteDns = CreateWindowExW(0, L"BUTTON", L"Proxy DNS over SOCKS5", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 20, 136, 210, 22, hwnd, (HMENU)IDC_CHK_REMOTE_DNS, nullptr, nullptr);
        SendMessageW(g_chkRemoteDns, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
        SendMessageW(g_chkRemoteDns, BM_SETCHECK, g_cfg.socksRemoteDns ? BST_CHECKED : BST_UNCHECKED, 0);

        g_chkWebRtc = CreateWindowExW(0, L"BUTTON", L"WebRTC IP Leak Protection", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 256, 136, 240, 22, hwnd, (HMENU)IDC_CHK_WEBRTC_PROTECT, nullptr, nullptr);
        SendMessageW(g_chkWebRtc, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
        SendMessageW(g_chkWebRtc, BM_SETCHECK, g_cfg.webrtcProtect ? BST_CHECKED : BST_UNCHECKED, 0);

        // --- OPENVPN & WIREGUARD ---
        MakeLabel(hwnd, L"OPENVPN (.ovpn)  &  WIREGUARD (.conf)  -  BUILT-IN PORTABLE", 20, 170, 560, 18, g_fontBold);
        MakeLabel(hwnd, L"OVPN:", 20, 198, 46, 20, g_fontUi);
        g_edOvpn = MakeEdit(hwnd, IDC_OVPN_PATH, g_cfg.ovpnPath.c_str(), 70, 194, 300, 24);
        MakeBtn(hwnd, IDC_BTN_OVPN_BROWSE, L"Browse", 376, 193, 68, 26);
        MakeBtn(hwnd, IDC_BTN_OVPN_CONNECT, L"Connect", 450, 193, 76, 26, true);
        MakeBtn(hwnd, IDC_BTN_OVPN_DISCONNECT, L"Stop", 532, 193, 73, 26);

        MakeLabel(hwnd, L"WG:", 20, 232, 46, 20, g_fontUi);
        g_edWg = MakeEdit(hwnd, IDC_WG_PATH, g_cfg.wgPath.c_str(), 70, 228, 300, 24);
        MakeBtn(hwnd, IDC_BTN_WG_BROWSE, L"Browse", 376, 227, 68, 26);
        MakeBtn(hwnd, IDC_BTN_WG_CONNECT, L"Connect", 450, 227, 76, 26, true);
        MakeBtn(hwnd, IDC_BTN_WG_DISCONNECT, L"Stop", 532, 227, 73, 26);

        // --- USER-AGENT SWITCHER ---
        MakeLabel(hwnd, L"USER-AGENT SWITCHER (PC / MOBILE / SMART TV / CONSOLE)", 20, 268, 560, 18, g_fontBold);
        MakeLabel(hwnd, L"Device:", 20, 296, 52, 20, g_fontUi);
        g_cbUa = CreateWindowExW(0, L"COMBOBOX", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL, 76, 292, 529, 260, hwnd, (HMENU)IDC_UA_PRESET, nullptr, nullptr);
        SendMessageW(g_cbUa, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
        for (int i = 0; i < kUaPresetCount; ++i)
            SendMessageW(g_cbUa, CB_ADDSTRING, 0, (LPARAM)kUaPresets[i].label);
        SendMessageW(g_cbUa, CB_SETCURSEL, g_cfg.uaIndex, 0);

        MakeLabel(hwnd, L"Custom:", 20, 328, 52, 20, g_fontUi);
        std::wstring initialUa = !g_cfg.customUa.empty() ? g_cfg.customUa : Utf8ToWide(kUaPresets[g_cfg.uaIndex].ua);
        g_edUaCustom = MakeEdit(hwnd, IDC_UA_CUSTOM, initialUa.c_str(), 76, 324, 529, 24);

        // --- AUTO TIMEZONE FROM IP ---
        MakeLabel(hwnd, L"AUTO TIMEZONE SYNC (MATCH VPN / PROXY IP)", 20, 364, 560, 18, g_fontBold);
        g_chkAutoTz = CreateWindowExW(0, L"BUTTON", L"Auto-detect Timezone from VPN / Proxy IP on launch", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 20, 388, 365, 22, hwnd, (HMENU)IDC_CHK_AUTO_TZ, nullptr, nullptr);
        SendMessageW(g_chkAutoTz, WM_SETFONT, (WPARAM)g_fontUi, TRUE);
        SendMessageW(g_chkAutoTz, BM_SETCHECK, g_cfg.autoTimezone ? BST_CHECKED : BST_UNCHECKED, 0);

        MakeLabel(hwnd, L"TZ:", 20, 420, 30, 20, g_fontUi);
        g_edTz = MakeEdit(hwnd, IDC_TZ_OVERRIDE, g_cfg.tzOverride.c_str(), 54, 416, 360, 24);
        MakeBtn(hwnd, IDC_BTN_CHECK_IP_TZ, L"Detect IP & Timezone", 424, 415, 181, 26);

        // --- LAUNCH ROW ---
        MakeBtn(hwnd, IDC_BTN_LAUNCH, L"Launch MH Browser (Gecko)", 20, 458, 250, 36, true);
        MakeBtn(hwnd, IDC_BTN_SAVE_ONLY, L"Save All Settings", 282, 458, 160, 36);

        g_lblStatus = MakeLabel(hwnd, L"Ready. Pick Proxy/VPN, User-Agent & Auto Timezone, then click Launch MH Browser.", 20, 506, 585, 22, g_fontUi);
        return 0;
    }

    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        HDC hdc = (HDC)wp;
        SetTextColor(hdc, RGB(242, 242, 242));
        SetBkColor(hdc, RGB(17, 17, 17));
        return (LRESULT)g_brBg;
    }

    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
        HDC hdc = (HDC)wp;
        SetTextColor(hdc, RGB(242, 242, 242));
        SetBkColor(hdc, RGB(38, 38, 38));
        return (LRESULT)g_brEdit;
    }

    case WM_COMMAND:
        if (LOWORD(wp) == IDC_UA_PRESET && HIWORD(wp) == CBN_SELCHANGE) {
            int idx = std::clamp((int)SendMessageW(g_cbUa, CB_GETCURSEL, 0, 0), 0, kUaPresetCount - 1);
            SetWindowTextW(g_edUaCustom, Utf8ToWide(kUaPresets[idx].ua).c_str());
            SetStatus(L"User-Agent selected: " + std::wstring(kUaPresets[idx].label));
            return 0;
        }
        switch (LOWORD(wp)) {
        case IDC_BTN_OVPN_BROWSE: {
            std::wstring p = BrowseFile(L"OpenVPN Config (*.ovpn)\0*.ovpn\0All Files (*.*)\0*.*\0", L"Select OpenVPN (.ovpn) File");
            if (!p.empty()) SetWindowTextW(g_edOvpn, p.c_str());
            return 0;
        }
        case IDC_BTN_OVPN_CONNECT: ConnectOpenVpn(); return 0;
        case IDC_BTN_OVPN_DISCONNECT: DisconnectOpenVpn(); return 0;

        case IDC_BTN_WG_BROWSE: {
            std::wstring p = BrowseFile(L"WireGuard Config (*.conf)\0*.conf\0All Files (*.*)\0*.*\0", L"Select WireGuard (.conf) File");
            if (!p.empty()) SetWindowTextW(g_edWg, p.c_str());
            return 0;
        }
        case IDC_BTN_WG_CONNECT: ConnectWireGuard(); return 0;
        case IDC_BTN_WG_DISCONNECT: DisconnectWireGuard(); return 0;

        case IDC_BTN_CHECK_IP_TZ: {
            ReadUiToConfig();
            SetStatus(L"Checking IP & Timezone...");
            std::wstring tz, ip, loc;
            if (DetectIpTimezone(tz, ip, loc)) {
                g_cfg.tzOverride = tz;
                SetWindowTextW(g_edTz, tz.c_str());
                SetStatus(L"Detected: " + ip + L" (" + loc + L") -> TZ: " + tz);
            } else {
                SetStatus(L"Could not detect IP/Timezone (check internet or proxy).");
            }
            return 0;
        }

        case IDC_BTN_SAVE_ONLY:
            ReadUiToConfig();
            SaveConfig();
            SetStatus(L"Saved all Proxy, User-Agent & Timezone settings.");
            return 0;

        case IDC_BTN_LAUNCH:
            ReadUiToConfig();
            SaveConfig();
            LaunchGeckoBrowser();
            return 0;
        }
        break;

    case WM_DESTROY:
        if (g_fontUi) DeleteObject(g_fontUi);
        if (g_fontBold) DeleteObject(g_fontBold);
        if (g_fontTitle) DeleteObject(g_fontTitle);
        if (g_brBg) DeleteObject(g_brBg);
        if (g_brSurface) DeleteObject(g_brSurface);
        if (g_brEdit) DeleteObject(g_brEdit);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR lpCmdLine, int nCmdShow) {
    if (lpCmdLine && wcslen(lpCmdLine) > 0) {
        LoadConfig();
        std::wstring arg = lpCmdLine;
        LaunchGeckoBrowser(arg == L"--direct" ? L"" : arg);
        return 0;
    }

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hIcon = LoadIconW(hInst, MAKEINTRESOURCEW(1));
    wc.hIconSm = LoadIconW(hInst, MAKEINTRESOURCEW(1));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(RGB(17, 17, 17));
    wc.lpszClassName = L"MHBrowserControlClass";
    RegisterClassExW(&wc);

    HWND hwnd = CreateWindowExW(
        0, L"MHBrowserControlClass", L"MH Browser - Network, VPN, User-Agent & Timezone",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 640, 578,
        nullptr, nullptr, hInst, nullptr);

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        if (!IsDialogMessageW(hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    return (int)msg.wParam;
}
