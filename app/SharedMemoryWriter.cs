using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;

namespace MHVirtualCam;

/// <summary>
/// Owns the shared-memory frame the DirectShow filter reads.
/// Must stay byte-identical with filter/sharedmem.h.
/// </summary>
public sealed class SharedMemoryWriter : IDisposable
{
    public const string MapName = @"Local\MHVirtualCamFrame";
    private const int HeaderSize = 256;
    private const int MaxW = 3840, MaxH = 2160;
    private const uint Magic = 0x4D485643; // "SVCA"
    private const long TotalBytes = HeaderSize + (long)MaxW * MaxH * 4;

    private readonly MemoryMappedFile _mmf;
    private readonly MemoryMappedViewAccessor _view;
    private long _frameNumber;

    // Header offsets (see SVCFrameHeader in sharedmem.h)
    private const int OffMagic = 0, OffWidth = 4, OffHeight = 8, OffFps = 12,
                      OffActive = 16, OffFrameLo = 20, OffFrameHi = 24, OffWriting = 28;

    public SharedMemoryWriter()
    {
        _mmf = MemoryMappedFile.CreateOrOpen(MapName, TotalBytes, MemoryMappedFileAccess.ReadWrite);
        _view = _mmf.CreateViewAccessor(0, TotalBytes, MemoryMappedFileAccess.ReadWrite);
        _view.Write(OffMagic, Magic);
        SetActive(false, 1280, 720, 30);
    }

    public void SetActive(bool active, int width, int height, int fps)
    {
        _view.Write(OffWidth, width);
        _view.Write(OffHeight, height);
        _view.Write(OffFps, fps);
        _view.Write(OffActive, active ? 1 : 0);
    }

    /// <summary>Copy one BGRA32 frame (width*height*4 bytes) into the mapping.</summary>
    public void WriteFrame(byte[] bgra, int width, int height, int fps)
    {
        _view.Write(OffWriting, 1);
        _view.Write(OffWidth, width);
        _view.Write(OffHeight, height);
        _view.Write(OffFps, fps);
        _view.Write(OffActive, 1);
        _view.WriteArray(HeaderSize, bgra, 0, Math.Min(bgra.Length, width * height * 4));
        _frameNumber++;
        _view.Write(OffFrameLo, (int)(_frameNumber & 0xFFFFFFFF));
        _view.Write(OffFrameHi, (int)(_frameNumber >> 32));
        _view.Write(OffWriting, 0);
    }

    public void Dispose()
    {
        try { SetActive(false, 1280, 720, 30); } catch { /* shutting down */ }
        _view.Dispose();
        _mmf.Dispose();
    }
}
