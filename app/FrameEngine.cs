using OpenCvSharp;
using System.Diagnostics;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MHVirtualCam;

/// <summary>
/// Playlist playback + frame rendering engine.
/// Supports full clips, split video segments (StartSec..EndSec), images,
/// synchronized video audio (via AudioEngine), slow/fast motion (0.25x..3.0x),
/// unrestricted Up/Down/Left/Right positioning, and realistic 3D Camera Dolly
/// zoom (smooth eased zoom, 3D perspective tilt, handheld breathing, edge DOF).
/// </summary>
public sealed class FrameEngine : IDisposable
{
    public List<PlaylistItem> Playlist { get; } = new();
    public CameraSettings Settings { get; } = new();
    public AudioEngine Audio { get; } = new();
    public int CurrentIndex { get; private set; } = -1;
    public bool IsPlaying { get; private set; }
    public bool IsStreaming { get; set; }              // virtual camera on/off
    public long FramesRendered { get; private set; }

    public event Action<BitmapSource>? PreviewFrame;   // raised on engine thread w/ frozen bitmap
    public event Action<int>? CurrentItemChanged;
    public event Action? PlaylistEnded;

    private readonly SharedMemoryWriter _shared = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private Thread? _thread;
    private volatile bool _run;
    private VideoCapture? _capture;
    private Mat? _imageMat;
    private Mat? _lastFrame;                            // for fade transitions
    private Mat? _lastRaw;
    private DateTime _itemStartedUtc;
    private DateTime _lastVideoTickUtc;
    private double _videoFrameMs = 33.3;
    private double _videoFrameAccum;
    private readonly object _lock = new();

    // Smooth 3D camera state (eased dolly zoom + pan)
    private double _curZoom = 1.0;
    private double _curPanX = 0.0;
    private double _curPanY = 0.0;

    // Cached radial vignette / edge-DOF masks per resolution
    private int _maskW, _maskH;
    private Mat? _edgeMask3C;     // CV_32FC3: 0 at center -> 1 at corners
    private Mat? _vignetteMask3C; // CV_32FC3: 1 at center -> ~0.82 at corners

    // ------------------------------------------------------------- control
    public void Start()
    {
        if (_run) return;
        _run = true; IsPlaying = true;
        if (CurrentIndex < 0 && Playlist.Count > 0) LoadItem(0);
        _thread = new Thread(Loop) { IsBackground = true, Name = "MVC-FrameEngine" };
        _thread.Start();
    }

    public void Pause()
    {
        IsPlaying = false;
        Audio.PauseVideoAudio();
    }

    public void Resume()
    {
        IsPlaying = true;
        _lastVideoTickUtc = DateTime.UtcNow;
        _videoFrameAccum = 0;
        Audio.ResumeVideoAudio();
    }

    public void StopAll()
    {
        _run = false;
        IsPlaying = false;
        _thread?.Join(500);
        ReleaseCurrent();
    }

    /// <summary>Clears transition history so switching ratio/resolution never blends or smears old frames.</summary>
    public void ResetRenderState()
    {
        lock (_lock)
        {
            _lastFrame?.Dispose();
            _lastFrame = null;
        }
    }

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
            _lastVideoTickUtc = DateTime.UtcNow;
            _videoFrameAccum = 1.0;
            var item = Playlist[index];
            if (item.Kind == MediaKind.Image)
            {
                _imageMat = Cv2.ImRead(item.FilePath, ImreadModes.Color);
                Audio.LoadVideoAudio(null, 0, false);
            }
            else
            {
                _capture = new VideoCapture(item.FilePath);
                if (_capture.IsOpened())
                {
                    double fps = _capture.Get(VideoCaptureProperties.Fps);
                    _videoFrameMs = fps > 1 ? 1000.0 / fps : 33.3;
                    double startSec = item.StartSec ?? 0;
                    if (startSec > 0)
                        _capture.Set(VideoCaptureProperties.PosMsec, startSec * 1000.0);
                    Audio.LoadVideoAudio(item.FilePath, startSec, IsPlaying);
                }
                else
                {
                    _capture.Dispose();
                    _capture = null;
                    Audio.LoadVideoAudio(null, 0, false);
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
        Audio.LoadVideoAudio(null, 0, false);
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
                    if (_lastRaw is null || _lastRaw.Empty())
                    {
                        var first = new Mat();
                        if (_capture.Read(first) && !first.Empty()) _lastRaw = first;
                        else first.Dispose();
                    }
                    src = _lastRaw;
                }
                else
                {
                    var now = DateTime.UtcNow;
                    double elapsedMs = Math.Clamp((now - _lastVideoTickUtc).TotalMilliseconds, 0, 250);
                    _lastVideoTickUtc = now;

                    double speed = Math.Clamp(Settings.PlaybackSpeed, 0.25, 3.0);
                    _videoFrameAccum += (elapsedMs * speed) / Math.Max(1.0, _videoFrameMs);

                    int advance = (int)Math.Floor(_videoFrameAccum);
                    if (advance <= 0 && _lastRaw is not null && !_lastRaw.Empty())
                    {
                        src = _lastRaw;
                    }
                    else
                    {
                        if (advance <= 0) advance = 1;
                        _videoFrameAccum = Math.Max(0, _videoFrameAccum - advance);
                        if (advance > 8) advance = 8;

                        bool hitEnd = false;
                        for (int s = 0; s < advance - 1; s++)
                        {
                            if (!_capture.Grab()) { hitEnd = true; break; }
                            if (item.EndSec.HasValue && _capture.Get(VideoCaptureProperties.PosMsec) >= item.EndSec.Value * 1000.0)
                            { hitEnd = true; break; }
                        }

                        var frame = new Mat();
                        if (!hitEnd)
                        {
                            if (!_capture.Read(frame) || frame.Empty()) hitEnd = true;
                            else if (item.EndSec.HasValue && _capture.Get(VideoCaptureProperties.PosMsec) >= item.EndSec.Value * 1000.0)
                                hitEnd = true;
                        }

                        if (hitEnd)
                        {
                            frame.Dispose();
                            if (Settings.Loop == LoopMode.LoopSingle)
                            {
                                double startSec = item.StartSec ?? 0;
                                if (startSec > 0)
                                    _capture.Set(VideoCaptureProperties.PosMsec, startSec * 1000.0);
                                else
                                    _capture.Set(VideoCaptureProperties.PosFrames, 0);
                                Audio.SeekVideoAudio(startSec, IsPlaying);
                                _lastVideoTickUtc = DateTime.UtcNow;
                                _videoFrameAccum = 1.0;
                                return;
                            }
                            AdvanceAfterEnd();
                            return;
                        }
                        _lastRaw?.Dispose(); _lastRaw = frame;
                        src = frame;
                    }
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
            else { IsPlaying = false; Audio.PauseVideoAudio(); PlaylistEnded?.Invoke(); return; }
        }
        if (Settings.AutoAdvance || Settings.Loop == LoopMode.LoopPlaylist)
            LoadItem(next);
        else { IsPlaying = false; Audio.PauseVideoAudio(); PlaylistEnded?.Invoke(); }
    }

    // -------------------------------------------------------------- render
    private void PushBlank()
    {
        var (w, h) = Settings.Resolution;
        w = Math.Max(16, w); h = Math.Max(16, h);
        using var blank = new Mat(h, w, MatType.CV_8UC3, new Scalar(29, 29, 29));
        RenderAndPush(blank, allow3D: false);
    }

    private void RenderAndPush(Mat srcBgr, bool allow3D = true)
    {
        var (rawW, rawH) = Settings.Resolution;
        int outW = Math.Max(16, rawW);
        int outH = Math.Max(16, rawH);
        double targetZoom = Math.Clamp(Settings.Zoom, 1.0, 4.0);
        double targetPanX = Math.Clamp(Settings.PanX, -1.0, 1.0);
        double targetPanY = Math.Clamp(Settings.PanY, -1.0, 1.0);
        bool use3D = allow3D && Settings.Camera3DEnabled;
        double depth = Math.Clamp(Settings.Camera3DDepth, 0.0, 1.0);
        double motion = Math.Clamp(Settings.Camera3DMotion, 0.0, 1.0);
        FitMode fit = Settings.Fit;
        string bgHex = Settings.BackgroundHex;
        int fps = Settings.Fps;

        // Smooth camera dolly interpolation when 3D Camera Mode is enabled
        if (use3D)
        {
            const double ease = 0.22;
            _curZoom += (targetZoom - _curZoom) * ease;
            _curPanX += (targetPanX - _curPanX) * ease;
            _curPanY += (targetPanY - _curPanY) * ease;
        }
        else
        {
            _curZoom = targetZoom;
            _curPanX = targetPanX;
            _curPanY = targetPanY;
        }

        double t = _clock.Elapsed.TotalSeconds;
        double swayX = use3D ? (Math.Sin(t * 0.85) * 0.012 + Math.Sin(t * 1.92) * 0.004) * motion : 0.0;
        double swayY = use3D ? (Math.Cos(t * 0.68) * 0.010 + Math.Sin(t * 1.45) * 0.003) * motion : 0.0;
        double swayZ = use3D ? (Math.Sin(t * 0.52) * 0.020 * motion) : 0.0;

        // Slight overscan when 3D tilt/motion is active so perspective edges stay clean
        double overscan = use3D ? (1.0 + 0.045 * depth + 0.025 * motion) : 1.0;
        double effZoom = Math.Clamp(_curZoom * overscan + swayZ, 1.0, 4.5);
        double effPanX = Math.Clamp(_curPanX + swayX, -1.0, 1.0);
        double effPanY = Math.Clamp(_curPanY + swayY, -1.0, 1.0);

        using var work = srcBgr.Channels() == 3 ? srcBgr.Clone() : ConvertToBgr(srcBgr);
        int srcW = work.Width, srcH = work.Height;
        if (srcW <= 0 || srcH <= 0) return;

        // 1) Compute scaled size based on Fit mode + Zoom
        double baseW, baseH;
        if (fit == FitMode.Stretch)
        {
            baseW = outW;
            baseH = outH;
        }
        else if (fit == FitMode.Fit)
        {
            double s = Math.Min((double)outW / srcW, (double)outH / srcH);
            baseW = srcW * s;
            baseH = srcH * s;
        }
        else // Fill
        {
            double s = Math.Max((double)outW / srcW, (double)outH / srcH);
            baseW = srcW * s;
            baseH = srcH * s;
        }

        double scaledW = Math.Max(1.0, baseW * effZoom);
        double scaledH = Math.Max(1.0, baseH * effZoom);

        // 2) Apply unrestricted Up/Down/Left/Right Pan offset
        double rangeX = Math.Max(outW * 0.75, Math.Abs(scaledW - outW) / 2.0);
        double rangeY = Math.Max(outH * 0.75, Math.Abs(scaledH - outH) / 2.0);
        double dstLeft = (outW - scaledW) / 2.0 + effPanX * rangeX;
        double dstTop  = (outH - scaledH) / 2.0 + effPanY * rangeY;

        using var canvas = new Mat(outH, outW, MatType.CV_8UC3, ParseBg(bgHex));

        int dx0 = Math.Clamp((int)Math.Round(dstLeft), 0, outW);
        int dy0 = Math.Clamp((int)Math.Round(dstTop), 0, outH);
        int dx1 = Math.Clamp((int)Math.Round(dstLeft + scaledW), 0, outW);
        int dy1 = Math.Clamp((int)Math.Round(dstTop + scaledH), 0, outH);
        int dw = dx1 - dx0;
        int dh = dy1 - dy0;

        if (dw > 0 && dh > 0)
        {
            int sx0 = Math.Clamp((int)Math.Floor((dx0 - dstLeft) * srcW / scaledW), 0, srcW - 1);
            int sy0 = Math.Clamp((int)Math.Floor((dy0 - dstTop) * srcH / scaledH), 0, srcH - 1);
            int sx1 = Math.Clamp((int)Math.Ceiling((dx1 - dstLeft) * srcW / scaledW), sx0 + 1, srcW);
            int sy1 = Math.Clamp((int)Math.Ceiling((dy1 - dstTop) * srcH / scaledH), sy0 + 1, srcH);

            using var srcRoi = new Mat(work, new Rect(sx0, sy0, sx1 - sx0, sy1 - sy0));
            using var dstRoi = new Mat(canvas, new Rect(dx0, dy0, dw, dh));
            Cv2.Resize(srcRoi, dstRoi, new OpenCvSharp.Size(dw, dh), 0, 0, InterpolationFlags.Linear);
        }

        // 3) 3D Camera Perspective + Depth-of-Field Edge Bokeh + Optical Vignette
        Mat staged = canvas;
        bool ownStaged = false;
        if (use3D && (depth > 0.01 || motion > 0.01))
        {
            staged = Apply3DCameraOptics(canvas, outW, outH, _curZoom, _curPanX, _curPanY, depth, motion, t);
            ownStaged = true;
        }

        // 4) Optional fade: only blend if previous frame has identical dimensions
        Mat output = staged;
        bool ownOutput = false;
        lock (_lock)
        {
            if (Settings.Transition == TransitionKind.Fade && _lastFrame is not null &&
                _lastFrame.Width == staged.Width && _lastFrame.Height == staged.Height &&
                (DateTime.UtcNow - _itemStartedUtc).TotalMilliseconds < 220)
            {
                double a = Math.Clamp((DateTime.UtcNow - _itemStartedUtc).TotalMilliseconds / 220.0, 0.0, 1.0);
                var blended = new Mat();
                Cv2.AddWeighted(_lastFrame, 1.0 - a, staged, a, 0, blended);
                output = blended;
                ownOutput = true;
            }
            _lastFrame?.Dispose();
            _lastFrame = output.Clone();
        }

        // 5) To BGRA for shared memory + preview bitmap
        using var bgra = new Mat();
        Cv2.CvtColor(output, bgra, ColorConversionCodes.BGR2BGRA);
        int bytes = outW * outH * 4;
        var buffer = new byte[bytes];
        System.Runtime.InteropServices.Marshal.Copy(bgra.Data, buffer, 0, bytes);

        if (IsStreaming)
            _shared.WriteFrame(buffer, outW, outH, fps);
        else
            _shared.SetActive(false, outW, outH, fps);

        var bitmap = BitmapSource.Create(outW, outH, 96, 96, PixelFormats.Bgra32, null, buffer, outW * 4);
        bitmap.Freeze();
        PreviewFrame?.Invoke(bitmap);
        FramesRendered++;

        if (ownOutput) output.Dispose();
        if (ownStaged) staged.Dispose();
    }

    private Mat Apply3DCameraOptics(Mat src, int w, int h, double zoom, double panX, double panY, double depth, double motion, double t)
    {
        EnsureOpticalMasks(w, h);

        // 3D perspective tilt driven by dolly zoom + pan + subtle live camera micro-tilt
        double zoomRatio = Math.Clamp((zoom - 1.0) / 3.0, 0.0, 1.0);
        double yaw = (panX * 0.045 + Math.Sin(t * 0.72) * 0.012 * motion) * depth;
        double pitch = (panY * 0.040 + Math.Cos(t * 0.58) * 0.010 * motion - zoomRatio * 0.028) * depth;
        double dollyBulge = zoomRatio * 0.032 * depth;

        // Compute 4-point perspective quad mimicking physical camera push-in / tilt
        float fw = w, fh = h;
        var srcPts = new[]
        {
            new Point2f(0, 0),
            new Point2f(fw, 0),
            new Point2f(fw, fh),
            new Point2f(0, fh)
        };

        float topInset    = (float)((pitch + dollyBulge) * fw);
        float bottomInset = (float)((-pitch + dollyBulge * 0.25) * fw);
        float leftInset   = (float)((yaw) * fh);
        float rightInset  = (float)((-yaw) * fh);

        var dstPts = new[]
        {
            new Point2f(Math.Max(0, -topInset), Math.Max(0, -leftInset)),
            new Point2f(fw - Math.Max(0, -topInset), Math.Max(0, -rightInset)),
            new Point2f(fw - Math.Max(0, -bottomInset), fh - Math.Max(0, -rightInset)),
            new Point2f(Math.Max(0, -bottomInset), fh - Math.Max(0, -leftInset))
        };

        // Map inward source corners to full output so there are never black perspective triangles
        var cropPts = new[]
        {
            new Point2f(Math.Clamp(topInset, 0, fw * 0.12f), Math.Clamp(leftInset, 0, fh * 0.12f)),
            new Point2f(fw - Math.Clamp(topInset, 0, fw * 0.12f), Math.Clamp(rightInset, 0, fh * 0.12f)),
            new Point2f(fw - Math.Clamp(bottomInset, 0, fw * 0.12f), fh - Math.Clamp(rightInset, 0, fh * 0.12f)),
            new Point2f(Math.Clamp(bottomInset, 0, fw * 0.12f), fh - Math.Clamp(leftInset, 0, fh * 0.12f))
        };
        _ = dstPts;

        var warped = new Mat();
        using (var H = Cv2.GetPerspectiveTransform(cropPts, srcPts))
        {
            Cv2.WarpPerspective(src, warped, H, new OpenCvSharp.Size(w, h), InterpolationFlags.Linear, BorderTypes.Replicate);
        }

        // Shallow depth-of-field edge blur that strengthens naturally as camera moves closer (zoom > 1)
        double dofStrength = Math.Clamp((0.18 + zoomRatio * 0.82) * depth, 0.0, 0.85);
        if (dofStrength > 0.05 && _edgeMask3C is not null && _vignetteMask3C is not null)
        {
            int ksize = (int)(3 + Math.Round(dofStrength * 6)) * 2 + 1; // odd 7..17
            using var blurred = new Mat();
            Cv2.GaussianBlur(warped, blurred, new OpenCvSharp.Size(ksize, ksize), 0);

            using var sharpF = new Mat();
            using var blurF = new Mat();
            warped.ConvertTo(sharpF, MatType.CV_32FC3);
            blurred.ConvertTo(blurF, MatType.CV_32FC3);

            // blend = sharp * (1 - dofStrength * edgeMask) + blur * (dofStrength * edgeMask)
            using var diff = new Mat();
            Cv2.Subtract(blurF, sharpF, diff);
            using var weightedDiff = new Mat();
            Cv2.Multiply(diff, _edgeMask3C, weightedDiff, dofStrength);
            Cv2.Add(sharpF, weightedDiff, sharpF);

            // Subtle optical lens vignette
            Cv2.Multiply(sharpF, _vignetteMask3C, sharpF);
            sharpF.ConvertTo(warped, MatType.CV_8UC3);
        }

        return warped;
    }

    private void EnsureOpticalMasks(int w, int h)
    {
        if (_maskW == w && _maskH == h && _edgeMask3C is not null && _vignetteMask3C is not null) return;
        _edgeMask3C?.Dispose();
        _vignetteMask3C?.Dispose();
        _maskW = w;
        _maskH = h;

        using var edge1 = new Mat(h, w, MatType.CV_32FC1);
        using var vig1 = new Mat(h, w, MatType.CV_32FC1);
        float cx = w * 0.5f, cy = h * 0.5f;
        float invRx = 1.0f / Math.Max(1f, cx);
        float invRy = 1.0f / Math.Max(1f, cy);

        for (int y = 0; y < h; y++)
        {
            float dy = (y - cy) * invRy;
            float dy2 = dy * dy;
            for (int x = 0; x < w; x++)
            {
                float dx = (x - cx) * invRx;
                float r = MathF.Sqrt(dx * dx + dy2); // 0 at center, ~1.414 at corners
                float dof = Math.Clamp((r - 0.52f) / 0.75f, 0f, 1f);
                edge1.Set(y, x, dof * dof);
                float vig = 1.0f - Math.Clamp((r - 0.55f) * 0.18f, 0f, 0.16f);
                vig1.Set(y, x, vig);
            }
        }

        _edgeMask3C = new Mat();
        _vignetteMask3C = new Mat();
        Cv2.CvtColor(edge1, _edgeMask3C, ColorConversionCodes.GRAY2BGR);
        Cv2.CvtColor(vig1, _vignetteMask3C, ColorConversionCodes.GRAY2BGR);
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
        _edgeMask3C?.Dispose(); _vignetteMask3C?.Dispose();
        Audio.Dispose();
        _shared.Dispose();
    }
}
