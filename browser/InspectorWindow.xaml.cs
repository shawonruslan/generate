using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace MHBrowser;

public sealed class CapturedNetRequest : INotifyPropertyChanged
{
    public string RequestId { get; set; } = "";
    public string Time { get; set; } = "";
    public string Method { get; set; } = "GET"; // GET, POST, WS SEND, WS RECV
    public string Url { get; set; } = "";
    public string ResourceType { get; set; } = "";
    public string GraphQlOp { get; set; } = "";
    public string Protocol { get; set; } = "";
    public string RemoteIp { get; set; } = "";
    public int StatusCode { get; set; }
    public string ErrorText { get; set; } = "";
    public long SizeBytes { get; set; }
    public long StartTickMs { get; set; }
    public long DurationMs { get; set; }
    public string RequestHeaders { get; set; } = "";
    public string PostData { get; set; } = "";
    public string ResponseHeaders { get; set; } = "";
    public string ResponseBody { get; set; } = "";

    public string StatusText => !string.IsNullOrEmpty(ErrorText) ? "FAIL" : (StatusCode > 0 ? StatusCode.ToString() : (Method.StartsWith("WS") ? "WS" : "..."));
    public string SizeText => SizeBytes <= 0 ? "-" : (SizeBytes < 1024 ? $"{SizeBytes} B" : $"{SizeBytes / 1024.0:F1} KB");
    public string DurationText => DurationMs > 0 ? $"{DurationMs} ms" : "-";
    public string DisplayEndpoint => string.IsNullOrEmpty(GraphQlOp) ? Url : $"[GQL: {GraphQlOp}] {Url}";

    public event PropertyChangedEventHandler? PropertyChanged;
    public void NotifyUpdate()
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(StatusText)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(StatusCode)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SizeText)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DurationText)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayEndpoint)));
    }
}

public sealed class RecordedUiAction
{
    public string Time { get; set; } = "";
    public string Action { get; set; } = ""; // CLICK, DBLCLICK, WRITE, SELECT, CHECK, SUBMIT, KEYPRESS
    public string Tag { get; set; } = "";
    public string Selector { get; set; } = "";
    public string XPath { get; set; } = "";
    public string FullXPath { get; set; } = "";
    public string ElementId { get; set; } = "";
    public string ElementName { get; set; } = "";
    public string AriaLabel { get; set; } = "";
    public string DataTestId { get; set; } = "";
    public string Bounds { get; set; } = "";
    public string Value { get; set; } = "";
    public string PageUrl { get; set; } = "";
}

public partial class InspectorWindow : Window
{
    private readonly ObservableCollection<CapturedNetRequest> _allNet;
    private readonly ObservableCollection<CapturedNetRequest> _filteredNet = new();
    private readonly ObservableCollection<RecordedUiAction> _uiActions;
    private readonly Func<string, Task<string>> _fetchBodyAsync;
    private string _activeFilter = "ALL";
    private bool _showingUi;

    public bool IsCapturing { get; set; } = true;

    public InspectorWindow(
        string profileName,
        ObservableCollection<CapturedNetRequest> netRequests,
        ObservableCollection<RecordedUiAction> uiActions,
        Func<string, Task<string>> fetchBodyAsync)
    {
        InitializeComponent();
        Title = $"MH Pro Inspector - {profileName}";
        HeaderTitle.Text = $"MH Pro Inspector ({profileName})";
        _allNet = netRequests;
        _uiActions = uiActions;
        _fetchBodyAsync = fetchBodyAsync;

        NetList.ItemsSource = _filteredNet;
        UiList.ItemsSource = _uiActions;

        _allNet.CollectionChanged += (_, _) => Dispatcher.BeginInvoke(RefreshNetFilter);
        _uiActions.CollectionChanged += (_, _) => Dispatcher.BeginInvoke(UpdateCounts);
        RefreshNetFilter();
        UpdateCounts();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        App.ApplyDarkTitleBar(this);
    }

    private void UpdateCounts()
    {
        InspectorStatus.Text = $"Captured {_allNet.Count} network/WS events | {_uiActions.Count} UI actions | Capture: {(IsCapturing ? "ON" : "PAUSED")}";
    }

    private void RefreshNetFilter()
    {
        string q = TxtNetFilter?.Text?.Trim() ?? "";
        _filteredNet.Clear();
        foreach (var r in _allNet)
        {
            bool typeOk = _activeFilter switch
            {
                "API" => r.ResourceType is "XHR" or "Fetch",
                "WS" => r.ResourceType == "WebSocket" || r.Method.StartsWith("WS"),
                "GQL" => !string.IsNullOrEmpty(r.GraphQlOp) || r.Url.Contains("graphql", StringComparison.OrdinalIgnoreCase),
                "POST" => r.Method is "POST" or "PUT" or "PATCH" or "DELETE",
                "ERR" => r.StatusCode >= 400 || !string.IsNullOrEmpty(r.ErrorText),
                _ => true
            };
            bool textOk = string.IsNullOrEmpty(q) ||
                          r.Url.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          r.Method.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          r.GraphQlOp.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          r.StatusText.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                          r.PostData.Contains(q, StringComparison.OrdinalIgnoreCase);
            if (typeOk && textOk) _filteredNet.Add(r);
        }
        UpdateCounts();
    }

    private void TxtNetFilter_TextChanged(object sender, TextChangedEventArgs e) => RefreshNetFilter();

    private void BtnFilter_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string f) return;
        _activeFilter = f;
        var accent = (Style)FindResource("AccentButton");
        var flat = (Style)FindResource("FlatButton");
        BtnFilterAll.Style = f == "ALL" ? accent : flat;
        BtnFilterApi.Style = f == "API" ? accent : flat;
        BtnFilterWs.Style = f == "WS" ? accent : flat;
        BtnFilterGql.Style = f == "GQL" ? accent : flat;
        BtnFilterPost.Style = f == "POST" ? accent : flat;
        BtnFilterErr.Style = f == "ERR" ? accent : flat;
        RefreshNetFilter();
    }

    private void BtnTabNetwork_Click(object sender, RoutedEventArgs e)
    {
        _showingUi = false;
        NetworkView.Visibility = Visibility.Visible;
        UiView.Visibility = Visibility.Collapsed;
        BtnExportHar.Visibility = Visibility.Visible;
        BtnExportPlaywright.Visibility = Visibility.Collapsed;
        BtnExportSelenium.Visibility = Visibility.Collapsed;
        BtnTabNetwork.Style = (Style)FindResource("AccentButton");
        BtnTabUi.Style = (Style)FindResource("FlatButton");
    }

    private void BtnTabUi_Click(object sender, RoutedEventArgs e)
    {
        _showingUi = true;
        NetworkView.Visibility = Visibility.Collapsed;
        UiView.Visibility = Visibility.Visible;
        BtnExportHar.Visibility = Visibility.Collapsed;
        BtnExportPlaywright.Visibility = Visibility.Visible;
        BtnExportSelenium.Visibility = Visibility.Visible;
        BtnTabNetwork.Style = (Style)FindResource("FlatButton");
        BtnTabUi.Style = (Style)FindResource("AccentButton");
    }

    private void BtnToggleCapture_Click(object sender, RoutedEventArgs e)
    {
        IsCapturing = !IsCapturing;
        BtnToggleCapture.Content = IsCapturing ? "Capturing: ON" : "Capturing: PAUSED";
        BtnToggleCapture.Style = (Style)FindResource(IsCapturing ? "GreenButton" : "FlatButton");
        UpdateCounts();
    }

    private async void NetList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NetList.SelectedItem is not CapturedNetRequest req) return;
        DetailHeader.Text = $"{req.Method} {req.StatusText}  {req.DisplayEndpoint}";

        if (string.IsNullOrEmpty(req.ResponseBody) && !string.IsNullOrEmpty(req.RequestId) && !req.Method.StartsWith("WS"))
        {
            TxtNetDetail.Text = "Loading response body...";
            req.ResponseBody = await _fetchBodyAsync(req.RequestId);
        }

        var sb = new StringBuilder();
        sb.AppendLine("=== OVERVIEW ===");
        sb.AppendLine($"{req.Method} {req.Url}");
        sb.AppendLine($"Status: {req.StatusText}   Type: {req.ResourceType}   Protocol: {req.Protocol}   Remote IP: {req.RemoteIp}");
        sb.AppendLine($"Size: {req.SizeText}   Duration: {req.DurationText}");
        if (!string.IsNullOrEmpty(req.GraphQlOp)) sb.AppendLine($"GraphQL Operation: {req.GraphQlOp}");
        if (!string.IsNullOrEmpty(req.ErrorText)) sb.AppendLine($"Error: {req.ErrorText}");

        if (!string.IsNullOrWhiteSpace(req.RequestHeaders))
        {
            sb.AppendLine("\n=== REQUEST HEADERS ===");
            sb.AppendLine(req.RequestHeaders);
        }
        if (!string.IsNullOrWhiteSpace(req.PostData))
        {
            sb.AppendLine("\n=== REQUEST PAYLOAD / WS FRAME ===");
            sb.AppendLine(req.PostData);
        }
        if (!string.IsNullOrWhiteSpace(req.ResponseHeaders))
        {
            sb.AppendLine("\n=== RESPONSE HEADERS ===");
            sb.AppendLine(req.ResponseHeaders);
        }
        if (!string.IsNullOrWhiteSpace(req.ResponseBody))
        {
            sb.AppendLine("\n=== RESPONSE BODY ===");
            sb.AppendLine(req.ResponseBody.Length > 35000 ? req.ResponseBody[..35000] + "\n... [truncated]" : req.ResponseBody);
        }
        TxtNetDetail.Text = sb.ToString();
    }

    private void UiList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UiList.SelectedItem is not RecordedUiAction a) return;
        UiDetailHeader.Text = $"{a.Action} on <{a.Tag}>";
        var sb = new StringBuilder();
        sb.AppendLine($"Action:       {a.Action}");
        sb.AppendLine($"Time:         {a.Time}");
        sb.AppendLine($"Tag:          <{a.Tag}>");
        sb.AppendLine($"CSS Selector: {a.Selector}");
        sb.AppendLine($"Smart XPath:  {a.XPath}");
        sb.AppendLine($"Full XPath:   {a.FullXPath}");
        if (!string.IsNullOrEmpty(a.ElementId)) sb.AppendLine($"id:           {a.ElementId}");
        if (!string.IsNullOrEmpty(a.ElementName)) sb.AppendLine($"name:         {a.ElementName}");
        if (!string.IsNullOrEmpty(a.DataTestId)) sb.AppendLine($"data-testid:  {a.DataTestId}");
        if (!string.IsNullOrEmpty(a.AriaLabel)) sb.AppendLine($"aria-label:   {a.AriaLabel}");
        if (!string.IsNullOrEmpty(a.Bounds)) sb.AppendLine($"BoundingBox:  {a.Bounds}");
        sb.AppendLine($"Value / Text: {a.Value}");
        sb.AppendLine($"Page URL:     {a.PageUrl}");
        TxtUiDetail.Text = sb.ToString();
    }

    private void BtnCopyUiCss_Click(object sender, RoutedEventArgs e)
    {
        if (UiList.SelectedItem is RecordedUiAction a && !string.IsNullOrEmpty(a.Selector))
        { try { Clipboard.SetText(a.Selector); InspectorStatus.Text = "Copied CSS Selector."; } catch { } }
    }

    private void BtnCopyUiXPath_Click(object sender, RoutedEventArgs e)
    {
        if (UiList.SelectedItem is RecordedUiAction a && !string.IsNullOrEmpty(a.XPath))
        { try { Clipboard.SetText(a.XPath); InspectorStatus.Text = "Copied Smart XPath."; } catch { } }
    }

    private void BtnCopyUiFullXPath_Click(object sender, RoutedEventArgs e)
    {
        if (UiList.SelectedItem is RecordedUiAction a && !string.IsNullOrEmpty(a.FullXPath))
        { try { Clipboard.SetText(a.FullXPath); InspectorStatus.Text = "Copied Full XPath."; } catch { } }
    }

    private void BtnCopyCurl_Click(object sender, RoutedEventArgs e)
    {
        if (NetList.SelectedItem is not CapturedNetRequest req) return;
        var sb = new StringBuilder($"curl -X {req.Method} \"{req.Url}\"");
        foreach (var line in (req.RequestHeaders ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith(":")) continue;
            sb.Append($" -H \"{trimmed.Replace("\"", "\\\"")}\"");
        }
        if (!string.IsNullOrWhiteSpace(req.PostData))
            sb.Append($" --data-raw \"{req.PostData.Replace("\"", "\\\"")}\"");
        try { Clipboard.SetText(sb.ToString()); InspectorStatus.Text = "Copied full cURL command (with headers)."; } catch { }
    }

    private void BtnCopyPython_Click(object sender, RoutedEventArgs e)
    {
        if (NetList.SelectedItem is not CapturedNetRequest req) return;
        var sb = new StringBuilder();
        sb.AppendLine("import requests");
        sb.AppendLine($"url = {JsonSerializer.Serialize(req.Url)}");
        sb.AppendLine("headers = {");
        foreach (var line in (req.RequestHeaders ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            int idx = line.IndexOf(':');
            if (idx <= 0) continue;
            string k = line[..idx].Trim();
            string v = line[(idx + 1)..].Trim();
            if (k.StartsWith(":")) continue;
            sb.AppendLine($"    {JsonSerializer.Serialize(k)}: {JsonSerializer.Serialize(v)},");
        }
        sb.AppendLine("}");
        if (!string.IsNullOrWhiteSpace(req.PostData))
            sb.AppendLine($"data = {JsonSerializer.Serialize(req.PostData)}\nresp = requests.request({JsonSerializer.Serialize(req.Method)}, url, headers=headers, data=data)");
        else
            sb.AppendLine($"resp = requests.request({JsonSerializer.Serialize(req.Method)}, url, headers=headers)");
        sb.AppendLine("print(resp.status_code, resp.text[:500])");
        try { Clipboard.SetText(sb.ToString()); InspectorStatus.Text = "Copied Python requests snippet."; } catch { }
    }

    private void BtnCopyFetch_Click(object sender, RoutedEventArgs e)
    {
        if (NetList.SelectedItem is not CapturedNetRequest req) return;
        var sb = new StringBuilder();
        sb.AppendLine($"fetch({JsonSerializer.Serialize(req.Url)}, {{");
        sb.AppendLine($"  method: {JsonSerializer.Serialize(req.Method)},");
        if (!string.IsNullOrWhiteSpace(req.PostData))
            sb.AppendLine($"  body: {JsonSerializer.Serialize(req.PostData)},");
        sb.AppendLine("}).then(r => r.text()).then(console.log);");
        try { Clipboard.SetText(sb.ToString()); InspectorStatus.Text = "Copied JS fetch() snippet."; } catch { }
    }

    private void BtnExportHar_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog { Filter = "HAR 1.2 Archive (*.har)|*.har", FileName = "mh_capture.har", Title = "Export HAR 1.2 (Reqable / Fiddler / DevTools)" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var entries = _allNet.Where(r => !r.Method.StartsWith("WS")).Select(r => new
            {
                startedDateTime = DateTime.UtcNow.ToString("O"),
                time = r.DurationMs,
                request = new
                {
                    method = r.Method,
                    url = r.Url,
                    httpVersion = string.IsNullOrEmpty(r.Protocol) ? "HTTP/1.1" : r.Protocol,
                    headers = ParseHeadersList(r.RequestHeaders),
                    queryString = Array.Empty<object>(),
                    cookies = Array.Empty<object>(),
                    headersSize = -1,
                    bodySize = r.PostData?.Length ?? 0,
                    postData = string.IsNullOrEmpty(r.PostData) ? null : new { mimeType = "application/json", text = r.PostData }
                },
                response = new
                {
                    status = r.StatusCode,
                    statusText = r.StatusText,
                    httpVersion = string.IsNullOrEmpty(r.Protocol) ? "HTTP/1.1" : r.Protocol,
                    headers = ParseHeadersList(r.ResponseHeaders),
                    cookies = Array.Empty<object>(),
                    content = new { size = r.SizeBytes, mimeType = "text/plain", text = r.ResponseBody ?? "" },
                    redirectURL = "",
                    headersSize = -1,
                    bodySize = r.SizeBytes
                },
                cache = new { },
                timings = new { send = 0, wait = r.DurationMs, receive = 0 }
            }).ToList();

            var har = new { log = new { version = "1.2", creator = new { name = "MH Advanced Tool", version = "4.3.0" }, entries } };
            File.WriteAllText(dlg.FileName, JsonSerializer.Serialize(har, new JsonSerializerOptions { WriteIndented = true }));
            InspectorStatus.Text = $"Exported HAR 1.2 ({entries.Count} requests) to {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "HAR Export Error", ex.Message); }
    }

    private static List<object> ParseHeadersList(string raw)
    {
        var list = new List<object>();
        foreach (var line in (raw ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            int idx = line.IndexOf(':');
            if (idx <= 0) continue;
            list.Add(new { name = line[..idx].Trim(), value = line[(idx + 1)..].Trim() });
        }
        return list;
    }

    private void BtnExportJson_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog
        {
            Filter = "JSON File (*.json)|*.json",
            FileName = _showingUi ? "ui_actions_recording.json" : "network_capture.json",
            Title = "Export Captured Data"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            string json = _showingUi
                ? JsonSerializer.Serialize(_uiActions.ToList(), new JsonSerializerOptions { WriteIndented = true })
                : JsonSerializer.Serialize(_allNet.ToList(), new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(dlg.FileName, json);
            InspectorStatus.Text = $"Exported to {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Export Error", ex.Message); }
    }

    private void BtnExportPlaywright_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog { Filter = "Python Playwright (*.py)|*.py", FileName = "recorded_playwright.py" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine("from playwright.sync_api import sync_playwright\n");
            sb.AppendLine("with sync_playwright() as p:");
            sb.AppendLine("    browser = p.chromium.connect_over_cdp('http://127.0.0.1:9222')");
            sb.AppendLine("    page = browser.contexts[0].pages[0]");
            foreach (var a in _uiActions.Reverse())
            {
                string loc = !string.IsNullOrEmpty(a.XPath) ? $"xpath={a.XPath}" : a.Selector;
                loc = loc.Replace("'", "\\'");
                string val = a.Value.Replace("'", "\\'");
                if (a.Action is "CLICK" or "CHECK") sb.AppendLine($"    page.locator('{loc}').first.click()");
                else if (a.Action == "DBLCLICK") sb.AppendLine($"    page.locator('{loc}').first.dblclick()");
                else if (a.Action == "WRITE") sb.AppendLine($"    page.locator('{loc}').first.fill('{val}')");
                else if (a.Action == "SELECT") sb.AppendLine($"    page.locator('{loc}').first.select_option('{val}')");
                else if (a.Action == "KEYPRESS") sb.AppendLine($"    page.keyboard.press('{val}')");
            }
            File.WriteAllText(dlg.FileName, sb.ToString());
            InspectorStatus.Text = $"Exported Playwright script to {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Export Error", ex.Message); }
    }

    private void BtnExportSelenium_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog { Filter = "Python Selenium (*.py)|*.py", FileName = "recorded_selenium.py" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine("from selenium import webdriver");
            sb.AppendLine("from selenium.webdriver.common.by import By");
            sb.AppendLine("from selenium.webdriver.support.ui import Select\n");
            sb.AppendLine("opts = webdriver.ChromeOptions()");
            sb.AppendLine("opts.add_experimental_option('debuggerAddress', '127.0.0.1:9222')");
            sb.AppendLine("driver = webdriver.Chrome(options=opts)");
            foreach (var a in _uiActions.Reverse())
            {
                string xp = (string.IsNullOrEmpty(a.XPath) ? a.FullXPath : a.XPath).Replace("'", "\\'");
                string val = a.Value.Replace("'", "\\'");
                if (a.Action is "CLICK" or "CHECK") sb.AppendLine($"driver.find_element(By.XPATH, '{xp}').click()");
                else if (a.Action == "WRITE") sb.AppendLine($"el = driver.find_element(By.XPATH, '{xp}'); el.clear(); el.send_keys('{val}')");
                else if (a.Action == "SELECT") sb.AppendLine($"Select(driver.find_element(By.XPATH, '{xp}')).select_by_value('{val}')");
            }
            File.WriteAllText(dlg.FileName, sb.ToString());
            InspectorStatus.Text = $"Exported Selenium script to {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex) { DarkDialog.ShowInfo(this, "Export Error", ex.Message); }
    }

    private void BtnClear_Click(object sender, RoutedEventArgs e)
    {
        if (_showingUi) { _uiActions.Clear(); TxtUiDetail.Text = ""; }
        else { _allNet.Clear(); TxtNetDetail.Text = ""; }
        UpdateCounts();
    }
}
