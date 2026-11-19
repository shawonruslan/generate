using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace MHVirtualCam;

public partial class MainWindow : Window
{
    private readonly FrameEngine _engine = new();
    private readonly ObservableCollection<PlaylistItem> _items = new();
    private readonly Dictionary<string, SavedShortcut> _savedShortcuts = new(StringComparer.OrdinalIgnoreCase);
    private GlobalHotkeys? _hotkeys;
    private bool _syncingUi;
    private bool _panning;
    private Point _panStart;
    private double _panStartX, _panStartY;

    private static readonly string ShortcutsFilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MHVirtualCam", "shortcuts.json");

    private sealed class SavedShortcut
    {
        public string Key { get; set; } = "";
        public int Modifiers { get; set; }
    }

    public MainWindow()
    {
        InitializeComponent();
        LoadSavedShortcuts();
        PlaylistBox.ItemsSource = _items;

        RatioCombo.ItemsSource = RatioPreset.All.Select(r => r.Name).ToList();
        RatioCombo.SelectedIndex = 0;
        FpsCombo.SelectedIndex = 1;   // 30 fps
        FitCombo.SelectedIndex = 0;   // Fill
        TransitionCombo.SelectedIndex = 0; // Fade
        RefreshResolutions();
        UpdateToggleStyles();
        UpdateLoopText();

        _engine.PreviewFrame += bmp => Dispatcher.BeginInvoke(() =>
        {
            PreviewImage.Source = bmp;
            PreviewEmptyText.Visibility = _items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        });
        _engine.CurrentItemChanged += idx => Dispatcher.BeginInvoke(() =>
        {
            PlaylistBox.SelectedIndex = idx;
            if (idx >= 0 && idx < _items.Count)
                StatusText.Text = $"Now showing: {_items[idx].FileName}";
        });
        _engine.PlaylistEnded += () => Dispatcher.BeginInvoke(() =>
        {
            PlayIcon.Data = (Geometry)FindResource("IconPlay");
            StatusText.Text = "Playlist finished";
        });
        _engine.Start();
    }

    // ------------------------------------------------------------ lifecycle
    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        _hotkeys = new GlobalHotkeys();
        _hotkeys.HotkeyPressed += name => Dispatcher.BeginInvoke(() => HandleHotkey(name));
        _hotkeys.ClipHotkeyPressed += idx => Dispatcher.BeginInvoke(() => JumpToClip(idx));
        _hotkeys.Register(hwnd);
        SyncClipHotkeys();
    }

    protected override void OnClosed(EventArgs e)
    {
        _hotkeys?.Dispose();
        _engine.Dispose();
        base.OnClosed(e);
    }

    // ------------------------------------------------------------ playlist
    private void AddFiles(IEnumerable<string> paths)
    {
        int added = 0;
        foreach (var p in paths.OrderBy(x => x))
        {
            if (Directory.Exists(p))
            {
                AddFiles(Directory.EnumerateFiles(p));
                continue;
            }
            if (PlaylistItem.TryCreate(p, out var item) && item is not null
                && !_engine.Playlist.Any(x => string.Equals(x.FilePath, p, StringComparison.OrdinalIgnoreCase)))
            {
                if (_savedShortcuts.TryGetValue(p, out var saved) &&
                    Enum.TryParse<Key>(saved.Key, out var parsedKey) &&
                    parsedKey != Key.None)
                {
                    item.ShortcutKey = parsedKey;
                    item.ShortcutModifiers = (ModifierKeys)saved.Modifiers;
                }
                _engine.Playlist.Add(item);
                _items.Add(item);
                added++;
            }
        }
        if (added > 0)
        {
            _engine.OnPlaylistChanged();
            SyncClipHotkeys();
            PlaylistCountText.Text = $"{_items.Count} item{(_items.Count == 1 ? "" : "s")}";
            StatusText.Text = $"Added {added} file(s). Playlist: {_items.Count} item(s).";
            PreviewEmptyText.Visibility = Visibility.Collapsed;
        }
    }

    private void BtnAddVideos_Click(object sender, RoutedEventArgs e) =>
        PickFiles("Video clips|*.mp4;*.mov;*.avi;*.mkv;*.webm;*.wmv;*.m4v|All files|*.*");

    private void BtnAddImages_Click(object sender, RoutedEventArgs e) =>
        PickFiles("Images|*.jpg;*.jpeg;*.png;*.bmp;*.webp;*.gif;*.tif;*.tiff|All files|*.*");

    private void PickFiles(string filter)
    {
        var dlg = new OpenFileDialog { Filter = filter, Multiselect = true, Title = "Add to playlist" };
        if (dlg.ShowDialog() == true) AddFiles(dlg.FileNames);
    }

    private void BtnClear_Click(object sender, RoutedEventArgs e)
    {
        _engine.Playlist.Clear(); _items.Clear();
        _engine.OnPlaylistChanged();
        SyncClipHotkeys();
        PlaylistCountText.Text = "0 items";
        PreviewEmptyText.Visibility = Visibility.Visible;
        StatusText.Text = "Playlist cleared";
    }

    private void BtnRemove_Click(object sender, RoutedEventArgs e)
    {
        if (PlaylistBox.SelectedIndex < 0) return;
        int i = PlaylistBox.SelectedIndex;
        _engine.Playlist.RemoveAt(i); _items.RemoveAt(i);
        _engine.OnPlaylistChanged();
        SyncClipHotkeys();
        PlaylistCountText.Text = $"{_items.Count} item{(_items.Count == 1 ? "" : "s")}";
    }

    private void BtnMoveUp_Click(object sender, RoutedEventArgs e) => MoveSelected(-1);
    private void BtnMoveDown_Click(object sender, RoutedEventArgs e) => MoveSelected(+1);

    private void MoveSelected(int delta)
    {
        int i = PlaylistBox.SelectedIndex;
        int j = i + delta;
        if (i < 0 || j < 0 || j >= _items.Count) return;
        (_engine.Playlist[i], _engine.Playlist[j]) = (_engine.Playlist[j], _engine.Playlist[i]);
        _items.Move(i, j);
        PlaylistBox.SelectedIndex = j;
        SyncClipHotkeys();
    }

    private void PlaylistBox_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (PlaylistBox.SelectedIndex >= 0) JumpToClip(PlaylistBox.SelectedIndex);
    }

    private void JumpToClip(int index)
    {
        if (index < 0 || index >= _items.Count) return;
        _engine.JumpTo(index);
        _engine.Resume();
        PlayIcon.Data = (Geometry)FindResource("IconPause");
        StatusText.Text = $"Switched to: {_items[index].FileName}";
    }

    private void PlaylistBox_SelectionChanged(object sender, SelectionChangedEventArgs e) { }

    private void Window_DragOver(object sender, DragEventArgs e)
        => e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;

    private void Window_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] files) AddFiles(files);
    }

    // --------------------------------------------------- per-clip shortcuts
    private void BtnSetShortcut_Click(object sender, RoutedEventArgs e)
    {
        if (PlaylistBox.SelectedIndex < 0 || PlaylistBox.SelectedIndex >= _items.Count)
        {
            StatusText.Text = "Select a clip or image in the playlist first to assign a shortcut.";
            return;
        }
        OpenShortcutDialog(_items[PlaylistBox.SelectedIndex]);
    }

    private void BtnClearShortcut_Click(object sender, RoutedEventArgs e)
    {
        if (PlaylistBox.SelectedIndex < 0 || PlaylistBox.SelectedIndex >= _items.Count) return;
        var item = _items[PlaylistBox.SelectedIndex];
        item.ShortcutKey = Key.None;
        item.ShortcutModifiers = ModifierKeys.None;
        _savedShortcuts.Remove(item.FilePath);
        SaveShortcutsToDisk();
        SyncClipHotkeys();
        StatusText.Text = $"Cleared shortcut for {item.FileName}";
    }

    private void OpenShortcutDialog(PlaylistItem item)
    {
        Key capturedKey = item.ShortcutKey;
        ModifierKeys capturedMods = item.ShortcutModifiers;

        var keyDisplay = new TextBlock
        {
            Text = item.HasShortcut ? item.ShortcutDisplay : "Press any key or combo...",
            FontSize = 18,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)FindResource(item.HasShortcut ? "Accent" : "Muted"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };

        var keyBox = new Border
        {
            Background = (Brush)FindResource("Panel"),
            BorderBrush = (Brush)FindResource("Accent"),
            BorderThickness = new Thickness(1.5),
            CornerRadius = new CornerRadius(8),
            Height = 56,
            Margin = new Thickness(0, 12, 0, 10),
            Child = keyDisplay
        };

        var btnSave = new Button { Content = "Save", Style = (Style)FindResource("AccentButton"), MinWidth = 84 };
        var btnClear = new Button { Content = "Clear", Style = (Style)FindResource("FlatButton"), MinWidth = 76, Margin = new Thickness(8, 0, 0, 0) };
        var btnCancel = new Button { Content = "Cancel", Style = (Style)FindResource("FlatButton"), MinWidth = 76, Margin = new Thickness(8, 0, 0, 0) };

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 8, 0, 0)
        };
        buttons.Children.Add(btnSave);
        buttons.Children.Add(btnClear);
        buttons.Children.Add(btnCancel);

        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(new TextBlock
        {
            Text = $"Assign Shortcut for: {item.FileName}",
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = (Brush)FindResource("Text")
        });
        root.Children.Add(new TextBlock
        {
            Text = "Press any key (e.g. F1, 1, Q, Ctrl+1, Alt+2) to switch directly to this clip or image.",
            FontSize = 11.5,
            Foreground = (Brush)FindResource("Muted"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 6, 0, 0)
        });
        root.Children.Add(keyBox);
        root.Children.Add(buttons);

        var dlg = new Window
        {
            Title = "Set Clip / Image Shortcut",
            Width = 430,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = this,
            Background = (Brush)FindResource("Bg"),
            Foreground = (Brush)FindResource("Text"),
            Content = root
        };

        dlg.PreviewKeyDown += (_, ke) =>
        {
            var k = ke.Key == Key.System ? ke.SystemKey : ke.Key;
            if (k == Key.Escape) { dlg.DialogResult = false; ke.Handled = true; return; }
            if (IsModifierOnlyKey(k)) { ke.Handled = true; return; }

            capturedKey = k;
            capturedMods = Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Shift);
            keyDisplay.Text = PlaylistItem.FormatShortcut(capturedMods, capturedKey);
            keyDisplay.Foreground = (Brush)FindResource("Accent");
            ke.Handled = true;
        };

        btnSave.Click += (_, _) =>
        {
            if (capturedKey != Key.None)
            {
                // Remove duplicate shortcut from any other item in playlist
                foreach (var other in _items)
                {
                    if (!ReferenceEquals(other, item) &&
                        other.ShortcutKey == capturedKey &&
                        other.ShortcutModifiers == capturedMods)
                    {
                        other.ShortcutKey = Key.None;
                        other.ShortcutModifiers = ModifierKeys.None;
                        _savedShortcuts.Remove(other.FilePath);
                    }
                }
                item.ShortcutKey = capturedKey;
                item.ShortcutModifiers = capturedMods;
                _savedShortcuts[item.FilePath] = new SavedShortcut
                {
                    Key = capturedKey.ToString(),
                    Modifiers = (int)capturedMods
                };
                SaveShortcutsToDisk();
                SyncClipHotkeys();
                StatusText.Text = $"Shortcut '{item.ShortcutDisplay}' assigned to {item.FileName}";
            }
            dlg.DialogResult = true;
        };

        btnClear.Click += (_, _) =>
        {
            item.ShortcutKey = Key.None;
            item.ShortcutModifiers = ModifierKeys.None;
            _savedShortcuts.Remove(item.FilePath);
            SaveShortcutsToDisk();
            SyncClipHotkeys();
            StatusText.Text = $"Cleared shortcut for {item.FileName}";
            dlg.DialogResult = true;
        };

        btnCancel.Click += (_, _) => dlg.DialogResult = false;
        dlg.ShowDialog();
    }

    private static bool IsModifierOnlyKey(Key k) =>
        k is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
          or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;

    private void SyncClipHotkeys()
    {
        if (_hotkeys is null) return;
        var bindings = new List<(int index, ModifierKeys modifiers, Key key)>();
        for (int i = 0; i < _items.Count; i++)
        {
            if (_items[i].HasShortcut)
                bindings.Add((i, _items[i].ShortcutModifiers, _items[i].ShortcutKey));
        }
        _hotkeys.RegisterClipHotkeys(bindings);
    }

    private void LoadSavedShortcuts()
    {
        try
        {
            if (!File.Exists(ShortcutsFilePath)) return;
            var json = File.ReadAllText(ShortcutsFilePath);
            var data = JsonSerializer.Deserialize<Dictionary<string, SavedShortcut>>(json);
            if (data is null) return;
            foreach (var kv in data) _savedShortcuts[kv.Key] = kv.Value;
        }
        catch { /* ignore corrupt file */ }
    }

    private void SaveShortcutsToDisk()
    {
        try
        {
            var dir = Path.GetDirectoryName(ShortcutsFilePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(_savedShortcuts, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(ShortcutsFilePath, json);
        }
        catch { /* non-fatal */ }
    }

    // ------------------------------------------------------------ transport
    private void BtnPlay_Click(object sender, RoutedEventArgs e) => TogglePlay();
    private void BtnNext_Click(object sender, RoutedEventArgs e) => _engine.Next();
    private void BtnPrev_Click(object sender, RoutedEventArgs e) => _engine.Previous();

    private void TogglePlay()
    {
        if (_engine.IsPlaying) { _engine.Pause(); PlayIcon.Data = (Geometry)FindResource("IconPlay"); StatusText.Text = "Paused"; }
        else { _engine.Resume(); PlayIcon.Data = (Geometry)FindResource("IconPause"); StatusText.Text = "Playing"; }
    }

    private void BtnLoop_Click(object sender, RoutedEventArgs e)
    {
        _engine.Settings.Loop = _engine.Settings.Loop switch
        {
            LoopMode.LoopPlaylist => LoopMode.LoopSingle,
            LoopMode.LoopSingle => LoopMode.None,
            _ => LoopMode.LoopPlaylist
        };
        UpdateLoopText(); UpdateToggleStyles();
    }

    private void BtnAuto_Click(object sender, RoutedEventArgs e)
    {
        _engine.Settings.AutoAdvance = !_engine.Settings.AutoAdvance;
        UpdateToggleStyles();
        StatusText.Text = _engine.Settings.AutoAdvance ? "Auto change: ON" : "Auto change: OFF";
    }

    private void UpdateLoopText() => LoopModeText.Text = _engine.Settings.Loop switch
    {
        LoopMode.LoopPlaylist => "Loop playlist",
        LoopMode.LoopSingle => "Loop current clip",
        _ => "Loop off - stop at end"
    };

    private void UpdateToggleStyles()
    {
        BtnLoop.Style = (Style)FindResource(_engine.Settings.Loop != LoopMode.None ? "ToggleOn" : "IconButton");
        LoopIcon.Fill = _engine.Settings.Loop != LoopMode.None
            ? new SolidColorBrush(Color.FromRgb(0x11, 0x11, 0x11)) : (Brush)FindResource("Text");
        BtnAuto.Style = (Style)FindResource(_engine.Settings.AutoAdvance ? "ToggleOn" : "IconButton");
        AutoIcon.Fill = _engine.Settings.AutoAdvance
            ? new SolidColorBrush(Color.FromRgb(0x11, 0x11, 0x11)) : (Brush)FindResource("Text");
    }

    // ------------------------------------------------------------- stream
    private void BtnStream_Click(object sender, RoutedEventArgs e) => ToggleStream();

    private void ToggleStream()
    {
        _engine.IsStreaming = !_engine.IsStreaming;
        if (_engine.IsStreaming && !_engine.IsPlaying) TogglePlay();
        OnAirDot.Fill = (Brush)FindResource(_engine.IsStreaming ? "Danger" : "Muted");
        OnAirText.Text = _engine.IsStreaming ? "ON AIR" : "OFF AIR";
        OnAirText.Foreground = (Brush)FindResource(_engine.IsStreaming ? "Danger" : "Muted");
        BtnStreamText.Text = _engine.IsStreaming ? "Stop Virtual Camera" : "Start Virtual Camera";
        StatusText.Text = _engine.IsStreaming
            ? "Virtual camera is LIVE - select 'MH Virtualcam' in Chrome / Edge / Zoom / Teams"
            : "Virtual camera stopped";
    }

    // ------------------------------------------------------------- settings
    private void RatioCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RatioCombo.SelectedIndex < 0) return;
        _engine.Settings.Ratio = RatioPreset.All[RatioCombo.SelectedIndex];
        RefreshResolutions();
    }

    private void RefreshResolutions()
    {
        _syncingUi = true;
        var ratio = _engine.Settings.Ratio;
        ResolutionCombo.ItemsSource = ratio.Resolutions.Select(r => $"{r.W} x {r.H}").ToList();
        int def = ratio.Resolutions.Length > 1 ? 1 : 0;   // middle = balanced default
        ResolutionCombo.SelectedIndex = def;
        _engine.Settings.Resolution = ratio.Resolutions[def];
        _syncingUi = false;
        UpdatePreviewMeta();
    }

    private void ResolutionCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingUi || ResolutionCombo.SelectedIndex < 0) return;
        _engine.Settings.Resolution = _engine.Settings.Ratio.Resolutions[ResolutionCombo.SelectedIndex];
        UpdatePreviewMeta();
    }

    private void FpsCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        => _engine.Settings.Fps = FpsCombo.SelectedIndex switch { 0 => 24, 2 => 60, _ => 30 };

    private void FitCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        => _engine.Settings.Fit = FitCombo.SelectedIndex switch { 1 => FitMode.Fit, 2 => FitMode.Stretch, _ => FitMode.Fill };

    private void TransitionCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        => _engine.Settings.Transition = TransitionCombo.SelectedIndex == 1 ? TransitionKind.Cut : TransitionKind.Fade;

    private void ImageSecondsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Settings.ImageSeconds = Math.Round(ImageSecondsSlider.Value);
        if (ImageSecondsText is not null) ImageSecondsText.Text = $"{_engine.Settings.ImageSeconds:0} sec";
    }

    private void UpdatePreviewMeta()
    {
        var (w, h) = _engine.Settings.Resolution;
        PreviewMetaText.Text = $"{w} x {h}  -  {_engine.Settings.Ratio.Name}  -  {_engine.Settings.Fps} fps";
    }

    // ---------------------------------------------------------------- zoom
    private void SetZoom(double zoom)
    {
        _engine.Settings.Zoom = Math.Clamp(zoom, 1.0, 4.0);
        if (Math.Abs(ZoomSlider.Value - _engine.Settings.Zoom) > 0.001)
            ZoomSlider.Value = _engine.Settings.Zoom;
        ZoomMetaText.Text = $"Zoom {(int)(_engine.Settings.Zoom * 100)}%";
        if (_engine.Settings.Zoom <= 1.001) { _engine.Settings.PanX = 0; _engine.Settings.PanY = 0; }
    }

    private void ZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) => SetZoom(e.NewValue);
    private void BtnZoomIn_Click(object sender, RoutedEventArgs e) => SetZoom(_engine.Settings.Zoom + 0.25);
    private void BtnZoomOut_Click(object sender, RoutedEventArgs e) => SetZoom(_engine.Settings.Zoom - 0.25);
    private void BtnZoomReset_Click(object sender, RoutedEventArgs e) => SetZoom(1.0);

    private void Preview_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        SetZoom(_engine.Settings.Zoom + (e.Delta > 0 ? 0.15 : -0.15));
        e.Handled = true;
    }

    private void Preview_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_engine.Settings.Zoom <= 1.001) return;
        _panning = true; _panStart = e.GetPosition(PreviewImage);
        _panStartX = _engine.Settings.PanX; _panStartY = _engine.Settings.PanY;
        PreviewImage.CaptureMouse();
    }

    private void Preview_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_panning) return;
        var p = e.GetPosition(PreviewImage);
        double dx = (p.X - _panStart.X) / Math.Max(1, PreviewImage.ActualWidth);
        double dy = (p.Y - _panStart.Y) / Math.Max(1, PreviewImage.ActualHeight);
        _engine.Settings.PanX = Math.Clamp(_panStartX - dx * 2, -1, 1);
        _engine.Settings.PanY = Math.Clamp(_panStartY - dy * 2, -1, 1);
    }

    private void Preview_MouseUp(object sender, MouseButtonEventArgs e)
    {
        _panning = false;
        PreviewImage.ReleaseMouseCapture();
    }

    // ------------------------------------------------------------- hotkeys
    private void HandleHotkey(string name)
    {
        switch (name)
        {
            case "toggle-camera": ToggleStream(); break;
            case "next": _engine.Next(); break;
            case "prev": _engine.Previous(); break;
            case "playpause": TogglePlay(); break;
            case "zoom-in": SetZoom(_engine.Settings.Zoom + 0.25); break;
            case "zoom-out": SetZoom(_engine.Settings.Zoom - 0.25); break;
            case "zoom-reset": SetZoom(1.0); break;
            case "loop": BtnLoop_Click(this, new RoutedEventArgs()); break;
        }
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox) return;

        var actualKey = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Shift);

        // 1) Custom per-clip / per-image shortcuts take top priority
        for (int i = 0; i < _items.Count; i++)
        {
            if (_items[i].HasShortcut && _items[i].ShortcutKey == actualKey && _items[i].ShortcutModifiers == mods)
            {
                JumpToClip(i);
                e.Handled = true;
                return;
            }
        }

        bool ctrl = (mods & ModifierKeys.Control) != 0;
        if (ctrl && actualKey == Key.O) { BtnAddVideos_Click(sender, e); e.Handled = true; return; }
        if (ctrl && actualKey == Key.Up) { MoveSelected(-1); e.Handled = true; return; }
        if (ctrl && actualKey == Key.Down) { MoveSelected(+1); e.Handled = true; return; }

        if (mods != ModifierKeys.None) return;

        switch (actualKey)
        {
            case Key.Space: TogglePlay(); e.Handled = true; break;
            case Key.Right: case Key.N: _engine.Next(); e.Handled = true; break;
            case Key.Left: case Key.B: _engine.Previous(); e.Handled = true; break;
            case Key.OemPlus: case Key.Add: SetZoom(_engine.Settings.Zoom + 0.25); e.Handled = true; break;
            case Key.OemMinus: case Key.Subtract: SetZoom(_engine.Settings.Zoom - 0.25); e.Handled = true; break;
            case Key.D0: case Key.NumPad0: SetZoom(1.0); e.Handled = true; break;
            case Key.L: BtnLoop_Click(sender, e); e.Handled = true; break;
            case Key.A: BtnAuto_Click(sender, e); e.Handled = true; break;
            case Key.S: ToggleStream(); e.Handled = true; break;
            case Key.F:
                FitCombo.SelectedIndex = (FitCombo.SelectedIndex + 1) % 3; e.Handled = true; break;
            case Key.R:
                RatioCombo.SelectedIndex = (RatioCombo.SelectedIndex + 1) % RatioPreset.All.Length; e.Handled = true; break;
            case Key.Delete: BtnRemove_Click(sender, e); e.Handled = true; break;
            case Key.W: _engine.Settings.PanY = Math.Clamp(_engine.Settings.PanY - 0.1, -1, 1); e.Handled = true; break;
            case Key.D: _engine.Settings.PanX = Math.Clamp(_engine.Settings.PanX + 0.1, -1, 1); e.Handled = true; break;
        }
    }

    // ------------------------------------------------------------ shortcuts dialog
    private void BtnShortcuts_Click(object sender, RoutedEventArgs e)
    {
        var sb = new StringBuilder();
        sb.AppendLine("CUSTOM CLIP / IMAGE SHORTCUTS");
        var customItems = _items.Where(x => x.HasShortcut).ToList();
        if (customItems.Count == 0)
        {
            sb.AppendLine("  (None yet — select any clip or image and click 'Set Shortcut')");
        }
        else
        {
            foreach (var it in customItems)
                sb.AppendLine($"  {it.ShortcutDisplay,-16} {it.FileName} ({it.KindLabel})");
        }
        sb.AppendLine();
        sb.Append(ShortcutsText);

        var win = new Window
        {
            Title = "Keyboard Shortcuts",
            Width = 560, Height = 540,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = this,
            Background = (Brush)FindResource("Bg"),
            Foreground = (Brush)FindResource("Text"),
            Content = new ScrollViewer
            {
                Content = new TextBlock
                {
                    Text = sb.ToString(),
                    Margin = new Thickness(20),
                    FontSize = 13,
                    FontFamily = new FontFamily("Consolas"),
                    TextWrapping = TextWrapping.Wrap,
                    Foreground = (Brush)FindResource("Text")
                }
            }
        };
        win.ShowDialog();
    }

    private const string ShortcutsText =
        "IN-APP SHORTCUTS\n" +
        "  Space            Play / Pause\n" +
        "  Right / N        Next clip or image\n" +
        "  Left / B         Previous clip or image\n" +
        "  + / -            Zoom in / out\n" +
        "  Mouse wheel      Zoom (over preview)\n" +
        "  Drag preview     Pan while zoomed\n" +
        "  0                Reset zoom and pan\n" +
        "  W / D            Pan up / right while zoomed\n" +
        "  S                Start / Stop virtual camera\n" +
        "  A                Toggle auto change\n" +
        "  L                Cycle loop mode\n" +
        "  F                Cycle fit mode\n" +
        "  R                Cycle aspect ratio\n" +
        "  Ctrl+O           Add files\n" +
        "  Ctrl+Up / Down   Move playlist item\n" +
        "  Delete           Remove selected item\n\n" +
        "GLOBAL SHORTCUTS (work in Chrome / Zoom / Teams too)\n" +
        "  Ctrl+Alt+S       Start / Stop virtual camera\n" +
        "  Ctrl+Alt+N       Next clip or image\n" +
        "  Ctrl+Alt+B       Previous clip or image\n" +
        "  Ctrl+Alt+Space   Play / Pause\n" +
        "  Ctrl+Alt+Up      Zoom in\n" +
        "  Ctrl+Alt+Down    Zoom out\n" +
        "  Ctrl+Alt+0       Reset zoom\n" +
        "  Ctrl+Alt+L       Cycle loop mode";
}
