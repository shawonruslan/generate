using OpenCvSharp;
using System.Diagnostics;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MHVirtualCam;

/// <summary>
/// Playlist playback + frame rendering engine.
/// Supports full clips, split video segments (StartSec..EndSec), images,
/// any aspect ratio (1:1, 16:9, 9:16, 4:3, 3:4, 21:9) with safe clamped
/// Fill/Fit/Stretch + Zoom + Up/Down/Left/Right Pan framing.
/// </summary>
public sealed class FrameEngine : IDisposable
{
    public List<PlaylistItem> Playlist { get; } = new();
    public CameraSettings Settings { get; } = new();
    public int CurrentIndex { get; private set; } = -1;
    public bool IsPlaying { get; private set; }
    public bool IsStreaming { get; set; }              // virtual camera on/off
    public long FramesRendered { get; private set; }

    public event Action<BitmapSource>? PreviewFrame;   // raised on engine thread w/ frozen bitmap
    public event Action<int>? CurrentItemChanged;
    public event Action? PlaylistEnded;

    private readonly SharedMemoryWriter _shared = new();
    private Thread? _thread;
    private volatile bool _run;
    private VideoCapture? _capture;
    private Mat? _imageMat;
    private Mat? _lastFrame;                            // for fade transitions
    private Mat? _lastRaw;
    private DateTime _itemStartedUtc;
    private DateTime _videoNextFrameUtc;
    private double _videoFrameMs = 33.3;
    private readonly object _lock = new();

    // ------------------------------------------------------------- control
    public void Start()
    {
        if (_run) return;
        _run = true; IsPlaying = true;
        if (CurrentIndex < 0 && Playlist.Count > 0) LoadItem(0);
        _thread = new Thread(Loop) { IsBackground = true, Name = "MVC-FrameEngine" };
        _thread.Start();
    }

    public void Pause() => IsPlaying = false;
    public void Resume() { IsPlaying = true; _videoNextFrameUtc = DateTime.UtcNow; }
    public void StopAll() { _run = false; IsPlaying = false; _thread?.Join(500); ReleaseCurrent(); }

    public void Next()
    {
        if (Playlist.Count == 0) return;
        int n = CurrentIndex + 1;
        if (n >= Playlist.Count) n = Settings.Loop == LoopMode.None ? Playlist.Count - 1 : 0;
        LoadItem(n);
    }

    public void Previous()
    {
        if (Playlist.Count == 0) return;
        int n = CurrentIndex - 1;
        if (n < 0) n = Settings.Loop == LoopMode.None ? 0 : Playlist.Count - 1;
        LoadItem(n);
    }

    public void JumpTo(int index)
    {
        if (index >= 0 && index < Playlist.Count) LoadItem(index);
    }

    public void OnPlaylistChanged()
    {
        if (Playlist.Count == 0) { ReleaseCurrent(); CurrentIndex = -1; return; }
        if (CurrentIndex >= Playlist.Count) LoadItem(0);
        else if (CurrentIndex < 0) LoadItem(0);
    }

    public static double GetVideoDurationSeconds(string filePath)
    {
        try
        {
            using var cap = new VideoCapture(filePath);
            if (!cap.IsOpened()) return 0;
            double fps = cap.Get(VideoCaptureProperties.Fps);
            double frames = cap.Get(VideoCaptureProperties.FrameCount);
            if (fps > 0.1 && frames > 0) return frames / fps;
        }
        catch { }
        return 0;
    }

    // -------------------------------------------------------------- loading
    private void LoadItem(int index)
    {
        lock (_lock)
        {
            ReleaseCurrent();
            CurrentIndex = index;
            _itemStartedUtc = DateTime.UtcNow;
            _videoNextFrameUtc = DateTime.UtcNow;
            var item = Playlist[index];
            if (item.Kind == MediaKind.Image)
            {
                _imageMat = Cv2.ImRead(item.FilePath, ImreadModes.Color);
            }
            else
            {
                _capture = new VideoCapture(item.FilePath);
                if (_capture.IsOpened())
                {
                    double fps = _capture.Get(VideoCaptureProperties.Fps);
                    _videoFrameMs = fps > 1 ? 1000.0 / fps : 33.3;
                    if (item.StartSec.HasValue && item.StartSec.Value > 0)
                        _capture.Set(VideoCaptureProperties.PosMsec, item.StartSec.Value * 1000.0);
                }
                else
                {
                    _capture.Dispose();
                    _capture = null;
                }
            }
        }
        CurrentItemChanged?.Invoke(index);
    }

    private void ReleaseCurrent()
    {
        _capture?.Release(); _capture?.Dispose(); _capture = null;
        _imageMat?.Dispose(); _imageMat = null;
        _lastRaw?.Dispose(); _lastRaw = null;
    }

    // ---------------------------------------------------------------- loop
    private void Loop()
    {
        var sw = new Stopwatch();
        while (_run)
        {
            sw.Restart();
            try { Tick(); } catch { /* a bad file must never kill the camera */ }
            double targetMs = 1000.0 / Math.Max(1, Settings.Fps);
            int sleep = (int)(targetMs - sw.Elapsed.TotalMilliseconds);
            if (sleep > 1) Thread.Sleep(sleep);
        }
    }

    private void Tick()
    {
        if (CurrentIndex < 0 || CurrentIndex >= Playlist.Count) { PushBlank(); return; }
        var item = Playlist[CurrentIndex];
        Mat? src = null;

        lock (_lock)
        {
            if (item.Kind == MediaKind.Image)
            {
                src = _imageMat;
                if (src is null || src.Empty()) { PushBlank(); return; }
                if (IsPlaying && Settings.AutoAdvance &&
                    (DateTime.UtcNow - _itemStartedUtc).TotalSeconds >= Settings.ImageSeconds)
                { AdvanceAfterEnd(); return; }
            }
            else
            {
                if (_capture is null) { PushBlank(); return; }
                if (!IsPlaying)
                {
                    // Keep rendering paused frame so user can adjust ratio / zoom / pan live
                    if (_lastRaw is null || _lastRaw.Empty())
                    {
                        var first = new Mat();
                        if (_capture.Read(first) && !first.Empty()) _lastRaw = first;
                        else first.Dispose();
                    }
                    src = _lastRaw;
                }
                else if (DateTime.UtcNow < _videoNextFrameUtc && _lastRaw is not null && !_lastRaw.Empty())
                {
                    src = _lastRaw;
                }
                else
                {
                    var frame = new Mat();
                    bool hitEnd = !_capture.Read(frame) || frame.Empty();
                    if (!hitEnd && item.EndSec.HasValue)
                    {
                        double posMs = _capture.Get(VideoCaptureProperties.PosMsec);
                        if (posMs >= item.EndSec.Value * 1000.0) hitEnd = true;
                    }

                    if (hitEnd)
                    {
                        frame.Dispose();
                        if (Settings.Loop == LoopMode.LoopSingle)
                        {
                            if (item.StartSec.HasValue && item.StartSec.Value > 0)
                                _capture.Set(VideoCaptureProperties.PosMsec, item.StartSec.Value * 1000.0);
                            else
                                _capture.Set(VideoCaptureProperties.PosFrames, 0);
                            _videoNextFrameUtc = DateTime.UtcNow;
                            return;
                        }
                        AdvanceAfterEnd();
                        return;
                    }
                    _lastRaw?.Dispose(); _lastRaw = frame;
                    src = frame;
                    _videoNextFrameUtc = DateTime.UtcNow.AddMilliseconds(_videoFrameMs);
                }
            }
        }
        if (src is null || src.Empty()) { PushBlank(); return; }
        RenderAndPush(src);
    }

    private void AdvanceAfterEnd()
    {
        int next = CurrentIndex + 1;
        if (next >= Playlist.Count)
        {
            if (Settings.Loop == LoopMode.LoopPlaylist) next = 0;
            else { IsPlaying = false; PlaylistEnded?.Invoke(); return; }
        }
        if (Settings.AutoAdvance || Settings.Loop == LoopMode.LoopPlaylist)
            LoadItem(next);
        else { IsPlaying = false; PlaylistEnded?.Invoke(); }
    }

    // -------------------------------------------------------------- render
    private void PushBlank()
    {
        var (w, h) = Settings.Resolution;
        w = Math.Max(16, w); h = Math.Max(16, h);
        using var blank = new Mat(h, w, MatType.CV_8UC3, new Scalar(29, 29, 29));
        RenderAndPush(blank);
    }

    private void RenderAndPush(Mat srcBgr)
    {
        var (rawW, rawH) = Settings.Resolution;
        int outW = Math.Max(16, rawW);
        int outH = Math.Max(16, rawH);

        using var work = srcBgr.Channels() == 3 ? srcBgr.Clone() : ConvertToBgr(srcBgr);
        if (work.Width <= 0 || work.Height <= 0) return;

        // 1) Digital zoom + pan: crop a (src/zoom) window around pan offset.
        double zoom = Math.Clamp(Settings.Zoom, 1.0, 4.0);
        double panX = Math.Clamp(Settings.PanX, -1.0, 1.0);
        double panY = Math.Clamp(Settings.PanY, -1.0, 1.0);

        Mat cropped = work;
        bool ownCropped = false;
        if (zoom > 1.001)
        {
            int cw = Math.Clamp((int)Math.Round(work.Width / zoom), 1, work.Width);
            int ch = Math.Clamp((int)Math.Round(work.Height / zoom), 1, work.Height);
            int maxX = Math.Max(0, work.Width - cw);
            int maxY = Math.Max(0, work.Height - ch);
            int x = Math.Clamp((int)Math.Round((maxX / 2.0) * (1.0 + panX)), 0, maxX);
            int y = Math.Clamp((int)Math.Round((maxY / 2.0) * (1.0 + panY)), 0, maxY);
            cropped = new Mat(work, new Rect(x, y, cw, ch)).Clone();
            ownCropped = true;
        }

        // 2) Fit mode to the target ratio/resolution (strictly clamped for every ratio like 1:1).
        using var canvas = new Mat(outH, outW, MatType.CV_8UC3, ParseBg(Settings.BackgroundHex));
        if (Settings.Fit == FitMode.Stretch)
        {
            Cv2.Resize(cropped, canvas, new OpenCvSharp.Size(outW, outH), 0, 0, InterpolationFlags.Linear);
        }
        else if (Settings.Fit == FitMode.Fit)
        {
            double s = Math.Min((double)outW / cropped.Width, (double)outH / cropped.Height);
            int nw = Math.Clamp((int)Math.Round(cropped.Width * s), 1, outW);
            int nh = Math.Clamp((int)Math.Round(cropped.Height * s), 1, outH);
            int maxOffX = Math.Max(0, outW - nw);
            int maxOffY = Math.Max(0, outH - nh);
            int ox = Math.Clamp((int)Math.Round((maxOffX / 2.0) * (1.0 + panX)), 0, maxOffX);
            int oy = Math.Clamp((int)Math.Round((maxOffY / 2.0) * (1.0 + panY)), 0, maxOffY);
            using var resized = new Mat();
            Cv2.Resize(cropped, resized, new OpenCvSharp.Size(nw, nh), 0, 0, InterpolationFlags.Linear);
            using var roi = new Mat(canvas, new Rect(ox, oy, nw, nh));
            resized.CopyTo(roi);
        }
        else // Fill: crop source to target aspect (using PanX/PanY so user can frame Up/Down/Left/Right even at 100% zoom)
        {
            double targetAspect = (double)outW / outH;
            double srcAspect = (double)cropped.Width / cropped.Height;
            if (srcAspect > targetAspect)
            {
                int nw = Math.Clamp((int)Math.Round(cropped.Height * targetAspect), 1, cropped.Width);
                int maxX = Math.Max(0, cropped.Width - nw);
                int x = Math.Clamp((int)Math.Round((maxX / 2.0) * (1.0 + panX)), 0, maxX);
                using var c = new Mat(cropped, new Rect(x, 0, nw, cropped.Height));
                Cv2.Resize(c, canvas, new OpenCvSharp.Size(outW, outH), 0, 0, InterpolationFlags.Linear);
            }
            else
            {
                int nh = Math.Clamp((int)Math.Round(cropped.Width / targetAspect), 1, cropped.Height);
                int maxY = Math.Max(0, cropped.Height - nh);
                int y = Math.Clamp((int)Math.Round((maxY / 2.0) * (1.0 + panY)), 0, maxY);
                using var c = new Mat(cropped, new Rect(0, y, cropped.Width, nh));
                Cv2.Resize(c, canvas, new OpenCvSharp.Size(outW, outH), 0, 0, InterpolationFlags.Linear);
            }
        }
        if (ownCropped) cropped.Dispose();

        // 3) Optional fade: blend with previous output right after an item change.
        Mat output = canvas;
        if (Settings.Transition == TransitionKind.Fade && _lastFrame is not null &&
            _lastFrame.Width == canvas.Width && _lastFrame.Height == canvas.Height &&
            (DateTime.UtcNow - _itemStartedUtc).TotalMilliseconds < 220)
        {
            double a = Math.Clamp((DateTime.UtcNow - _itemStartedUtc).TotalMilliseconds / 220.0, 0.0, 1.0);
            var blended = new Mat();
            Cv2.AddWeighted(_lastFrame, 1.0 - a, canvas, a, 0, blended);
            output = blended;
        }
        _lastFrame?.Dispose();
        _lastFrame = output.Clone();

        // 4) To BGRA for shared memory + preview bitmap.
        using var bgra = new Mat();
        Cv2.CvtColor(output, bgra, ColorConversionCodes.BGR2BGRA);
        int bytes = outW * outH * 4;
        var buffer = new byte[bytes];
        System.Runtime.InteropServices.Marshal.Copy(bgra.Data, buffer, 0, bytes);

        if (IsStreaming)
            _shared.WriteFrame(buffer, outW, outH, Settings.Fps);
        else
            _shared.SetActive(false, outW, outH, Settings.Fps);

        var bitmap = BitmapSource.Create(outW, outH, 96, 96, PixelFormats.Bgra32, null, buffer, outW * 4);
        bitmap.Freeze();
        PreviewFrame?.Invoke(bitmap);
        FramesRendered++;
        if (!ReferenceEquals(output, canvas)) output.Dispose();
    }

    private static Mat ConvertToBgr(Mat src)
    {
        var dst = new Mat();
        if (src.Channels() == 4) Cv2.CvtColor(src, dst, ColorConversionCodes.BGRA2BGR);
        else if (src.Channels() == 1) Cv2.CvtColor(src, dst, ColorConversionCodes.GRAY2BGR);
        else src.CopyTo(dst);
        return dst;
    }

    private static Scalar ParseBg(string hex)
    {
        try
        {
            var c = (Color)ColorConverter.ConvertFromString(hex);
            return new Scalar(c.B, c.G, c.R); // OpenCV is BGR
        }
        catch { return new Scalar(0, 0, 0); }
    }

    public void Dispose()
    {
        StopAll();
        _lastFrame?.Dispose(); _lastRaw?.Dispose();
        _shared.Dispose();
    }
}
