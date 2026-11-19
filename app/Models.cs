using System.IO;

namespace MHVirtualCam;

public enum MediaKind { Image, Video }
public enum LoopMode { None, LoopPlaylist, LoopSingle }
public enum FitMode { Fill, Fit, Stretch }
public enum TransitionKind { Cut, Fade }

public sealed class PlaylistItem
{
    public required string FilePath { get; init; }
    public MediaKind Kind { get; init; }
    public string FileName => Path.GetFileName(FilePath);
    public string KindLabel => Kind == MediaKind.Image ? "IMAGE" : "VIDEO";

    private static readonly HashSet<string> ImageExts = new(StringComparer.OrdinalIgnoreCase)
        { ".jpg", ".jpeg", ".png", ".bmp", ".webp", ".gif", ".tif", ".tiff" };
    private static readonly HashSet<string> VideoExts = new(StringComparer.OrdinalIgnoreCase)
        { ".mp4", ".mov", ".avi", ".mkv", ".webm", ".wmv", ".m4v" };

    public static bool TryCreate(string path, out PlaylistItem? item)
    {
        item = null;
        var ext = Path.GetExtension(path);
        if (ImageExts.Contains(ext)) { item = new PlaylistItem { FilePath = path, Kind = MediaKind.Image }; return true; }
        if (VideoExts.Contains(ext)) { item = new PlaylistItem { FilePath = path, Kind = MediaKind.Video }; return true; }
        return false;
    }
    public static bool IsSupported(string path) => TryCreate(path, out _);
}

/// <summary>An aspect-ratio preset with the resolutions that exactly match it.</summary>
public sealed record RatioPreset(string Name, int RatioW, int RatioH, (int W, int H)[] Resolutions)
{
    public static readonly RatioPreset[] All =
    {
        new("16:9", 16, 9,  new[] { (1920,1080), (1280,720), (854,480) }),
        new("9:16",  9, 16, new[] { (1080,1920), (720,1280), (540,960) }),
        new("1:1",   1, 1,  new[] { (1080,1080), (720,720), (480,480) }),
        new("4:3",   4, 3,  new[] { (1440,1080), (1024,768), (640,480) }),
        new("3:4",   3, 4,  new[] { (1080,1440), (768,1024), (480,640) }),
        new("21:9", 21, 9,  new[] { (1680,720), (1280,548), (2560,1080) }),
    };
}

public sealed class CameraSettings
{
    public RatioPreset Ratio { get; set; } = RatioPreset.All[0];       // 16:9
    public (int W, int H) Resolution { get; set; } = (1280, 720);
    public int Fps { get; set; } = 30;
    public FitMode Fit { get; set; } = FitMode.Fill;
    public TransitionKind Transition { get; set; } = TransitionKind.Fade;
    public LoopMode Loop { get; set; } = LoopMode.LoopPlaylist;
    public bool AutoAdvance { get; set; } = true;
    public double ImageSeconds { get; set; } = 5.0;                    // slideshow hold per image
    public double Zoom { get; set; } = 1.0;                            // 1.0 .. 4.0
    public double PanX { get; set; } = 0.0;                            // -1 .. 1
    public double PanY { get; set; } = 0.0;                            // -1 .. 1
    public string BackgroundHex { get; set; } = "#000000";             // letterbox colour (Fit mode)
}
