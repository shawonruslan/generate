using System.IO;
using System.IO.MemoryMappedFiles;

namespace MHVirtualCam;

/// <summary>
/// Owns the shared-memory frame buffers read by:
///  1) DirectShow filter (Local\MHVirtualCamFrame)
///  2) Windows 11 Media Foundation Virtual Camera running in FrameServer
///     as LocalService (%ProgramData%\MHVirtualCam\frame.shm)
/// Header layout must stay byte-identical with filter/sharedmem.h.
/// </summary>
public sealed class SharedMemoryWriter : IDisposable
{
    public const string MapName = @"Local\MHVirtualCamFrame";
    private const int HeaderSize = 256;
    private const int MaxW = 3840, MaxH = 2160;
    private const uint Magic = 0x4D485643; // "MHVC"
    private const long TotalBytes = HeaderSize + (long)MaxW * MaxH * 4;

    private readonly MemoryMappedFile _mmf;
    private readonly MemoryMappedViewAccessor _view;

    private FileStream? _fileStream;
    private MemoryMappedFile? _fileMmf;
    private MemoryMappedViewAccessor? _fileView;

    private long _frameNumber;

    // Header offsets (see MVCFrameHeader in sharedmem.h)
    private const int OffMagic = 0, OffWidth = 4, OffHeight = 8, OffFps = 12,
                      OffActive = 16, OffFrameLo = 20, OffFrameHi = 24, OffWriting = 28;

    public SharedMemoryWriter()
    {
        _mmf = MemoryMappedFile.CreateOrOpen(MapName, TotalBytes, MemoryMappedFileAccess.ReadWrite);
        _view = _mmf.CreateViewAccessor(0, TotalBytes, MemoryMappedFileAccess.ReadWrite);
        _view.Write(OffMagic, Magic);

        TryOpenCrossSessionFile();
        SetActive(false, 1280, 720, 30);
    }

    private void TryOpenCrossSessionFile()
    {
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "MHVirtualCam");
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, "frame.shm");
            _fileStream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite | FileShare.Delete);
            if (_fileStream.Length < TotalBytes) _fileStream.SetLength(TotalBytes);
            _fileMmf = MemoryMappedFile.CreateFromFile(
                _fileStream, null, TotalBytes, MemoryMappedFileAccess.ReadWrite, HandleInheritability.None, leaveOpen: true);
            _fileView = _fileMmf.CreateViewAccessor(0, TotalBytes, MemoryMappedFileAccess.ReadWrite);
            _fileView.Write(OffMagic, Magic);
        }
        catch
        {
            _fileView?.Dispose(); _fileView = null;
            _fileMmf?.Dispose(); _fileMmf = null;
            _fileStream?.Dispose(); _fileStream = null;
        }
    }

    public void SetActive(bool active, int width, int height, int fps)
    {
        WriteActive(_view, active, width, height, fps);
        if (_fileView is not null) WriteActive(_fileView, active, width, height, fps);
    }

    private static void WriteActive(MemoryMappedViewAccessor v, bool active, int width, int height, int fps)
    {
        v.Write(OffWriting, 1);
        Thread.MemoryBarrier();
        v.Write(OffWidth, width);
        v.Write(OffHeight, height);
        v.Write(OffFps, fps);
        v.Write(OffActive, active ? 1 : 0);
        Thread.MemoryBarrier();
        v.Write(OffWriting, 0);
    }

    /// <summary>Copy one BGRA32 frame (width*height*4 bytes) into both shared memory views.</summary>
    public void WriteFrame(byte[] bgra, int width, int height, int fps)
    {
        int copyLen = Math.Min(bgra.Length, width * height * 4);
        _frameNumber++;
        WriteToView(_view, bgra, copyLen, width, height, fps, _frameNumber);
        if (_fileView is not null)
            WriteToView(_fileView, bgra, copyLen, width, height, fps, _frameNumber);
    }

    private static void WriteToView(MemoryMappedViewAccessor v, byte[] bgra, int copyLen, int width, int height, int fps, long frameNum)
    {
        v.Write(OffWriting, 1);
        Thread.MemoryBarrier();
        v.Write(OffWidth, width);
        v.Write(OffHeight, height);
        v.Write(OffFps, fps);
        v.Write(OffActive, 1);
        v.WriteArray(HeaderSize, bgra, 0, copyLen);
        v.Write(OffFrameLo, (int)(frameNum & 0xFFFFFFFF));
        v.Write(OffFrameHi, (int)(frameNum >> 32));
        Thread.MemoryBarrier();
        v.Write(OffWriting, 0);
    }

    public void Dispose()
    {
        try { SetActive(false, 1280, 720, 30); } catch { /* shutting down */ }
        _fileView?.Dispose();
        _fileMmf?.Dispose();
        _fileStream?.Dispose();
        _view.Dispose();
        _mmf.Dispose();
    }
}
