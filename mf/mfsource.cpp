// mfsource.cpp - MH Virtualcam Windows 11 Media Foundation Virtual Camera source.
// Hosted inside Windows Camera Frame Server (NT AUTHORITY\LocalService).
// Reads BGRA32 frames from %ProgramData%\MHVirtualCam\frame.shm and delivers
// NV12 / RGB32 samples to Windows Camera, Android Emulators, Chrome, Edge, Teams, Zoom.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <initguid.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <mferror.h>
#include <mfvirtualcamera.h>
#include <ks.h>
#include <ksmedia.h>
#include <ksproxy.h>
#include <shlobj.h>
#include <mmsystem.h>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include "../filter/sharedmem.h"

// {F6A0C342-9B5D-4E10-AC34-7D801F2E5C63}
DEFINE_GUID(CLSID_MHVirtualCamMF,
    0xf6a0c342, 0x9b5d, 0x4e10, 0xac, 0x34, 0x7d, 0x80, 0x1f, 0x2e, 0x5c, 0x63);

static const wchar_t* kClsidStr = L"{F6A0C342-9B5D-4E10-AC34-7D801F2E5C63}";
static const wchar_t* kFriendlyName = L"MH Virtualcam";

static HMODULE g_hModule = nullptr;
static std::atomic<long> g_dllRefCount{ 0 };

struct MFFormat { UINT32 w; UINT32 h; UINT32 fps; };
static const MFFormat kFormats[] = {
    { 1280,  720, 30 },
    { 1920, 1080, 30 },
    {  640,  480, 30 },
    {  720,  720, 30 },
    { 1080, 1080, 30 },
};
static const int kFormatCount = (int)(sizeof(kFormats) / sizeof(kFormats[0]));

static inline BYTE ClampByte(int v)
{
    return (BYTE)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// ------------------------------------------------ Cross-session Shared Memory
class ShmReader
{
public:
    ~ShmReader() { Close(); }

    bool EnsureOpen()
    {
        if (m_pHeader) return true;

        // 1) Preferred: %ProgramData%\MHVirtualCam\frame.shm (works in Session 0 LocalService)
        wchar_t* progData = nullptr;
        std::wstring path = L"C:\\ProgramData\\MHVirtualCam\\frame.shm";
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_ProgramData, 0, nullptr, &progData)) && progData) {
            path = std::wstring(progData) + L"\\MHVirtualCam\\frame.shm";
            CoTaskMemFree(progData);
        }

        m_hFile = CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (m_hFile != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER sz = {};
            if (GetFileSizeEx(m_hFile, &sz) && sz.QuadPart >= (LONGLONG)MVC_TOTAL_BYTES) {
                m_hMap = CreateFileMappingW(m_hFile, nullptr, PAGE_READONLY, 0, 0, nullptr);
                if (m_hMap) {
                    void* view = MapViewOfFile(m_hMap, FILE_MAP_READ, 0, 0, MVC_TOTAL_BYTES);
                    if (view) {
                        m_pHeader = (const MVCFrameHeader*)view;
                        m_pPixels = (const BYTE*)view + MVC_HEADER_SIZE;
                        return true;
                    }
                    CloseHandle(m_hMap);
                    m_hMap = nullptr;
                }
            }
            CloseHandle(m_hFile);
            m_hFile = INVALID_HANDLE_VALUE;
        }

        // 2) Fallback: Local\ shared memory (same session)
        m_hMap = OpenFileMappingW(FILE_MAP_READ, FALSE, MVC_SHARED_MEM_NAME);
        if (m_hMap) {
            void* view = MapViewOfFile(m_hMap, FILE_MAP_READ, 0, 0, MVC_TOTAL_BYTES);
            if (view) {
                m_pHeader = (const MVCFrameHeader*)view;
                m_pPixels = (const BYTE*)view + MVC_HEADER_SIZE;
                return true;
            }
            CloseHandle(m_hMap);
            m_hMap = nullptr;
        }
        return false;
    }

    void Close()
    {
        if (m_pHeader) { UnmapViewOfFile(m_pHeader); m_pHeader = nullptr; m_pPixels = nullptr; }
        if (m_hMap) { CloseHandle(m_hMap); m_hMap = nullptr; }
        if (m_hFile != INVALID_HANDLE_VALUE) { CloseHandle(m_hFile); m_hFile = INVALID_HANDLE_VALUE; }
    }

    void RenderNV12(BYTE* dst, UINT32 outW, UINT32 outH)
    {
        const size_t yBytes = (size_t)outW * outH;
        const size_t uvBytes = yBytes / 2;
        BYTE* yPlane = dst;
        BYTE* uvPlane = dst + yBytes;

        bool hasLive = EnsureOpen();
        int srcW = 0, srcH = 0;
        if (hasLive) {
            if (m_pHeader->Magic != MVC_MAGIC || m_pHeader->IsActive != 1 || m_pHeader->Writing == 1) {
                hasLive = false;
            } else {
                srcW = (int)m_pHeader->Width;
                srcH = (int)m_pHeader->Height;
                if (srcW <= 0 || srcH <= 0 || srcW > MVC_MAX_WIDTH || srcH > MVC_MAX_HEIGHT)
                    hasLive = false;
            }
        }

        if (!hasLive) {
            memset(yPlane, 0x29, yBytes);   // #1d1d1d luma
            memset(uvPlane, 0x80, uvBytes); // neutral chroma
            return;
        }

        // Black letterbox background
        memset(yPlane, 0x10, yBytes);
        memset(uvPlane, 0x80, uvBytes);

        const double scale = std::min((double)outW / srcW, (double)outH / srcH);
        const int dstW = std::max(2, (int)(srcW * scale)) & ~1;
        const int dstH = std::max(2, (int)(srcH * scale)) & ~1;
        const int offX = ((int)outW - dstW) / 2 & ~1;
        const int offY = ((int)outH - dstH) / 2 & ~1;

        for (int y = 0; y < dstH; ++y) {
            const int sy = std::min(srcH - 1, (int)((double)y / scale));
            const BYTE* srcRow = m_pPixels + (size_t)sy * srcW * 4;
            BYTE* yRow = yPlane + (size_t)(offY + y) * outW + offX;
            BYTE* uvRow = ((y & 1) == 0) ? (uvPlane + (size_t)((offY + y) / 2) * outW + offX) : nullptr;

            for (int x = 0; x < dstW; ++x) {
                const int sx = std::min(srcW - 1, (int)((double)x / scale));
                const BYTE* p = srcRow + (size_t)sx * 4; // BGRA
                const int b = p[0], g = p[1], r = p[2];
                yRow[x] = ClampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
                if (uvRow && (x & 1) == 0) {
                    const int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                    const int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                    uvRow[x]     = ClampByte(u);
                    uvRow[x + 1] = ClampByte(v);
                }
            }
        }
    }

    void RenderRGB32(BYTE* dst, UINT32 outW, UINT32 outH)
    {
        const size_t total = (size_t)outW * outH * 4;
        bool hasLive = EnsureOpen();
        int srcW = 0, srcH = 0;
        if (hasLive) {
            if (m_pHeader->Magic != MVC_MAGIC || m_pHeader->IsActive != 1 || m_pHeader->Writing == 1) {
                hasLive = false;
            } else {
                srcW = (int)m_pHeader->Width;
                srcH = (int)m_pHeader->Height;
                if (srcW <= 0 || srcH <= 0 || srcW > MVC_MAX_WIDTH || srcH > MVC_MAX_HEIGHT)
                    hasLive = false;
            }
        }

        if (!hasLive) {
            for (size_t i = 0; i + 3 < total; i += 4) {
                dst[i] = 0x1D; dst[i + 1] = 0x1D; dst[i + 2] = 0x1D; dst[i + 3] = 0xFF;
            }
            return;
        }

        ZeroMemory(dst, total);
        const double scale = std::min((double)outW / srcW, (double)outH / srcH);
        const int dstW = std::max(1, (int)(srcW * scale));
        const int dstH = std::max(1, (int)(srcH * scale));
        const int offX = ((int)outW - dstW) / 2;
        const int offY = ((int)outH - dstH) / 2;

        for (int y = 0; y < dstH; ++y) {
            const int sy = std::min(srcH - 1, (int)((double)y / scale));
            const BYTE* srcRow = m_pPixels + (size_t)sy * srcW * 4;
            BYTE* dstRow = dst + (size_t)(offY + y) * outW * 4 + (size_t)offX * 4;
            for (int x = 0; x < dstW; ++x) {
                const int sx = std::min(srcW - 1, (int)((double)x / scale));
                const BYTE* s = srcRow + (size_t)sx * 4;
                BYTE* d = dstRow + (size_t)x * 4;
                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 0xFF;
            }
        }
    }

private:
    HANDLE m_hFile = INVALID_HANDLE_VALUE;
    HANDLE m_hMap = nullptr;
    const MVCFrameHeader* m_pHeader = nullptr;
    const BYTE* m_pPixels = nullptr;
};

static HRESULT BuildVideoMediaType(UINT32 w, UINT32 h, UINT32 fps, const GUID& subtype, IMFMediaType** ppType)
{
    IMFMediaType* mt = nullptr;
    HRESULT hr = MFCreateMediaType(&mt);
    if (FAILED(hr)) return hr;

    const bool isNv12 = (subtype == MFVideoFormat_NV12);
    const UINT32 stride = isNv12 ? w : (w * 4);
    const UINT32 sampleSize = isNv12 ? (w * h * 3 / 2) : (w * h * 4);

    mt->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    mt->SetGUID(MF_MT_SUBTYPE, subtype);
    mt->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    mt->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
    MFSetAttributeSize(mt, MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(mt, MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(mt, MF_MT_FRAME_RATE_RANGE_MIN, 15, 1);
    MFSetAttributeRatio(mt, MF_MT_FRAME_RATE_RANGE_MAX, 60, 1);
    MFSetAttributeRatio(mt, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    mt->SetUINT32(MF_MT_DEFAULT_STRIDE, stride);
    mt->SetUINT32(MF_MT_SAMPLE_SIZE, sampleSize);
    mt->SetUINT32(MF_MT_FIXED_SIZE_SAMPLES, TRUE);

    *ppType = mt;
    return S_OK;
}

class CMHMediaSource;

// ------------------------------------------------------------ Media Stream
class CMHMediaStream : public IMFMediaStream2, public IKsControl
{
public:
    CMHMediaStream(CMHMediaSource* pSource, IMFStreamDescriptor* pDesc)
        : m_source(pSource), m_desc(pDesc)
    {
        g_dllRefCount++;
        if (m_desc) m_desc->AddRef();
        MFCreateEventQueue(&m_queue);
        QueryPerformanceFrequency(&m_qpcFreq);
        QueryPerformanceCounter(&m_nextQpc);
    }

    ~CMHMediaStream()
    {
        if (m_queue) m_queue->Release();
        if (m_desc) m_desc->Release();
        g_dllRefCount--;
    }

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator ||
            riid == IID_IMFMediaStream || riid == IID_IMFMediaStream2) {
            *ppv = static_cast<IMFMediaStream2*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IKsControl) {
            *ppv = static_cast<IKsControl*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_ref; }
    STDMETHODIMP_(ULONG) Release() override
    {
        ULONG c = --m_ref;
        if (c == 0) delete this;
        return c;
    }

    // IMFMediaEventGenerator
    STDMETHODIMP GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->GetEvent(dwFlags, ppEvent);
    }
    STDMETHODIMP BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->BeginGetEvent(pCallback, punkState);
    }
    STDMETHODIMP EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->EndGetEvent(pResult, ppEvent);
    }
    STDMETHODIMP QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->QueueEventParamVar(met, guidExtendedType, hrStatus, pvValue);
    }

    // IMFMediaStream
    STDMETHODIMP GetMediaSource(IMFMediaSource** ppMediaSource) override;
    STDMETHODIMP GetStreamDescriptor(IMFStreamDescriptor** ppStreamDescriptor) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        if (!ppStreamDescriptor) return E_POINTER;
        *ppStreamDescriptor = m_desc;
        if (m_desc) m_desc->AddRef();
        return S_OK;
    }

    STDMETHODIMP RequestSample(IUnknown* pToken) override
    {
        UINT32 w = 1280, h = 720, fps = 30;
        GUID sub = MFVideoFormat_NV12;
        LONGLONG frameIndex = 0;

        {
            std::lock_guard<std::mutex> lock(m_mtx);
            if (m_shutdown) return MF_E_SHUTDOWN;
            if (m_state == MF_STREAM_STATE_STOPPED) return MF_E_INVALID_STATE_TRANSITION;
            ReadCurrentFormatLocked(w, h, fps, sub);
            frameIndex = m_frameNumber++;
        }

        PaceFrame(fps);

        const bool isNv12 = (sub == MFVideoFormat_NV12);
        const DWORD bufLen = isNv12 ? (w * h * 3 / 2) : (w * h * 4);

        IMFSample* sample = nullptr;
        IMFMediaBuffer* buffer = nullptr;
        HRESULT hr = MFCreateSample(&sample);
        if (SUCCEEDED(hr)) hr = MFCreateMemoryBuffer(bufLen, &buffer);
        if (SUCCEEDED(hr)) {
            BYTE* pData = nullptr;
            hr = buffer->Lock(&pData, nullptr, nullptr);
            if (SUCCEEDED(hr)) {
                std::lock_guard<std::mutex> shmLock(m_shmMtx);
                if (isNv12) m_shm.RenderNV12(pData, w, h);
                else m_shm.RenderRGB32(pData, w, h);
                buffer->Unlock();
                buffer->SetCurrentLength(bufLen);
            }
        }

        if (SUCCEEDED(hr)) {
            sample->AddBuffer(buffer);
            const LONGLONG dur = 10000000LL / std::max<UINT32>(1, fps);
            sample->SetSampleTime(frameIndex * dur);
            sample->SetSampleDuration(dur);
            sample->SetUINT32(MFSampleExtension_CleanPoint, 1);
            if (pToken) sample->SetUnknown(MFSampleExtension_Token, pToken);

            std::lock_guard<std::mutex> lock(m_mtx);
            if (!m_shutdown)
                hr = m_queue->QueueEventParamUnk(MEMediaSample, GUID_NULL, S_OK, sample);
            else
                hr = MF_E_SHUTDOWN;
        }

        if (buffer) buffer->Release();
        if (sample) sample->Release();
        return hr;
    }

    // IMFMediaStream2
    STDMETHODIMP SetStreamState(MF_STREAM_STATE value) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        if (m_state == value) return S_OK;
        m_state = value;
        if (value == MF_STREAM_STATE_RUNNING) {
            QueryPerformanceCounter(&m_nextQpc);
            PROPVARIANT var; PropVariantInit(&var);
            m_queue->QueueEventParamVar(MEStreamStarted, GUID_NULL, S_OK, &var);
        } else if (value == MF_STREAM_STATE_STOPPED) {
            m_queue->QueueEventParamVar(MEStreamStopped, GUID_NULL, S_OK, nullptr);
        } else if (value == MF_STREAM_STATE_PAUSED) {
            m_queue->QueueEventParamVar(MEStreamPaused, GUID_NULL, S_OK, nullptr);
        }
        return S_OK;
    }

    STDMETHODIMP GetStreamState(MF_STREAM_STATE* value) override
    {
        if (!value) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        *value = m_state;
        return S_OK;
    }

    // IKsControl
    STDMETHODIMP KsProperty(PKSPROPERTY, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }
    STDMETHODIMP KsMethod(PKSMETHOD, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }
    STDMETHODIMP KsEvent(PKSEVENT, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }

    // Internal control from CMHMediaSource
    void StartStream(const PROPVARIANT* pvarStart)
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return;
        m_state = MF_STREAM_STATE_RUNNING;
        m_frameNumber = 0;
        QueryPerformanceCounter(&m_nextQpc);
        m_queue->QueueEventParamVar(MEStreamStarted, GUID_NULL, S_OK, pvarStart);
    }

    void StopStream()
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return;
        m_state = MF_STREAM_STATE_STOPPED;
        m_queue->QueueEventParamVar(MEStreamStopped, GUID_NULL, S_OK, nullptr);
    }

    void ShutdownStream()
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return;
        m_shutdown = true;
        if (m_queue) m_queue->Shutdown();
        std::lock_guard<std::mutex> shmLock(m_shmMtx);
        m_shm.Close();
    }

private:
    void ReadCurrentFormatLocked(UINT32& w, UINT32& h, UINT32& fps, GUID& sub)
    {
        IMFMediaTypeHandler* handler = nullptr;
        if (m_desc && SUCCEEDED(m_desc->GetMediaTypeHandler(&handler)) && handler) {
            IMFMediaType* cur = nullptr;
            if (SUCCEEDED(handler->GetCurrentMediaType(&cur)) && cur) {
                MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &w, &h);
                UINT32 num = 30, den = 1;
                if (SUCCEEDED(MFGetAttributeRatio(cur, MF_MT_FRAME_RATE, &num, &den)) && den > 0)
                    fps = std::max<UINT32>(1, num / den);
                cur->GetGUID(MF_MT_SUBTYPE, &sub);
                cur->Release();
            }
            handler->Release();
        }
    }

    void PaceFrame(UINT32 fps)
    {
        if (m_qpcFreq.QuadPart <= 0) return;
        const LONGLONG interval = m_qpcFreq.QuadPart / std::max<UINT32>(1, fps);
        m_nextQpc.QuadPart += interval;
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        const LONGLONG rem = m_nextQpc.QuadPart - now.QuadPart;
        if (rem > 0) {
            const DWORD ms = (DWORD)((rem * 1000) / m_qpcFreq.QuadPart);
            if (ms > 0) Sleep(ms);
        } else if (-rem > interval * 3) {
            m_nextQpc = now;
        }
    }

    std::atomic<ULONG> m_ref{ 1 };
    CMHMediaSource* m_source; // weak back-pointer while source is alive
    IMFStreamDescriptor* m_desc;
    IMFMediaEventQueue* m_queue = nullptr;
    MF_STREAM_STATE m_state = MF_STREAM_STATE_STOPPED;
    bool m_shutdown = false;
    LONGLONG m_frameNumber = 0;
    LARGE_INTEGER m_qpcFreq = {};
    LARGE_INTEGER m_nextQpc = {};
    std::mutex m_mtx;
    std::mutex m_shmMtx;
    ShmReader m_shm;
};

// ------------------------------------------------------------ Media Source
class CMHMediaSource : public IMFMediaSourceEx, public IMFGetService, public IKsControl, public IMFSampleAllocatorControl
{
public:
    CMHMediaSource() { g_dllRefCount++; }
    ~CMHMediaSource()
    {
        if (m_stream) m_stream->Release();
        if (m_pd) m_pd->Release();
        if (m_sourceAttrs) m_sourceAttrs->Release();
        if (m_streamAttrs) m_streamAttrs->Release();
        if (m_queue) m_queue->Release();
        g_dllRefCount--;
    }

    HRESULT Init()
    {
        HRESULT hr = MFCreateEventQueue(&m_queue);
        if (FAILED(hr)) return hr;

        hr = MFCreateAttributes(&m_sourceAttrs, 4);
        if (FAILED(hr)) return hr;
        m_sourceAttrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        m_sourceAttrs->SetString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, kFriendlyName);
        m_sourceAttrs->SetUINT32(MF_VIRTUALCAMERA_PROVIDE_ASSOCIATED_CAMERA_SOURCES, 0);

        hr = MFCreateAttributes(&m_streamAttrs, 4);
        if (FAILED(hr)) return hr;
        m_streamAttrs->SetGUID(MF_DEVICESTREAM_STREAM_CATEGORY, PINNAME_VIDEO_CAPTURE);
        m_streamAttrs->SetUINT32(MF_DEVICESTREAM_STREAM_ID, 0);
        m_streamAttrs->SetUINT32(MF_DEVICESTREAM_FRAMESERVER_SHARED, 1);
        m_streamAttrs->SetUINT32(MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, MFFrameSourceTypes_Color);

        // Build NV12 + RGB32 media types
        const int totalTypes = kFormatCount * 2;
        IMFMediaType* types[kFormatCount * 2] = {};
        int idx = 0;
        for (int i = 0; i < kFormatCount; ++i)
            BuildVideoMediaType(kFormats[i].w, kFormats[i].h, kFormats[i].fps, MFVideoFormat_NV12, &types[idx++]);
        for (int i = 0; i < kFormatCount; ++i)
            BuildVideoMediaType(kFormats[i].w, kFormats[i].h, kFormats[i].fps, MFVideoFormat_RGB32, &types[idx++]);

        IMFStreamDescriptor* sd = nullptr;
        hr = MFCreateStreamDescriptor(0, totalTypes, types, &sd);
        if (SUCCEEDED(hr) && sd) {
            sd->SetGUID(MF_DEVICESTREAM_STREAM_CATEGORY, PINNAME_VIDEO_CAPTURE);
            sd->SetUINT32(MF_DEVICESTREAM_STREAM_ID, 0);
            sd->SetUINT32(MF_DEVICESTREAM_FRAMESERVER_SHARED, 1);
            sd->SetUINT32(MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, MFFrameSourceTypes_Color);

            IMFMediaTypeHandler* handler = nullptr;
            if (SUCCEEDED(sd->GetMediaTypeHandler(&handler)) && handler) {
                handler->SetCurrentMediaType(types[0]);
                handler->Release();
            }
            hr = MFCreatePresentationDescriptor(1, &sd, &m_pd);
            if (SUCCEEDED(hr)) {
                m_pd->SelectStream(0);
                m_stream = new CMHMediaStream(this, sd);
            }
            sd->Release();
        }
        for (int i = 0; i < totalTypes; ++i) if (types[i]) types[i]->Release();
        return hr;
    }

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator ||
            riid == IID_IMFMediaSource || riid == IID_IMFMediaSourceEx) {
            *ppv = static_cast<IMFMediaSourceEx*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IMFGetService) {
            *ppv = static_cast<IMFGetService*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IKsControl) {
            *ppv = static_cast<IKsControl*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IMFSampleAllocatorControl) {
            *ppv = static_cast<IMFSampleAllocatorControl*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_ref; }
    STDMETHODIMP_(ULONG) Release() override
    {
        ULONG c = --m_ref;
        if (c == 0) delete this;
        return c;
    }

    // IMFMediaEventGenerator
    STDMETHODIMP GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->GetEvent(dwFlags, ppEvent);
    }
    STDMETHODIMP BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->BeginGetEvent(pCallback, punkState);
    }
    STDMETHODIMP EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->EndGetEvent(pResult, ppEvent);
    }
    STDMETHODIMP QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_queue->QueueEventParamVar(met, guidExtendedType, hrStatus, pvValue);
    }

    // IMFMediaSource
    STDMETHODIMP GetCharacteristics(DWORD* pdwCharacteristics) override
    {
        if (!pdwCharacteristics) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        *pdwCharacteristics = MFMEDIASOURCE_IS_LIVE;
        return S_OK;
    }

    STDMETHODIMP CreatePresentationDescriptor(IMFPresentationDescriptor** ppPD) override
    {
        if (!ppPD) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        return m_pd->Clone(ppPD);
    }

    STDMETHODIMP Start(IMFPresentationDescriptor* pPD, const GUID* pguidTimeFormat, const PROPVARIANT* pvarStartPosition) override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        if (pguidTimeFormat && *pguidTimeFormat != GUID_NULL) return MF_E_UNSUPPORTED_TIME_FORMAT;

        // Sync negotiated media type from caller's presentation descriptor if provided
        if (pPD && m_stream) {
            BOOL selected = FALSE;
            IMFStreamDescriptor* reqSd = nullptr;
            if (SUCCEEDED(pPD->GetStreamDescriptorByIndex(0, &selected, &reqSd)) && reqSd) {
                IMFMediaTypeHandler* reqH = nullptr;
                IMFMediaType* reqMt = nullptr;
                if (SUCCEEDED(reqSd->GetMediaTypeHandler(&reqH)) && reqH) {
                    if (SUCCEEDED(reqH->GetCurrentMediaType(&reqMt)) && reqMt) {
                        IMFStreamDescriptor* ownSd = nullptr;
                        if (SUCCEEDED(m_stream->GetStreamDescriptor(&ownSd)) && ownSd) {
                            IMFMediaTypeHandler* ownH = nullptr;
                            if (SUCCEEDED(ownSd->GetMediaTypeHandler(&ownH)) && ownH) {
                                ownH->SetCurrentMediaType(reqMt);
                                ownH->Release();
                            }
                            ownSd->Release();
                        }
                        reqMt->Release();
                    }
                    reqH->Release();
                }
                reqSd->Release();
            }
        }

        PROPVARIANT startVar;
        PropVariantInit(&startVar);
        if (pvarStartPosition) startVar = *pvarStartPosition;

        MediaEventType streamEv = m_startedOnce ? MEUpdatedStream : MENewStream;
        m_startedOnce = true;
        m_queue->QueueEventParamUnk(streamEv, GUID_NULL, S_OK, static_cast<IMFMediaStream2*>(m_stream));
        m_queue->QueueEventParamVar(MESourceStarted, GUID_NULL, S_OK, &startVar);
        m_stream->StartStream(&startVar);
        return S_OK;
    }

    STDMETHODIMP Stop() override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        if (m_stream) m_stream->StopStream();
        m_queue->QueueEventParamVar(MESourceStopped, GUID_NULL, S_OK, nullptr);
        return S_OK;
    }

    STDMETHODIMP Pause() override { return MF_E_INVALID_STATE_TRANSITION; }

    STDMETHODIMP Shutdown() override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return S_OK;
        m_shutdown = true;
        if (m_stream) m_stream->ShutdownStream();
        if (m_queue) m_queue->Shutdown();
        return S_OK;
    }

    // IMFMediaSourceEx
    STDMETHODIMP GetSourceAttributes(IMFAttributes** ppAttributes) override
    {
        if (!ppAttributes) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        *ppAttributes = m_sourceAttrs;
        m_sourceAttrs->AddRef();
        return S_OK;
    }

    STDMETHODIMP GetStreamAttributes(DWORD dwStreamIdentifier, IMFAttributes** ppAttributes) override
    {
        if (!ppAttributes) return E_POINTER;
        if (dwStreamIdentifier != 0) return MF_E_INVALIDSTREAMNUMBER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_shutdown) return MF_E_SHUTDOWN;
        *ppAttributes = m_streamAttrs;
        m_streamAttrs->AddRef();
        return S_OK;
    }

    STDMETHODIMP SetD3DManager(IUnknown*) override { return S_OK; }

    // IMFGetService
    STDMETHODIMP GetService(REFGUID, REFIID riid, LPVOID* ppvObject) override
    {
        if (riid == IID_IMFSampleAllocatorControl)
            return QueryInterface(riid, ppvObject);
        return MF_E_UNSUPPORTED_SERVICE;
    }

    // IKsControl
    STDMETHODIMP KsProperty(PKSPROPERTY, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }
    STDMETHODIMP KsMethod(PKSMETHOD, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }
    STDMETHODIMP KsEvent(PKSEVENT, ULONG, LPVOID, ULONG, ULONG* BytesReturned) override
    {
        if (BytesReturned) *BytesReturned = 0;
        return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
    }

    // IMFSampleAllocatorControl
    STDMETHODIMP SetDefaultAllocator(DWORD, IUnknown*) override { return S_OK; }
    STDMETHODIMP GetAllocatorUsage(DWORD, DWORD*, MFSampleAllocatorUsage* peUsage) override
    {
        if (!peUsage) return E_POINTER;
        *peUsage = MFSampleAllocatorUsage_DoesNotUseProvidedAllocator;
        return S_OK;
    }

private:
    std::atomic<ULONG> m_ref{ 1 };
    IMFMediaEventQueue* m_queue = nullptr;
    IMFPresentationDescriptor* m_pd = nullptr;
    IMFAttributes* m_sourceAttrs = nullptr;
    IMFAttributes* m_streamAttrs = nullptr;
    CMHMediaStream* m_stream = nullptr;
    bool m_startedOnce = false;
    bool m_shutdown = false;
    std::mutex m_mtx;
};

STDMETHODIMP CMHMediaStream::GetMediaSource(IMFMediaSource** ppMediaSource)
{
    if (!ppMediaSource) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mtx);
    if (m_shutdown) return MF_E_SHUTDOWN;
    *ppMediaSource = static_cast<IMFMediaSource*>(m_source);
    m_source->AddRef();
    return S_OK;
}

// ------------------------------------------------------------ IMFActivate
class CMHActivate : public IMFActivate
{
public:
    CMHActivate()
    {
        g_dllRefCount++;
        MFCreateAttributes(&m_attrs, 4);
    }
    ~CMHActivate()
    {
        if (m_source) m_source->Release();
        if (m_attrs) m_attrs->Release();
        g_dllRefCount--;
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IMFAttributes || riid == IID_IMFActivate) {
            *ppv = static_cast<IMFActivate*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_ref; }
    STDMETHODIMP_(ULONG) Release() override
    {
        ULONG c = --m_ref;
        if (c == 0) delete this;
        return c;
    }

    // IMFActivate
    STDMETHODIMP ActivateObject(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (!m_source) {
            auto* src = new CMHMediaSource();
            HRESULT hr = src->Init();
            if (FAILED(hr)) { src->Release(); return hr; }
            m_source = src;
        }
        return m_source->QueryInterface(riid, ppv);
    }
    STDMETHODIMP ShutdownObject() override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_source) { m_source->Shutdown(); m_source->Release(); m_source = nullptr; }
        return S_OK;
    }
    STDMETHODIMP DetachObject() override
    {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (m_source) { m_source->Release(); m_source = nullptr; }
        return S_OK;
    }

    // IMFAttributes delegation
    STDMETHODIMP GetItem(REFGUID k, PROPVARIANT* v) override { return m_attrs->GetItem(k, v); }
    STDMETHODIMP GetItemType(REFGUID k, MF_ATTRIBUTE_TYPE* t) override { return m_attrs->GetItemType(k, t); }
    STDMETHODIMP CompareItem(REFGUID k, REFPROPVARIANT v, BOOL* r) override { return m_attrs->CompareItem(k, v, r); }
    STDMETHODIMP Compare(IMFAttributes* o, MF_ATTRIBUTES_MATCH_TYPE t, BOOL* r) override { return m_attrs->Compare(o, t, r); }
    STDMETHODIMP GetUINT32(REFGUID k, UINT32* v) override { return m_attrs->GetUINT32(k, v); }
    STDMETHODIMP GetUINT64(REFGUID k, UINT64* v) override { return m_attrs->GetUINT64(k, v); }
    STDMETHODIMP GetDouble(REFGUID k, double* v) override { return m_attrs->GetDouble(k, v); }
    STDMETHODIMP GetGUID(REFGUID k, GUID* v) override { return m_attrs->GetGUID(k, v); }
    STDMETHODIMP GetStringLength(REFGUID k, UINT32* l) override { return m_attrs->GetStringLength(k, l); }
    STDMETHODIMP GetString(REFGUID k, LPWSTR v, UINT32 c, UINT32* l) override { return m_attrs->GetString(k, v, c, l); }
    STDMETHODIMP GetAllocatedString(REFGUID k, LPWSTR* v, UINT32* l) override { return m_attrs->GetAllocatedString(k, v, l); }
    STDMETHODIMP GetBlobSize(REFGUID k, UINT32* s) override { return m_attrs->GetBlobSize(k, s); }
    STDMETHODIMP GetBlob(REFGUID k, UINT8* b, UINT32 s, UINT32* l) override { return m_attrs->GetBlob(k, b, s, l); }
    STDMETHODIMP GetAllocatedBlob(REFGUID k, UINT8** b, UINT32* s) override { return m_attrs->GetAllocatedBlob(k, b, s); }
    STDMETHODIMP GetUnknown(REFGUID k, REFIID r, LPVOID* v) override { return m_attrs->GetUnknown(k, r, v); }
    STDMETHODIMP SetItem(REFGUID k, REFPROPVARIANT v) override { return m_attrs->SetItem(k, v); }
    STDMETHODIMP DeleteItem(REFGUID k) override { return m_attrs->DeleteItem(k); }
    STDMETHODIMP DeleteAllItems() override { return m_attrs->DeleteAllItems(); }
    STDMETHODIMP SetUINT32(REFGUID k, UINT32 v) override { return m_attrs->SetUINT32(k, v); }
    STDMETHODIMP SetUINT64(REFGUID k, UINT64 v) override { return m_attrs->SetUINT64(k, v); }
    STDMETHODIMP SetDouble(REFGUID k, double v) override { return m_attrs->SetDouble(k, v); }
    STDMETHODIMP SetGUID(REFGUID k, REFGUID v) override { return m_attrs->SetGUID(k, v); }
    STDMETHODIMP SetString(REFGUID k, LPCWSTR v) override { return m_attrs->SetString(k, v); }
    STDMETHODIMP SetBlob(REFGUID k, const UINT8* b, UINT32 s) override { return m_attrs->SetBlob(k, b, s); }
    STDMETHODIMP SetUnknown(REFGUID k, IUnknown* v) override { return m_attrs->SetUnknown(k, v); }
    STDMETHODIMP LockStore() override { return m_attrs->LockStore(); }
    STDMETHODIMP UnlockStore() override { return m_attrs->UnlockStore(); }
    STDMETHODIMP GetCount(UINT32* c) override { return m_attrs->GetCount(c); }
    STDMETHODIMP GetItemByIndex(UINT32 i, GUID* k, PROPVARIANT* v) override { return m_attrs->GetItemByIndex(i, k, v); }
    STDMETHODIMP CopyAllItems(IMFAttributes* d) override { return m_attrs->CopyAllItems(d); }

private:
    std::atomic<ULONG> m_ref{ 1 };
    IMFAttributes* m_attrs = nullptr;
    CMHMediaSource* m_source = nullptr;
    std::mutex m_mtx;
};

// ------------------------------------------------------------ Class Factory
class CMHClassFactory : public IClassFactory
{
public:
    CMHClassFactory() { g_dllRefCount++; }
    ~CMHClassFactory() { g_dllRefCount--; }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_ref; }
    STDMETHODIMP_(ULONG) Release() override
    {
        ULONG c = --m_ref;
        if (c == 0) delete this;
        return c;
    }

    STDMETHODIMP CreateInstance(IUnknown* pOuter, REFIID riid, void** ppv) override
    {
        if (pOuter) return CLASS_E_NOAGGREGATION;
        if (!ppv) return E_POINTER;
        if (riid == IID_IMFMediaSource || riid == IID_IMFMediaSourceEx) {
            auto* src = new CMHMediaSource();
            HRESULT hr = src->Init();
            if (SUCCEEDED(hr)) hr = src->QueryInterface(riid, ppv);
            src->Release();
            return hr;
        }
        auto* act = new CMHActivate();
        HRESULT hr = act->QueryInterface(riid, ppv);
        act->Release();
        return hr;
    }

    STDMETHODIMP LockServer(BOOL fLock) override
    {
        if (fLock) g_dllRefCount++; else g_dllRefCount--;
        return S_OK;
    }

private:
    std::atomic<ULONG> m_ref{ 1 };
};

// ------------------------------------------------------------ DLL Exports
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) {
        g_hModule = hModule;
        DisableThreadLibraryCalls(hModule);
    }
    return TRUE;
}

STDAPI DllCanUnloadNow()
{
    return (g_dllRefCount.load() == 0) ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv)
{
    if (rclsid != CLSID_MHVirtualCamMF) return CLASS_E_CLASSNOTAVAILABLE;
    auto* cf = new CMHClassFactory();
    HRESULT hr = cf->QueryInterface(riid, ppv);
    cf->Release();
    return hr;
}

STDAPI DllRegisterServer()
{
    wchar_t dllPath[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_hModule, dllPath, MAX_PATH))
        return HRESULT_FROM_WIN32(GetLastError());

    std::wstring keyPath = std::wstring(L"CLSID\\") + kClsidStr;
    HKEY hKey = nullptr;
    LONG rc = RegCreateKeyExW(HKEY_CLASSES_ROOT, keyPath.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr);
    if (rc != ERROR_SUCCESS) return HRESULT_FROM_WIN32(rc);
    RegSetValueExW(hKey, nullptr, 0, REG_SZ, (const BYTE*)kFriendlyName, (DWORD)((wcslen(kFriendlyName) + 1) * sizeof(wchar_t)));

    HKEY hInproc = nullptr;
    rc = RegCreateKeyExW(hKey, L"InprocServer32", 0, nullptr, 0, KEY_WRITE, nullptr, &hInproc, nullptr);
    if (rc == ERROR_SUCCESS) {
        RegSetValueExW(hInproc, nullptr, 0, REG_SZ, (const BYTE*)dllPath, (DWORD)((wcslen(dllPath) + 1) * sizeof(wchar_t)));
        const wchar_t* model = L"Both";
        RegSetValueExW(hInproc, L"ThreadingModel", 0, REG_SZ, (const BYTE*)model, (DWORD)((wcslen(model) + 1) * sizeof(wchar_t)));
        RegCloseKey(hInproc);
    }
    RegCloseKey(hKey);
    return HRESULT_FROM_WIN32(rc);
}

STDAPI DllUnregisterServer()
{
    std::wstring keyPath = std::wstring(L"CLSID\\") + kClsidStr;
    RegDeleteTreeW(HKEY_CLASSES_ROOT, keyPath.c_str());
    return S_OK;
}
