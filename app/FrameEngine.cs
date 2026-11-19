using OpenCvSharp;
using System.Diagnostics;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MHVirtualCam;

/// <summary>
/// Playlist playback + frame rendering engine.
/// - Images are held for Settings.ImageSeconds when AutoAdvance is on.
/// - Videos play at their native pace; on end they loop (LoopSingle),
///   advance (AutoAdvance), and the playlist itself loops (LoopPlaylist).
/// - Every output frame is rendered at the selected ratio/resolution with
///   digital zoom + pan and the chosen fit mode, then pushed to shared
///   memory (virtual camera) and to the on-screen preview.
/// Runs on its own thread paced to Settings.Fps.
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
        _thread = new Thread(Loop) { IsBackground = true, Name = "SVC-FrameEngine" };
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
                double fps = _capture.Get(VideoCaptureProperties.Fps);
                _videoFrameMs = fps > 1 ? 1000.0 / fps : 33.3;
                if (!_capture.IsOpened()) { _capture.Dispose(); _capture = null; }
            }
        }
        CurrentItemChanged?.Invoke(index);
    }

    private void ReleaseCurrent()
    {
        _capture?.Release(); _capture?.Dispose(); _capture = null;
        _imageMat?.Dispose(); _imageMat = null;
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
        if (!IsPlaying || CurrentIndex < 0 || CurrentIndex >= Playlist.Count) { PushBlank(); return; }
        var item = Playlist[CurrentIndex];
        Mat? src = null;
        bool ownSrc = false;

        lock (_lock)
        {
            if (item.Kind == MediaKind.Image)
            {
                src = _imageMat;
                if (src is null) { PushBlank(); return; }
                if (Settings.AutoAdvance &&
                    (DateTime.UtcNow - _itemStartedUtc).TotalSeconds >= Settings.ImageSeconds)
                { AdvanceAfterEnd(single: false); return; }
            }
            else
            {
                if (_capture is null) { PushBlank(); return; }
                if (DateTime.UtcNow < _videoNextFrameUtc) { src = _lastRaw; }
                else
                {
                    var frame = new Mat();
                    if (!_capture.Read(frame) || frame.Empty())
                    {
                        frame.Dispose();
                        if (Settings.Loop == LoopMode.LoopSingle)
                        { _capture.Set(VideoCaptureProperties.PosFrames, 0); _videoNextFrameUtc = DateTime.UtcNow; return; }
                        AdvanceAfterEnd(single: false);
                        return;
                    }
                    _lastRaw?.Dispose(); _lastRaw = frame;
                    src = frame; ownSrc = false;
                    _videoNextFrameUtc = DateTime.UtcNow.AddMilliseconds(_videoFrameMs);
                }
            }
        }
        if (src is null || src.Empty()) { PushBlank(); return; }
        RenderAndPush(src);
        if (ownSrc) src.Dispose();
    }

    private Mat? _lastRaw;

    private void AdvanceAfterEnd(bool single)
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
        using var blank = new Mat(h, w, MatType.CV_8UC3, new Scalar(29, 29, 29));
        RenderAndPush(blank, skipTransform: false);
    }

    private void RenderAndPush(Mat srcBgr, bool skipTransform = false)
    {
        var (outW, outH) = Settings.Resolution;
        using var work = srcBgr.Clone();

        // 1) Digital zoom + pan: crop a (src/zoom) window around the pan centre.
        double zoom = Math.Clamp(Settings.Zoom, 1.0, 4.0);
        Mat cropped = work;
        bool ownCropped = false;
        if (zoom > 1.001)
        {
            int cw = (int)(work.Width / zoom), ch = (int)(work.Height / zoom);
            double cx = work.Width / 2.0 + Settings.PanX * (work.Width - cw) / 2.0;
            double cy = work.Height / 2.0 + Settings.PanY * (work.Height - ch) / 2.0;
            int x = (int)Math.Clamp(cx - cw / 2.0, 0, work.Width - cw);
            int y = (int)Math.Clamp(cy - ch / 2.0, 0, work.Height - ch);
            cropped = new Mat(work, new Rect(x, y, cw, ch)).Clone();
            ownCropped = true;
        }

        // 2) Fit mode to the target ratio/resolution.
        using var canvas = new Mat(outH, outW, MatType.CV_8UC3, ParseBg(Settings.BackgroundHex));
        if (Settings.Fit == FitMode.Stretch)
        {
            Cv2.Resize(cropped, canvas, new OpenCvSharp.Size(outW, outH), 0, 0, InterpolationFlags.Linear);
        }
        else if (Settings.Fit == FitMode.Fit)
        {
            double s = Math.Min((double)outW / cropped.Width, (double)outH / cropped.Height);
            int nw = Math.Max(1, (int)(cropped.Width * s)), nh = Math.Max(1, (int)(cropped.Height * s));
            using var resized = new Mat();
            Cv2.Resize(cropped, resized, new OpenCvSharp.Size(nw, nh), 0, 0, InterpolationFlags.Linear);
            resized.CopyTo(new Mat(canvas, new Rect((outW - nw) / 2, (outH - nh) / 2, nw, nh)));
        }
        else // Fill: crop source to target aspect, then resize (no bars).
        {
            double targetAspect = (double)outW / outH;
            double srcAspect = (double)cropped.Width / cropped.Height;
            using var fillSrc = cropped.Clone();
            if (srcAspect > targetAspect)
            {
                int nw = (int)(cropped.Height * targetAspect);
                int x = (cropped.Width - nw) / 2;
                using var c = new Mat(cropped, new Rect(x, 0, nw, cropped.Height));
                Cv2.Resize(c, canvas, new OpenCvSharp.Size(outW, outH), 0, 0, InterpolationFlags.Linear);
            }
            else
            {
                int nh = (int)(cropped.Width / targetAspect);
                int y = (cropped.Height - nh) / 2;
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
            double a = (DateTime.UtcNow - _itemStartedUtc).TotalMilliseconds / 220.0;
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
