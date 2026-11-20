using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
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
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    private static void ApplyDarkTitleBar(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        int dark = 1;
        if (DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int)) != 0)
            DwmSetWindowAttribute(hwnd, 19, ref dark, sizeof(int));
        int captionColor = 0x00171717; // #171717 (BGR)
        DwmSetWindowAttribute(hwnd, 35, ref captionColor, sizeof(int));
        int textColor = 0x00F2F2F2;    // #F2F2F2 (BGR)
        DwmSetWindowAttribute(hwnd, 36, ref textColor, sizeof(int));
    }

    private readonly FrameEngine _engine = new();
    private readonly ObservableCollection<PlaylistItem> _items = new();
    private readonly Dictionary<string, SavedShortcut> _savedShortcuts = new(StringComparer.OrdinalIgnoreCase);
    private List<(int DeviceId, string Name)> _audioDevices = new();
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

        _audioDevices = AudioEngine.GetOutputDevices();
        AudioDeviceCombo.ItemsSource = _audioDevices.Select(d => d.Name).ToList();
        AudioDeviceCombo.SelectedIndex = 0;

        RatioCombo.ItemsSource = RatioPreset.All.Select(r => r.Name).ToList();
        RatioCombo.SelectedIndex = 0;
        FpsCombo.SelectedIndex = 1;   // 30 fps
        FitCombo.SelectedIndex = 0;   // Fill
        TransitionCombo.SelectedIndex = 0; // Fade
        RefreshResolutions();
        UpdateToggleStyles();
        UpdateLoopText();
        UpdateZoomSpeedMeta();

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
    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        ApplyDarkTitleBar(this);
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyDarkTitleBar(this);
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
                && !_engine.Playlist.Any(x => string.Equals(x.UniqueKey, item.UniqueKey, StringComparison.OrdinalIgnoreCase)))
            {
                ApplySavedShortcut(item);
                _engine.Playlist.Add(item);
                _items.Add(item);
                added++;
            }
        }
        if (added > 0)
        {
            _engine.OnPlaylistChanged();
            SyncClipHotkeys();
            UpdatePlaylistCount();
            StatusText.Text = $"Added {added} file(s). Playlist: {_items.Count} item(s).";
            PreviewEmptyText.Visibility = Visibility.Collapsed;
        }
    }

    private void ApplySavedShortcut(PlaylistItem item)
    {
        if (_savedShortcuts.TryGetValue(item.UniqueKey, out var saved) &&
            Enum.TryParse<Key>(saved.Key, out var parsedKey) &&
            parsedKey != Key.None)
        {
            item.ShortcutKey = parsedKey;
            item.ShortcutModifiers = (ModifierKeys)saved.Modifiers;
        }
    }

    private void UpdatePlaylistCount()
        => PlaylistCountText.Text = $"{_items.Count} item{(_items.Count == 1 ? "" : "s")}";

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
        UpdatePlaylistCount();
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
        UpdatePlaylistCount();
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

    // --------------------------------------------------- 3D camera effect
    private void Chk3DCamera_Changed(object sender, RoutedEventArgs e)
    {
        if (_engine is null) return;
        _engine.Settings.Camera3DEnabled = Chk3DCamera.IsChecked == true;
        UpdateZoomSpeedMeta();
    }

    private void Depth3DSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Settings.Camera3DDepth = Math.Clamp(e.NewValue / 100.0, 0.0, 1.0);
        if (Depth3DText is not null) Depth3DText.Text = $"{(int)Math.Round(e.NewValue)}%";
    }

    private void Motion3DSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Settings.Camera3DMotion = Math.Clamp(e.NewValue / 100.0, 0.0, 1.0);
        if (Motion3DText is not null) Motion3DText.Text = $"{(int)Math.Round(e.NewValue)}%";
    }

    // --------------------------------------------------- audio & music
    private void AudioDeviceCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (AudioDeviceCombo.SelectedIndex < 0 || AudioDeviceCombo.SelectedIndex >= _audioDevices.Count) return;
        var dev = _audioDevices[AudioDeviceCombo.SelectedIndex];
        _engine.Audio.SetOutputDevice(dev.DeviceId);
        StatusText.Text = $"Audio output: {dev.Name}";
    }

    private void ChkVideoSound_Changed(object sender, RoutedEventArgs e)
    {
        if (_engine is null) return;
        _engine.Audio.SetVideoMuted(ChkVideoSound.IsChecked != true);
    }

    private void VideoVolSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Audio.SetVideoVolume(e.NewValue / 100.0);
        if (VideoVolText is not null) VideoVolText.Text = $"{(int)Math.Round(e.NewValue)}%";
    }

    private void BtnAddMusic_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "Audio / Music|*.mp3;*.wav;*.m4a;*.aac;*.wma;*.flac;*.mp4|All files|*.*",
            Title = "Select Background Music or Sound"
        };
        if (dlg.ShowDialog() == true)
        {
            if (_engine.Audio.LoadAndPlayMusic(dlg.FileName))
            {
                MusicTrackText.Text = $"Playing: {Path.GetFileName(dlg.FileName)}";
                StatusText.Text = $"Music started: {Path.GetFileName(dlg.FileName)}";
            }
            else
            {
                StatusText.Text = "Could not play selected audio file.";
            }
        }
    }

    private void BtnMusicPlay_Click(object sender, RoutedEventArgs e)
    {
        _engine.Audio.ToggleMusic();
        var name = _engine.Audio.CurrentMusicName;
        if (name is not null)
            MusicTrackText.Text = _engine.Audio.IsMusicPlaying ? $"Playing: {name}" : $"Paused: {name}";
    }

    private void BtnMusicStop_Click(object sender, RoutedEventArgs e)
    {
        _engine.Audio.StopMusic();
        MusicTrackText.Text = "No music loaded";
    }

    private void MusicVolSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Audio.SetMusicVolume(e.NewValue / 100.0);
        if (MusicVolText is not null) MusicVolText.Text = $"{(int)Math.Round(e.NewValue)}%";
    }

    // --------------------------------------------------- split video clip
    private void BtnSplitClip_Click(object sender, RoutedEventArgs e)
    {
        if (PlaylistBox.SelectedIndex < 0 || PlaylistBox.SelectedIndex >= _items.Count)
        {
            StatusText.Text = "Select a video clip in the playlist first to split it.";
            return;
        }
        var item = _items[PlaylistBox.SelectedIndex];
        if (item.Kind != MediaKind.Video)
        {
            StatusText.Text = "Only video clips can be split into parts.";
            return;
        }
        OpenSplitClipDialog(item);
    }

    private void OpenSplitClipDialog(PlaylistItem sourceItem)
    {
        double totalSec = FrameEngine.GetVideoDurationSeconds(sourceItem.FilePath);
        if (totalSec <= 0.5)
        {
            StatusText.Text = "Could not read duration of this video file.";
            return;
        }

        string baseName = Path.GetFileNameWithoutExtension(sourceItem.FilePath);

        TextBox MakeDarkTextBox(string text, double width = 100) => new()
        {
            Text = text,
            Width = width,
            Padding = new Thickness(8, 5, 8, 5),
            Background = (Brush)FindResource("PanelAlt"),
            Foreground = (Brush)FindResource("Text"),
            BorderBrush = (Brush)FindResource("BorderBrush"),
            BorderThickness = new Thickness(1),
            CaretBrush = (Brush)FindResource("Accent"),
            FontSize = 12.5
        };

        var rbEqual = new RadioButton
        {
            Content = "Split into equal parts",
            IsChecked = true,
            Foreground = (Brush)FindResource("Text"),
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 12, 0, 6)
        };
        var txtParts = MakeDarkTextBox("3", 70);
        var chkAutoKey = new CheckBox
        {
            Content = "Auto-assign shortcuts (1, 2, 3...)",
            IsChecked = true,
            Foreground = (Brush)FindResource("Text"),
            Margin = new Thickness(12, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var equalRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 0, 0, 10) };
        equalRow.Children.Add(new TextBlock { Text = "Parts:", Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        equalRow.Children.Add(txtParts);
        equalRow.Children.Add(chkAutoKey);

        var rbCustom = new RadioButton
        {
            Content = "Add a custom time range (mm:ss or seconds)",
            Foreground = (Brush)FindResource("Text"),
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 6, 0, 6)
        };
        var txtStart = MakeDarkTextBox("0:00", 75);
        var txtEnd = MakeDarkTextBox(PlaylistItem.FormatTime(Math.Min(10, totalSec)), 75);
        var txtLabel = MakeDarkTextBox($"{baseName} - Cut", 160);

        var customRow1 = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 0, 0, 8) };
        customRow1.Children.Add(new TextBlock { Text = "Start:", Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        customRow1.Children.Add(txtStart);
        customRow1.Children.Add(new TextBlock { Text = "End:", Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 6, 0) });
        customRow1.Children.Add(txtEnd);

        var customRow2 = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 0, 0, 10) };
        customRow2.Children.Add(new TextBlock { Text = "Name:", Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        customRow2.Children.Add(txtLabel);

        var errText = new TextBlock { Foreground = (Brush)FindResource("Danger"), FontSize = 11.5, Margin = new Thickness(0, 2, 0, 6) };

        var btnAdd = new Button { Content = "Create Parts", Style = (Style)FindResource("AccentButton"), MinWidth = 104 };
        var btnCancel = new Button { Content = "Cancel", Style = (Style)FindResource("FlatButton"), MinWidth = 76, Margin = new Thickness(8, 0, 0, 0) };
        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 6, 0, 0) };
        btnRow.Children.Add(btnAdd);
        btnRow.Children.Add(btnCancel);

        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(new TextBlock
        {
            Text = $"Split Video: {Path.GetFileName(sourceItem.FilePath)}",
            FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis
        });
        root.Children.Add(new TextBlock
        {
            Text = $"Total duration: {PlaylistItem.FormatTime(totalSec)} ({totalSec:0.0} sec)",
            FontSize = 11.5, Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 4, 0, 0)
        });
        root.Children.Add(rbEqual);
        root.Children.Add(equalRow);
        root.Children.Add(rbCustom);
        root.Children.Add(customRow1);
        root.Children.Add(customRow2);
        root.Children.Add(errText);
        root.Children.Add(btnRow);

        var dlg = new Window
        {
            Title = "Split Video Clip",
            Width = 460,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = this,
            Background = (Brush)FindResource("Bg"),
            Foreground = (Brush)FindResource("Text"),
            Content = root
        };
        dlg.SourceInitialized += (_, _) => ApplyDarkTitleBar(dlg);

        btnAdd.Click += (_, _) =>
        {
            errText.Text = "";
            var newParts = new List<PlaylistItem>();

            if (rbEqual.IsChecked == true)
            {
                if (!int.TryParse(txtParts.Text.Trim(), out int count) || count < 2 || count > 20)
                {
                    errText.Text = "Enter a number of parts between 2 and 20.";
                    return;
                }
                double step = totalSec / count;
                for (int i = 0; i < count; i++)
                {
                    double s = i * step;
                    double eSec = (i == count - 1) ? totalSec : (i + 1) * step;
                    var part = new PlaylistItem
                    {
                        FilePath = sourceItem.FilePath,
                        Kind = MediaKind.Video,
                        StartSec = s,
                        EndSec = eSec,
                        CustomLabel = $"{baseName} [Part {i + 1}: {PlaylistItem.FormatTime(s)}-{PlaylistItem.FormatTime(eSec)}]"
                    };
                    if (chkAutoKey.IsChecked == true)
                    {
                        var autoKey = GetAutoKeyForIndex(i);
                        if (autoKey != Key.None)
                        {
                            ClearDuplicateShortcut(part, autoKey, ModifierKeys.None);
                            part.ShortcutKey = autoKey;
                            part.ShortcutModifiers = ModifierKeys.None;
                            _savedShortcuts[part.UniqueKey] = new SavedShortcut { Key = autoKey.ToString(), Modifiers = 0 };
                        }
                    }
                    newParts.Add(part);
                }
            }
            else
            {
                if (!TryParseTime(txtStart.Text, out double s) || !TryParseTime(txtEnd.Text, out double eSec))
                {
                    errText.Text = "Invalid time format. Use seconds (e.g. 12) or mm:ss (e.g. 0:12).";
                    return;
                }
                s = Math.Clamp(s, 0, totalSec);
                eSec = Math.Clamp(eSec, 0, totalSec);
                if (eSec <= s + 0.2)
                {
                    errText.Text = "End time must be greater than Start time.";
                    return;
                }
                string label = string.IsNullOrWhiteSpace(txtLabel.Text)
                    ? $"{baseName} [{PlaylistItem.FormatTime(s)}-{PlaylistItem.FormatTime(eSec)}]"
                    : $"{txtLabel.Text.Trim()} [{PlaylistItem.FormatTime(s)}-{PlaylistItem.FormatTime(eSec)}]";
                newParts.Add(new PlaylistItem
                {
                    FilePath = sourceItem.FilePath,
                    Kind = MediaKind.Video,
                    StartSec = s,
                    EndSec = eSec,
                    CustomLabel = label
                });
            }

            foreach (var part in newParts)
            {
                _engine.Playlist.Add(part);
                _items.Add(part);
            }
            SaveShortcutsToDisk();
            _engine.OnPlaylistChanged();
            SyncClipHotkeys();
            UpdatePlaylistCount();
            PreviewEmptyText.Visibility = Visibility.Collapsed;
            StatusText.Text = $"Created {newParts.Count} split part(s) from {Path.GetFileName(sourceItem.FilePath)}.";
            dlg.DialogResult = true;
        };

        btnCancel.Click += (_, _) => dlg.DialogResult = false;
        dlg.ShowDialog();
    }

    private static Key GetAutoKeyForIndex(int i) => i switch
    {
        >= 0 and <= 8 => Key.D1 + i,
        >= 9 and <= 20 => Key.F1 + (i - 9),
        _ => Key.None
    };

    private static bool TryParseTime(string input, out double seconds)
    {
        seconds = 0;
        input = input.Trim();
        if (double.TryParse(input, NumberStyles.Float, CultureInfo.InvariantCulture, out seconds))
            return seconds >= 0;
        var parts = input.Split(':');
        if (parts.Length == 2 &&
            int.TryParse(parts[0], out int m) &&
            double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out double s))
        {
            seconds = m * 60 + s;
            return seconds >= 0;
        }
        if (parts.Length == 3 &&
            int.TryParse(parts[0], out int h) &&
            int.TryParse(parts[1], out int m3) &&
            double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out double s3))
        {
            seconds = h * 3600 + m3 * 60 + s3;
            return seconds >= 0;
        }
        return false;
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
        _savedShortcuts.Remove(item.UniqueKey);
        SaveShortcutsToDisk();
        SyncClipHotkeys();
        StatusText.Text = $"Cleared shortcut for {item.FileName}";
    }

    private void ClearDuplicateShortcut(PlaylistItem target, Key key, ModifierKeys mods)
    {
        foreach (var other in _items)
        {
            if (!ReferenceEquals(other, target) &&
                other.ShortcutKey == key &&
                other.ShortcutModifiers == mods)
            {
                other.ShortcutKey = Key.None;
                other.ShortcutModifiers = ModifierKeys.None;
                _savedShortcuts.Remove(other.UniqueKey);
            }
        }
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
        dlg.SourceInitialized += (_, _) => ApplyDarkTitleBar(dlg);

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
                ClearDuplicateShortcut(item, capturedKey, capturedMods);
                item.ShortcutKey = capturedKey;
                item.ShortcutModifiers = capturedMods;
                _savedShortcuts[item.UniqueKey] = new SavedShortcut
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
            _savedShortcuts.Remove(item.UniqueKey);
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
        catch { }
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
        catch { }
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
    private void BtnOpenBrowser_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var exe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "browser", "MHBrowser.exe");
            if (File.Exists(exe))
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true });
                StatusText.Text = "Opened MH Browser";
            }
            else
            {
                StatusText.Text = "MHBrowser.exe not found in application folder.";
            }
        }
        catch (Exception ex) { StatusText.Text = "Could not launch MH Browser: " + ex.Message; }
    }

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
            ? "Virtual camera is LIVE - select 'HD USB Webcam' in Chrome / Edge / Emulator / Zoom"
            : "Virtual camera stopped";
    }

    // ------------------------------------------------------------- settings
    private void Combo_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (sender is ComboBox cb && !cb.IsDropDownOpen) e.Handled = true;
    }

    private void RatioCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RatioCombo.SelectedIndex < 0) return;
        _engine.Settings.Ratio = RatioPreset.All[RatioCombo.SelectedIndex];
        _engine.ResetRenderState();
        CenterPan();
        RefreshResolutions();
    }

    private void RefreshResolutions()
    {
        _syncingUi = true;
        var ratio = _engine.Settings.Ratio;
        ResolutionCombo.ItemsSource = ratio.Resolutions.Select(r => $"{r.W} x {r.H}").ToList();
        int def = ratio.Resolutions.Length > 1 ? 1 : 0;
        ResolutionCombo.SelectedIndex = def;
        _engine.Settings.Resolution = ratio.Resolutions[def];
        _engine.ResetRenderState();
        _syncingUi = false;
        UpdatePreviewMeta();
    }

    private void ResolutionCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingUi || ResolutionCombo.SelectedIndex < 0) return;
        _engine.Settings.Resolution = _engine.Settings.Ratio.Resolutions[ResolutionCombo.SelectedIndex];
        _engine.ResetRenderState();
        UpdatePreviewMeta();
    }

    private void FpsCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _engine.Settings.Fps = FpsCombo.SelectedIndex switch { 0 => 24, 2 => 60, _ => 30 };
        UpdatePreviewMeta();
    }

    private void FitCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _engine.Settings.Fit = FitCombo.SelectedIndex switch { 1 => FitMode.Fit, 2 => FitMode.Stretch, _ => FitMode.Fill };
        _engine.ResetRenderState();
    }

    private void TransitionCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        => _engine.Settings.Transition = TransitionCombo.SelectedIndex == 1 ? TransitionKind.Cut : TransitionKind.Fade;

    private void ImageSecondsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _engine.Settings.ImageSeconds = Math.Round(ImageSecondsSlider.Value);
        if (ImageSecondsText is not null) ImageSecondsText.Text = $"{_engine.Settings.ImageSeconds:0} sec";
    }

    // ------------------------------------------------------------- speed
    private void SetSpeed(double speed)
    {
        speed = Math.Clamp(Math.Round(speed, 2), 0.25, 3.0);
        _engine.Settings.PlaybackSpeed = speed;
        if (SpeedSlider is not null && Math.Abs(SpeedSlider.Value - speed) > 0.001)
            SpeedSlider.Value = speed;
        if (SpeedText is not null) SpeedText.Text = $"{speed:0.00}x";
        UpdateZoomSpeedMeta();
    }

    private void SpeedSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) => SetSpeed(e.NewValue);
    private void BtnSpeed05_Click(object sender, RoutedEventArgs e) => SetSpeed(0.5);
    private void BtnSpeed10_Click(object sender, RoutedEventArgs e) => SetSpeed(1.0);
    private void BtnSpeed15_Click(object sender, RoutedEventArgs e) => SetSpeed(1.5);
    private void BtnSpeed20_Click(object sender, RoutedEventArgs e) => SetSpeed(2.0);

    private void UpdatePreviewMeta()
    {
        if (PreviewMetaText is null) return;
        var (w, h) = _engine.Settings.Resolution;
        PreviewMetaText.Text = $"{w} x {h}  -  {_engine.Settings.Ratio.Name}  -  {_engine.Settings.Fps} fps";
    }

    private void UpdateZoomSpeedMeta()
    {
        if (ZoomMetaText is null) return;
        string mode = _engine.Settings.Camera3DEnabled ? "3D Dolly" : "Zoom";
        ZoomMetaText.Text = $"{mode} {(int)(_engine.Settings.Zoom * 100)}%  -  {_engine.Settings.PlaybackSpeed:0.00}x";
    }

    // -------------------------------------------------------- zoom & position
    private void SetZoom(double zoom)
    {
        _engine.Settings.Zoom = Math.Clamp(zoom, 1.0, 4.0);
        if (ZoomSlider is not null && Math.Abs(ZoomSlider.Value - _engine.Settings.Zoom) > 0.001)
            ZoomSlider.Value = _engine.Settings.Zoom;
        UpdateZoomSpeedMeta();
    }

    private void NudgePan(double dx, double dy)
    {
        _engine.Settings.PanX = Math.Clamp(_engine.Settings.PanX + dx, -1.0, 1.0);
        _engine.Settings.PanY = Math.Clamp(_engine.Settings.PanY + dy, -1.0, 1.0);
        UpdatePanMeta();
    }

    private void CenterPan()
    {
        _engine.Settings.PanX = 0;
        _engine.Settings.PanY = 0;
        UpdatePanMeta();
    }

    private void UpdatePanMeta()
    {
        if (PanMetaText is null) return;
        int px = (int)Math.Round(_engine.Settings.PanX * 100);
        int py = (int)Math.Round(_engine.Settings.PanY * 100);
        PanMetaText.Text = $"X: {px:+#;-#;0}%   Y: {py:+#;-#;0}%";
    }

    private void ZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) => SetZoom(e.NewValue);
    private void BtnZoomIn_Click(object sender, RoutedEventArgs e) => SetZoom(_engine.Settings.Zoom + 0.25);
    private void BtnZoomOut_Click(object sender, RoutedEventArgs e) => SetZoom(_engine.Settings.Zoom - 0.25);
    private void BtnZoomReset_Click(object sender, RoutedEventArgs e) { SetZoom(1.0); CenterPan(); }

    private void BtnPanUp_Click(object sender, RoutedEventArgs e) => NudgePan(0, -0.08);
    private void BtnPanDown_Click(object sender, RoutedEventArgs e) => NudgePan(0, +0.08);
    private void BtnPanLeft_Click(object sender, RoutedEventArgs e) => NudgePan(-0.08, 0);
    private void BtnPanRight_Click(object sender, RoutedEventArgs e) => NudgePan(+0.08, 0);
    private void BtnPanCenter_Click(object sender, RoutedEventArgs e) => CenterPan();

    private void Preview_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        SetZoom(_engine.Settings.Zoom + (e.Delta > 0 ? 0.15 : -0.15));
        e.Handled = true;
    }

    private void Preview_MouseDown(object sender, MouseButtonEventArgs e)
    {
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
        _engine.Settings.PanX = Math.Clamp(_panStartX + dx * 1.5, -1, 1);
        _engine.Settings.PanY = Math.Clamp(_panStartY + dy * 1.5, -1, 1);
        UpdatePanMeta();
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
            case "zoom-reset": SetZoom(1.0); CenterPan(); break;
            case "loop": BtnLoop_Click(this, new RoutedEventArgs()); break;
        }
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox) return;

        var actualKey = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Shift);

        // 1) Custom per-clip / per-part / per-image shortcuts take top priority
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

        if (!ctrl && (mods == ModifierKeys.None || mods == ModifierKeys.Shift))
        {
            switch (actualKey)
            {
                case Key.Up: NudgePan(0, -0.08); e.Handled = true; return;
                case Key.Down: NudgePan(0, +0.08); e.Handled = true; return;
                case Key.Left: NudgePan(-0.08, 0); e.Handled = true; return;
                case Key.Right: NudgePan(+0.08, 0); e.Handled = true; return;
            }
        }

        if (mods != ModifierKeys.None) return;

        switch (actualKey)
        {
            case Key.Space: TogglePlay(); e.Handled = true; break;
            case Key.N: _engine.Next(); e.Handled = true; break;
            case Key.B: _engine.Previous(); e.Handled = true; break;
            case Key.OemPlus: case Key.Add: SetZoom(_engine.Settings.Zoom + 0.25); e.Handled = true; break;
            case Key.OemMinus: case Key.Subtract: SetZoom(_engine.Settings.Zoom - 0.25); e.Handled = true; break;
            case Key.OemOpenBrackets: SetSpeed(_engine.Settings.PlaybackSpeed - 0.25); e.Handled = true; break;
            case Key.OemCloseBrackets: SetSpeed(_engine.Settings.PlaybackSpeed + 0.25); e.Handled = true; break;
            case Key.D0: case Key.NumPad0: SetZoom(1.0); CenterPan(); e.Handled = true; break;
            case Key.L: BtnLoop_Click(sender, e); e.Handled = true; break;
            case Key.A: BtnAuto_Click(sender, e); e.Handled = true; break;
            case Key.S: ToggleStream(); e.Handled = true; break;
            case Key.F:
                FitCombo.SelectedIndex = (FitCombo.SelectedIndex + 1) % 3; e.Handled = true; break;
            case Key.Delete: BtnRemove_Click(sender, e); e.Handled = true; break;
        }
    }

    // ------------------------------------------------------------ shortcuts dialog
    private void BtnShortcuts_Click(object sender, RoutedEventArgs e)
    {
        var sb = new StringBuilder();
        sb.AppendLine("CUSTOM CLIP / PART / IMAGE SHORTCUTS");
        var customItems = _items.Where(x => x.HasShortcut).ToList();
        if (customItems.Count == 0)
        {
            sb.AppendLine("  (None yet — select any item and click 'Shortcut', or use 'Split Clip')");
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
        win.SourceInitialized += (_, _) => ApplyDarkTitleBar(win);
        win.ShowDialog();
    }

    private const string ShortcutsText =
        "IN-APP SHORTCUTS\n" +
        "  Arrow Keys       Move image / clip Up, Down, Left, Right\n" +
        "  Drag preview     Move image / clip freely with mouse\n" +
        "  [ / ]            Slow motion / Fast motion speed (-/+ 0.25x)\n" +
        "  Space            Play / Pause\n" +
        "  N / B            Next / Previous clip or image\n" +
        "  + / - / Wheel    3D Camera Dolly Zoom in / out\n" +
        "  0                Reset zoom and position\n" +
        "  S                Start / Stop virtual camera\n" +
        "  A                Toggle auto change\n" +
        "  L                Cycle loop mode\n" +
        "  F                Cycle fit mode\n" +
        "  Ctrl+O           Add files\n" +
        "  Ctrl+Up / Down   Move item up/down in playlist\n" +
        "  Delete           Remove selected item\n\n" +
        "GLOBAL SHORTCUTS (work in Chrome / Emulator / Zoom too)\n" +
        "  Ctrl+Alt+S       Start / Stop virtual camera\n" +
        "  Ctrl+Alt+N       Next clip or image\n" +
        "  Ctrl+Alt+B       Previous clip or image\n" +
        "  Ctrl+Alt+Space   Play / Pause\n" +
        "  Ctrl+Alt+Up      3D Camera Dolly in\n" +
        "  Ctrl+Alt+Down    3D Camera Dolly out\n" +
        "  Ctrl+Alt+0       Reset zoom & position\n" +
        "  Ctrl+Alt+L       Cycle loop mode";
}
