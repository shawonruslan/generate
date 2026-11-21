using NAudio.Wave;

namespace MHVirtualCam;

/// <summary>
/// Plays video clip audio tracks and optional background music/sound files
/// to any selected Windows audio output device (Speakers, Headphones, or
/// Virtual Audio Cable like VB-Cable to route audio into browser/emulator mic).
/// </summary>
public sealed class AudioEngine : IDisposable
{
    private readonly object _lock = new();

    private WaveOutEvent? _videoOut;
    private MediaFoundationReader? _videoReader;
    private string? _videoPath;
    private float _videoVolume = 0.85f;
    private bool _videoMuted;

    private WaveOutEvent? _musicOut;
    private MediaFoundationReader? _musicReader;
    private string? _musicPath;
    private float _musicVolume = 0.50f;
    private bool _musicLoop = true;
    private bool _musicPlaying;

    private int _deviceNumber = -1; // -1 = Windows Default

    public static List<(int DeviceId, string Name)> GetOutputDevices()
    {
        var list = new List<(int, string)> { (-1, "Default Audio Output") };
        try
        {
            int count = WaveOut.DeviceCount;
            for (int i = 0; i < count; i++)
            {
                var caps = WaveOut.GetCapabilities(i);
                list.Add((i, caps.ProductName));
            }
        }
        catch { }
        return list;
    }

    public void SetOutputDevice(int deviceNumber)
    {
        lock (_lock)
        {
            if (_deviceNumber == deviceNumber) return;
            _deviceNumber = deviceNumber;
            // Restart active streams on the newly selected device
            if (_videoPath is not null && _videoOut is not null)
            {
                double pos = _videoReader?.CurrentTime.TotalSeconds ?? 0;
                bool wasPlaying = _videoOut.PlaybackState == PlaybackState.Playing;
                LoadVideoAudioLocked(_videoPath, pos, wasPlaying);
            }
            if (_musicPath is not null && _musicOut is not null)
            {
                double pos = _musicReader?.CurrentTime.TotalSeconds ?? 0;
                bool wasPlaying = _musicPlaying;
                LoadMusicLocked(_musicPath, pos, wasPlaying);
            }
        }
    }

    // --------------------------------------------------------- Video Audio
    public void LoadVideoAudio(string? filePath, double startSec, bool play)
    {
        lock (_lock)
        {
            if (string.IsNullOrEmpty(filePath))
            {
                StopVideoAudioLocked();
                _videoPath = null;
                return;
            }
            LoadVideoAudioLocked(filePath, startSec, play);
        }
    }

    private void LoadVideoAudioLocked(string filePath, double startSec, bool play)
    {
        StopVideoAudioLocked();
        _videoPath = filePath;
        try
        {
            _videoReader = new MediaFoundationReader(filePath);
            if (startSec > 0 && _videoReader.TotalTime.TotalSeconds > startSec)
                _videoReader.CurrentTime = TimeSpan.FromSeconds(startSec);

            _videoOut = new WaveOutEvent { DeviceNumber = _deviceNumber, DesiredLatency = 120 };
            _videoOut.Init(_videoReader);
            _videoOut.Volume = _videoMuted ? 0f : _videoVolume;
            if (play) _videoOut.Play();
        }
        catch
        {
            // Video has no audio track or unsupported audio stream — fail silently
            StopVideoAudioLocked();
        }
    }

    public void SeekVideoAudio(double startSec, bool play)
    {
        lock (_lock)
        {
            if (_videoReader is null || _videoOut is null) return;
            try
            {
                _videoReader.CurrentTime = TimeSpan.FromSeconds(Math.Max(0, startSec));
                if (play && _videoOut.PlaybackState != PlaybackState.Playing) _videoOut.Play();
            }
            catch { }
        }
    }

    public void PauseVideoAudio()
    {
        lock (_lock) { try { _videoOut?.Pause(); } catch { } }
    }

    public void ResumeVideoAudio()
    {
        lock (_lock) { try { _videoOut?.Play(); } catch { } }
    }

    public void SetVideoVolume(double volume01)
    {
        lock (_lock)
        {
            _videoVolume = (float)Math.Clamp(volume01, 0.0, 1.0);
            if (_videoOut is not null) _videoOut.Volume = _videoMuted ? 0f : _videoVolume;
        }
    }

    public void SetVideoMuted(bool muted)
    {
        lock (_lock)
        {
            _videoMuted = muted;
            if (_videoOut is not null) _videoOut.Volume = _videoMuted ? 0f : _videoVolume;
        }
    }

    private void StopVideoAudioLocked()
    {
        try { _videoOut?.Stop(); } catch { }
        _videoOut?.Dispose(); _videoOut = null;
        _videoReader?.Dispose(); _videoReader = null;
    }

    // --------------------------------------------------- Background Music
    public bool IsMusicPlaying => _musicPlaying;
    public string? CurrentMusicName => string.IsNullOrEmpty(_musicPath) ? null : System.IO.Path.GetFileName(_musicPath);

    public bool LoadAndPlayMusic(string filePath)
    {
        lock (_lock)
        {
            return LoadMusicLocked(filePath, 0, true);
        }
    }

    private bool LoadMusicLocked(string filePath, double startSec, bool play)
    {
        StopMusicLocked();
        _musicPath = filePath;
        try
        {
            _musicReader = new MediaFoundationReader(filePath);
            if (startSec > 0 && _musicReader.TotalTime.TotalSeconds > startSec)
                _musicReader.CurrentTime = TimeSpan.FromSeconds(startSec);

            _musicOut = new WaveOutEvent { DeviceNumber = _deviceNumber, DesiredLatency = 120 };
            _musicOut.PlaybackStopped += OnMusicStopped;
            _musicOut.Init(_musicReader);
            _musicOut.Volume = _musicVolume;
            if (play)
            {
                _musicOut.Play();
                _musicPlaying = true;
            }
            return true;
        }
        catch
        {
            StopMusicLocked();
            _musicPath = null;
            return false;
        }
    }

    private void OnMusicStopped(object? sender, StoppedEventArgs e)
    {
        lock (_lock)
        {
            if (!_musicPlaying || !_musicLoop || _musicReader is null || _musicOut is null) return;
            try
            {
                if (_musicReader.Position >= _musicReader.Length - 1024)
                {
                    _musicReader.Position = 0;
                    _musicOut.Play();
                }
            }
            catch { }
        }
    }

    public void ToggleMusic()
    {
        lock (_lock)
        {
            if (_musicOut is null) return;
            try
            {
                if (_musicPlaying) { _musicOut.Pause(); _musicPlaying = false; }
                else { _musicOut.Play(); _musicPlaying = true; }
            }
            catch { }
        }
    }

    public void StopMusic()
    {
        lock (_lock) { StopMusicLocked(); _musicPath = null; }
    }

    public void SetMusicVolume(double volume01)
    {
        lock (_lock)
        {
            _musicVolume = (float)Math.Clamp(volume01, 0.0, 1.0);
            if (_musicOut is not null) _musicOut.Volume = _musicVolume;
        }
    }

    public void SetMusicLoop(bool loop)
    {
        lock (_lock) { _musicLoop = loop; }
    }

    private void StopMusicLocked()
    {
        _musicPlaying = false;
        if (_musicOut is not null) _musicOut.PlaybackStopped -= OnMusicStopped;
        try { _musicOut?.Stop(); } catch { }
        _musicOut?.Dispose(); _musicOut = null;
        _musicReader?.Dispose(); _musicReader = null;
    }

    public void Dispose()
    {
        lock (_lock)
        {
            StopVideoAudioLocked();
            StopMusicLocked();
        }
    }
}
