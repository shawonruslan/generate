// filter.cpp - MH Virtualcam DirectShow source filter.
// Register with:  regsvr32 MHVirtualCamFilter.dll  (admin, x64 + Win32)
#include <streams.h>
#include <olectl.h>
#include <initguid.h>
#include <dllsetup.h>
#include <mmsystem.h>
#include <limits.h>
#include "guids.h"
#include "filter.h"

// ---------------------------------------------------------------- formats
struct CamFormat { int width; int height; int fps; };
static const CamFormat kFormats[] = {
    {1280,  720, 30}, {1280,  720, 60},
    {1920, 1080, 30}, {1920, 1080, 60},
    { 640,  480, 30},
    {1080, 1080, 30}, { 720,  720, 30},
    {1440, 1080, 30}, {1024,  768, 30},
    {1080, 1920, 30}, { 720, 1280, 30},
    {1080, 1440, 30}, { 768, 1024, 30},
    {1680,  720, 30}, { 854,  480, 30},
};
static const int kFormatCount = (int)(sizeof(kFormats) / sizeof(kFormats[0]));

static const GUID kSubtypes[] = {
    MEDIASUBTYPE_YUY2,
    MEDIASUBTYPE_RGB24,
    MEDIASUBTYPE_RGB32,
};
static const int kSubtypeCount = (int)(sizeof(kSubtypes) / sizeof(kSubtypes[0]));

static int BitsPerPixel(const GUID& subtype)
{
    if (subtype == MEDIASUBTYPE_YUY2)  return 16;
    if (subtype == MEDIASUBTYPE_RGB24) return 24;
    return 32;
}

static long CalcImageSize(const GUID& subtype, int w, int h)
{
    return (long)((LONGLONG)w * h * BitsPerPixel(subtype) / 8);
}

static HRESULT MakeMediaType(CMediaType* mt, const CamFormat& f, const GUID& subtype)
{
    const int bpp = BitsPerPixel(subtype);
    const long imageSize = CalcImageSize(subtype, f.width, f.height);

    mt->SetType(&MEDIATYPE_Video);
    mt->SetSubtype(&subtype);
    mt->SetFormatType(&FORMAT_VideoInfo);
    mt->SetTemporalCompression(FALSE);
    mt->SetSampleSize((ULONG)imageSize);

    VIDEOINFOHEADER* vih = (VIDEOINFOHEADER*)mt->AllocFormatBuffer(sizeof(VIDEOINFOHEADER));
    if (!vih) return E_OUTOFMEMORY;
    ZeroMemory(vih, sizeof(VIDEOINFOHEADER));
    vih->AvgTimePerFrame = UNITS / f.fps;
    vih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    vih->bmiHeader.biWidth = f.width;
    vih->bmiHeader.biHeight = f.height;
    vih->bmiHeader.biPlanes = 1;
    vih->bmiHeader.biBitCount = (WORD)bpp;
    vih->bmiHeader.biCompression = (subtype == MEDIASUBTYPE_YUY2) ? MAKEFOURCC('Y', 'U', 'Y', '2') : BI_RGB;
    vih->bmiHeader.biSizeImage = (DWORD)imageSize;
    const LONGLONG bitRate = (LONGLONG)imageSize * 8 * f.fps;
    vih->dwBitRate = (DWORD)min(bitRate, (LONGLONG)ULONG_MAX);
    SetRect(&vih->rcSource, 0, 0, f.width, f.height);
    SetRect(&vih->rcTarget, 0, 0, f.width, f.height);
    return S_OK;
}

static inline BYTE ClampByte(int v)
{
    return (BYTE)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// ------------------------------------------------------------------- pin
CMHCamPin::CMHCamPin(HRESULT* phr, CSource* pFilter)
    : CSourceStream(NAME("MH Virtualcam"), phr, pFilter, L"Capture")
{
    m_subtype = MEDIASUBTYPE_YUY2;
    m_width = kFormats[0].width;
    m_height = kFormats[0].height;
    m_fps = kFormats[0].fps;
    m_frameDuration = UNITS / m_fps;
    QueryPerformanceFrequency(&m_qpcFreq);
}

CMHCamPin::~CMHCamPin() { CloseSharedMemory(); }

STDMETHODIMP CMHCamPin::NonDelegatingQueryInterface(REFIID riid, void** ppv)
{
    if (riid == IID_IAMStreamConfig)  return GetInterface((IAMStreamConfig*)this, ppv);
    if (riid == IID_IKsPropertySet)   return GetInterface((IKsPropertySet*)this, ppv);
    return CSourceStream::NonDelegatingQueryInterface(riid, ppv);
}

bool CMHCamPin::OpenSharedMemory()
{
    if (m_pHeader) return true;
    m_hMap = OpenFileMappingW(FILE_MAP_READ, FALSE, MVC_SHARED_MEM_NAME);
    if (!m_hMap) return false;
    void* view = MapViewOfFile(m_hMap, FILE_MAP_READ, 0, 0, MVC_TOTAL_BYTES);
    if (!view) { CloseHandle(m_hMap); m_hMap = nullptr; return false; }
    m_pHeader = (MVCFrameHeader*)view;
    m_pPixels = (const BYTE*)view + MVC_HEADER_SIZE;
    return true;
}

void CMHCamPin::CloseSharedMemory()
{
    if (m_pHeader) { UnmapViewOfFile(m_pHeader); m_pHeader = nullptr; m_pPixels = nullptr; }
    if (m_hMap) { CloseHandle(m_hMap); m_hMap = nullptr; }
}

HRESULT CMHCamPin::OnThreadCreate()
{
    m_frameNumber = 0;
    if (timeBeginPeriod(1) == TIMERR_NOERROR) m_timerResSet = true;
    QueryPerformanceCounter(&m_nextFrameQpc);
    OpenSharedMemory();
    return S_OK;
}

HRESULT CMHCamPin::OnThreadDestroy()
{
    if (m_timerResSet) {
        timeEndPeriod(1);
        m_timerResSet = false;
    }
    return S_OK;
}

void CMHCamPin::PaceFrame()
{
    if (m_qpcFreq.QuadPart <= 0) return;
    const LONGLONG intervalTicks = m_qpcFreq.QuadPart / max(1, m_fps);
    m_nextFrameQpc.QuadPart += intervalTicks;

    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    const LONGLONG remaining = m_nextFrameQpc.QuadPart - now.QuadPart;
    if (remaining > 0) {
        const DWORD ms = (DWORD)((remaining * 1000) / m_qpcFreq.QuadPart);
        if (ms > 0) Sleep(ms);
        do {
            QueryPerformanceCounter(&now);
        } while (now.QuadPart < m_nextFrameQpc.QuadPart);
    } else if (-remaining > intervalTicks * 3) {
        // Resync if we fell more than 3 frames behind
        m_nextFrameQpc = now;
    }
}

void CMHCamPin::CopyFrameTo(BYTE* pData, long outSize)
{
    const int outW = m_width, outH = m_height;
    const bool isYuy2 = (m_subtype == MEDIASUBTYPE_YUY2);
    const bool isRgb24 = (m_subtype == MEDIASUBTYPE_RGB24);

    // Check if live shared-memory frame is available
    bool hasLive = (m_pHeader != nullptr || OpenSharedMemory());
    int srcW = 0, srcH = 0;
    if (hasLive) {
        if (m_pHeader->Magic != MVC_MAGIC || m_pHeader->IsActive != 1) {
            hasLive = false;
        } else {
            srcW = (int)m_pHeader->Width;
            srcH = (int)m_pHeader->Height;
            if (srcW <= 0 || srcH <= 0 || srcW > MVC_MAX_WIDTH || srcH > MVC_MAX_HEIGHT || m_pHeader->Writing == 1)
                hasLive = false;
        }
    }

    if (!hasLive) {
        // Dark placeholder (#1d1d1d)
        if (isYuy2) {
            for (long i = 0; i + 3 < outSize; i += 4) {
                pData[i + 0] = 0x29; pData[i + 1] = 0x80; // Y0=41, U=128 (BT.601 for #1d1d1d)
                pData[i + 2] = 0x29; pData[i + 3] = 0x80; // Y1=41, V=128
            }
        } else if (isRgb24) {
            for (long i = 0; i + 2 < outSize; i += 3) {
                pData[i + 0] = 0x1D; pData[i + 1] = 0x1D; pData[i + 2] = 0x1D;
            }
        } else {
            for (long i = 0; i + 3 < outSize; i += 4) {
                pData[i + 0] = 0x1D; pData[i + 1] = 0x1D; pData[i + 2] = 0x1D; pData[i + 3] = 0xFF;
            }
        }
        return;
    }

    // Fill letterbox background first
    if (isYuy2) {
        for (long i = 0; i + 3 < outSize; i += 4) {
            pData[i + 0] = 0x10; pData[i + 1] = 0x80;
            pData[i + 2] = 0x10; pData[i + 3] = 0x80;
        }
    } else {
        ZeroMemory(pData, (size_t)outSize);
    }

    const double scale = min((double)outW / srcW, (double)outH / srcH);
    const int dstW = max(1, (int)(srcW * scale));
    const int dstH = max(1, (int)(srcH * scale));
    const int offX = (outW - dstW) / 2;
    const int offY = (outH - dstH) / 2;

    if (isYuy2) {
        // YUY2 is always top-down, 2 pixels per 4 bytes: Y0 U Y1 V
        for (int y = 0; y < dstH; ++y) {
            const int sy = min(srcH - 1, (int)((double)y / scale));
            const BYTE* srcRow = m_pPixels + (size_t)sy * srcW * 4;
            BYTE* dstRow = pData + (size_t)(offY + y) * outW * 2;
            const int xStart = offX & ~1;
            const int xEnd = (offX + dstW) & ~1;
            for (int x = xStart; x + 1 < xEnd; x += 2) {
                const int sx0 = min(srcW - 1, max(0, (int)((double)(x - offX) / scale)));
                const int sx1 = min(srcW - 1, max(0, (int)((double)(x + 1 - offX) / scale)));
                const BYTE* p0 = srcRow + (size_t)sx0 * 4; // B G R A
                const BYTE* p1 = srcRow + (size_t)sx1 * 4;
                const int b0 = p0[0], g0 = p0[1], r0 = p0[2];
                const int b1 = p1[0], g1 = p1[1], r1 = p1[2];
                const int y0 = ((66 * r0 + 129 * g0 + 25 * b0 + 128) >> 8) + 16;
                const int y1 = ((66 * r1 + 129 * g1 + 25 * b1 + 128) >> 8) + 16;
                const int rAvg = (r0 + r1) >> 1;
                const int gAvg = (g0 + g1) >> 1;
                const int bAvg = (b0 + b1) >> 1;
                const int u = ((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) >> 8) + 128;
                const int v = ((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) >> 8) + 128;
                BYTE* d = dstRow + (size_t)x * 2;
                d[0] = ClampByte(y0);
                d[1] = ClampByte(u);
                d[2] = ClampByte(y1);
                d[3] = ClampByte(v);
            }
        }
    } else if (isRgb24) {
        for (int y = 0; y < dstH; ++y) {
            const int sy = min(srcH - 1, (int)((double)y / scale));
            const BYTE* srcRow = m_pPixels + (size_t)sy * srcW * 4;
            const int dstY = m_topDown ? (offY + y) : (outH - 1 - (offY + y));
            BYTE* dstRow = pData + (size_t)dstY * outW * 3 + (size_t)offX * 3;
            for (int x = 0; x < dstW; ++x) {
                const int sx = min(srcW - 1, (int)((double)x / scale));
                const BYTE* s = srcRow + (size_t)sx * 4;
                BYTE* d = dstRow + (size_t)x * 3;
                d[0] = s[0]; d[1] = s[1]; d[2] = s[2];
            }
        }
    } else {
        for (int y = 0; y < dstH; ++y) {
            const int sy = min(srcH - 1, (int)((double)y / scale));
            const BYTE* srcRow = m_pPixels + (size_t)sy * srcW * 4;
            const int dstY = m_topDown ? (offY + y) : (outH - 1 - (offY + y));
            BYTE* dstRow = pData + (size_t)dstY * outW * 4 + (size_t)offX * 4;
            for (int x = 0; x < dstW; ++x) {
                const int sx = min(srcW - 1, (int)((double)x / scale));
                const BYTE* s = srcRow + (size_t)sx * 4;
                BYTE* d = dstRow + (size_t)x * 4;
                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 0xFF;
            }
        }
    }
}

HRESULT CMHCamPin::FillBuffer(IMediaSample* pSample)
{
    CheckPointer(pSample, E_POINTER);
    PaceFrame();

    BYTE* pData = nullptr;
    HRESULT hr = pSample->GetPointer(&pData);
    if (FAILED(hr)) return hr;
    const long size = pSample->GetSize();
    const long expectedSize = CalcImageSize(m_subtype, m_width, m_height);
    const long actualSize = min(size, expectedSize);

    { CAutoLock lock(&m_critSec); CopyFrameTo(pData, actualSize); }

    const REFERENCE_TIME start = m_frameNumber * m_frameDuration;
    const REFERENCE_TIME stop = start + m_frameDuration;
    pSample->SetTime((REFERENCE_TIME*)&start, (REFERENCE_TIME*)&stop);
    pSample->SetMediaTime(nullptr, nullptr);
    pSample->SetSyncPoint(TRUE);
    pSample->SetDiscontinuity(m_frameNumber == 0);
    pSample->SetActualDataLength(actualSize);
    ++m_frameNumber;
    return S_OK;
}

HRESULT CMHCamPin::DecideBufferSize(IMemAllocator* pAlloc, ALLOCATOR_PROPERTIES* pProps)
{
    CheckPointer(pAlloc, E_POINTER); CheckPointer(pProps, E_POINTER);
    CAutoLock lock(m_pFilter->pStateLock());
    if (pProps->cBuffers == 0) pProps->cBuffers = 1;
    pProps->cbBuffer = CalcImageSize(m_subtype, m_width, m_height);
    ALLOCATOR_PROPERTIES actual;
    HRESULT hr = pAlloc->SetProperties(pProps, &actual);
    if (FAILED(hr)) return hr;
    if (actual.cbBuffer < pProps->cbBuffer) return E_FAIL;
    return S_OK;
}

HRESULT CMHCamPin::CheckMediaType(const CMediaType* pMediaType)
{
    CheckPointer(pMediaType, E_POINTER);
    if (*pMediaType->Type() != MEDIATYPE_Video) return E_INVALIDARG;
    const GUID& sub = *pMediaType->Subtype();
    bool validSub = false;
    for (int i = 0; i < kSubtypeCount; ++i) {
        if (sub == kSubtypes[i]) { validSub = true; break; }
    }
    if (!validSub) return E_INVALIDARG;
    if (*pMediaType->FormatType() != FORMAT_VideoInfo) return E_INVALIDARG;

    VIDEOINFOHEADER* vih = (VIDEOINFOHEADER*)pMediaType->Format();
    if (!vih || pMediaType->FormatLength() < sizeof(VIDEOINFOHEADER)) return E_INVALIDARG;
    if (vih->bmiHeader.biBitCount != BitsPerPixel(sub)) return E_INVALIDARG;

    const int w = vih->bmiHeader.biWidth;
    const int h = abs(vih->bmiHeader.biHeight);
    for (int i = 0; i < kFormatCount; ++i) {
        if (w == kFormats[i].width && h == kFormats[i].height)
            return S_OK;
    }
    return E_INVALIDARG;
}

HRESULT CMHCamPin::SetMediaType(const CMediaType* pMediaType)
{
    HRESULT hr = CSourceStream::SetMediaType(pMediaType);
    if (FAILED(hr)) return hr;
    VIDEOINFOHEADER* vih = (VIDEOINFOHEADER*)pMediaType->Format();
    CAutoLock lock(&m_critSec);
    m_subtype = *pMediaType->Subtype();
    m_width = vih->bmiHeader.biWidth;
    m_height = abs(vih->bmiHeader.biHeight);
    m_topDown = (vih->bmiHeader.biHeight < 0);
    m_fps = (vih->AvgTimePerFrame > 0) ? (int)(UNITS / vih->AvgTimePerFrame) : 30;
    if (m_fps <= 0 || m_fps > 120) m_fps = 30;
    m_frameDuration = UNITS / m_fps;
    return S_OK;
}

HRESULT CMHCamPin::GetMediaType(int iPosition, CMediaType* pMediaType)
{
    CheckPointer(pMediaType, E_POINTER);
    CAutoLock lock(m_pFilter->pStateLock());
    if (iPosition < 0) return E_INVALIDARG;
    const int total = kSubtypeCount * kFormatCount;
    if (iPosition >= total) return VFW_S_NO_MORE_ITEMS;
    const int subIdx = iPosition / kFormatCount;
    const int fmtIdx = iPosition % kFormatCount;
    return MakeMediaType(pMediaType, kFormats[fmtIdx], kSubtypes[subIdx]);
}

// IAMStreamConfig ------------------------------------------------------------
STDMETHODIMP CMHCamPin::SetFormat(AM_MEDIA_TYPE* pmt)
{
    if (!pmt) return E_POINTER;
    CMediaType mt(*pmt);
    HRESULT hr = CheckMediaType(&mt);
    if (FAILED(hr)) return hr;

    VIDEOINFOHEADER* vih = (VIDEOINFOHEADER*)mt.Format();
    CAutoLock lock(&m_critSec);
    m_subtype = *mt.Subtype();
    m_width = vih->bmiHeader.biWidth;
    m_height = abs(vih->bmiHeader.biHeight);
    m_topDown = (vih->bmiHeader.biHeight < 0);
    m_fps = (vih->AvgTimePerFrame > 0) ? (int)(UNITS / vih->AvgTimePerFrame) : 30;
    if (m_fps <= 0 || m_fps > 120) m_fps = 30;
    m_frameDuration = UNITS / m_fps;
    m_mt = mt;
    return S_OK;
}

STDMETHODIMP CMHCamPin::GetFormat(AM_MEDIA_TYPE** ppmt)
{
    if (!ppmt) return E_POINTER;
    CMediaType mt;
    CamFormat cur{ m_width, m_height, m_fps };
    HRESULT hr = MakeMediaType(&mt, cur, m_subtype);
    if (FAILED(hr)) return hr;
    *ppmt = CreateMediaType(&mt);
    if (!*ppmt) return E_OUTOFMEMORY;
    return S_OK;
}

STDMETHODIMP CMHCamPin::GetNumberOfCapabilities(int* piCount, int* piSize)
{
    if (!piCount || !piSize) return E_POINTER;
    *piCount = kSubtypeCount * kFormatCount;
    *piSize = sizeof(VIDEO_STREAM_CONFIG_CAPS);
    return S_OK;
}

STDMETHODIMP CMHCamPin::GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pCaps)
{
    if (!ppmt || !pCaps) return E_POINTER;
    const int total = kSubtypeCount * kFormatCount;
    if (iIndex < 0 || iIndex >= total) return E_INVALIDARG;

    const int subIdx = iIndex / kFormatCount;
    const int fmtIdx = iIndex % kFormatCount;
    const CamFormat& f = kFormats[fmtIdx];
    const GUID& sub = kSubtypes[subIdx];

    CMediaType mt;
    HRESULT hr = MakeMediaType(&mt, f, sub);
    if (FAILED(hr)) return hr;

    *ppmt = CreateMediaType(&mt);
    if (!*ppmt) return E_OUTOFMEMORY;

    const int bpp = BitsPerPixel(sub);
    VIDEO_STREAM_CONFIG_CAPS* caps = (VIDEO_STREAM_CONFIG_CAPS*)pCaps;
    ZeroMemory(caps, sizeof(*caps));
    caps->guid = FORMAT_VideoInfo;
    caps->VideoStandard = AnalogVideo_None;
    caps->InputSize.cx = f.width;
    caps->InputSize.cy = f.height;
    caps->MinCroppingSize = caps->InputSize;
    caps->MaxCroppingSize = caps->InputSize;
    caps->CropGranularityX = 1;
    caps->CropGranularityY = 1;
    caps->CropAlignX = 0;
    caps->CropAlignY = 0;
    caps->MinOutputSize = caps->InputSize;
    caps->MaxOutputSize = caps->InputSize;
    caps->OutputGranularityX = 1;
    caps->OutputGranularityY = 1;
    caps->StretchTapsX = 0;
    caps->StretchTapsY = 0;
    caps->ShrinkTapsX = 0;
    caps->ShrinkTapsY = 0;
    caps->MinFrameInterval = UNITS / 60;
    caps->MaxFrameInterval = UNITS / 15;
    caps->MinBitsPerSecond = (LONG)min((LONGLONG)LONG_MAX, (LONGLONG)f.width * f.height * bpp * 15);
    caps->MaxBitsPerSecond = (LONG)min((LONGLONG)LONG_MAX, (LONGLONG)f.width * f.height * bpp * 60);
    return S_OK;
}

// IKsPropertySet -------------------------------------------------------------
STDMETHODIMP CMHCamPin::Set(REFGUID, DWORD, void*, DWORD, void*, DWORD) { return E_NOTIMPL; }
STDMETHODIMP CMHCamPin::Get(REFGUID guidPropSet, DWORD dwID, void*, DWORD, void* pPropData, DWORD cbPropData, DWORD* pcbReturned)
{
    if (guidPropSet != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
    if (dwID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
    if (pcbReturned) *pcbReturned = sizeof(GUID);
    if (!pPropData) return S_OK;
    if (cbPropData < sizeof(GUID)) return E_UNEXPECTED;
    *(GUID*)pPropData = PIN_CATEGORY_CAPTURE;
    return S_OK;
}
STDMETHODIMP CMHCamPin::QuerySupported(REFGUID guidPropSet, DWORD dwID, DWORD* pTypeSupport)
{
    if (guidPropSet != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
    if (dwID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
    if (pTypeSupport) *pTypeSupport = KSPROPERTY_SUPPORT_GET;
    return S_OK;
}

// ------------------------------------------------------------------ filter
CMHCamFilter::CMHCamFilter(LPUNKNOWN punk, HRESULT* phr)
    : CSource(NAME("MH Virtualcam"), punk, CLSID_MHVirtualCam)
{
    new CMHCamPin(phr, this); // CSource takes ownership via pin list
}

STDMETHODIMP CMHCamFilter::NonDelegatingQueryInterface(REFIID riid, void** ppv)
{
    if (riid == IID_IAMFilterMiscFlags) return GetInterface((IAMFilterMiscFlags*)this, ppv);
    return CSource::NonDelegatingQueryInterface(riid, ppv);
}

CUnknown* WINAPI CMHCamFilter::CreateInstance(LPUNKNOWN punk, HRESULT* phr)
{
    CMHCamFilter* p = new CMHCamFilter(punk, phr);
    if (phr && FAILED(*phr) && p) { delete p; p = nullptr; }
    return p;
}

// ------------------------------------------------------------- registration
const AMOVIESETUP_MEDIATYPE kPinTypes[] = {
    { &MEDIATYPE_Video, &MEDIASUBTYPE_YUY2 },
    { &MEDIATYPE_Video, &MEDIASUBTYPE_RGB24 },
    { &MEDIATYPE_Video, &MEDIASUBTYPE_RGB32 }
};
const AMOVIESETUP_PIN kPinInfo = {
    L"Capture", FALSE, TRUE, FALSE, FALSE, &CLSID_NULL, nullptr, 3, kPinTypes
};
const AMOVIESETUP_FILTER kFilterInfo = {
    &CLSID_MHVirtualCam, L"MH Virtualcam", MERIT_DO_NOT_USE, 1, &kPinInfo
};

CFactoryTemplate g_Templates[] = {
    { L"MH Virtualcam", &CLSID_MHVirtualCam, CMHCamFilter::CreateInstance, nullptr, &kFilterInfo }
};
int g_cTemplates = (int)(sizeof(g_Templates) / sizeof(g_Templates[0]));

// Register under Video Input Device category with PIN_CATEGORY_CAPTURE so
// Chrome / Edge / Firefox / Zoom / Teams / Discord / OBS list it reliably.
STDAPI DllRegisterServer()
{
    HRESULT hr = AMovieDllRegisterServer2(TRUE);
    if (FAILED(hr)) return hr;
    IFilterMapper2* mapper = nullptr;
    hr = CoCreateInstance(CLSID_FilterMapper2, nullptr, CLSCTX_INPROC_SERVER,
                          IID_IFilterMapper2, (void**)&mapper);
    if (SUCCEEDED(hr) && mapper) {
        IMoniker* moniker = nullptr;
        REGFILTER2 rf2 = {};
        rf2.dwVersion = 2;
        rf2.dwMerit = MERIT_DO_NOT_USE;
        rf2.cPins2 = 1;
        REGFILTERPINS2 pin = {};
        pin.dwFlags = REG_PINFLAG_B_OUTPUT;
        pin.cInstances = 1;
        pin.nMediaTypes = 3;
        const REGPINTYPES types[] = {
            { &MEDIATYPE_Video, &MEDIASUBTYPE_YUY2 },
            { &MEDIATYPE_Video, &MEDIASUBTYPE_RGB24 },
            { &MEDIATYPE_Video, &MEDIASUBTYPE_RGB32 }
        };
        pin.lpMediaType = types;
        pin.nMediums = 0;
        pin.lpMedium = nullptr;
        pin.clsPinCategory = &PIN_CATEGORY_CAPTURE;
        rf2.rgPins2 = &pin;
        hr = mapper->RegisterFilter(CLSID_MHVirtualCam, L"MH Virtualcam",
                                    &moniker, &CLSID_VideoInputDeviceCategory, nullptr, &rf2);
        if (moniker) moniker->Release();
        mapper->Release();
    }
    return hr;
}

STDAPI DllUnregisterServer()
{
    HRESULT hr = AMovieDllRegisterServer2(FALSE);
    IFilterMapper2* mapper = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_FilterMapper2, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IFilterMapper2, (void**)&mapper)) && mapper) {
        mapper->UnregisterFilter(&CLSID_VideoInputDeviceCategory, nullptr, CLSID_MHVirtualCam);
        mapper->Release();
    }
    return hr;
}

extern "C" BOOL WINAPI DllEntryPoint(HINSTANCE, ULONG, LPVOID);
BOOL APIENTRY DllMain(HANDLE hModule, DWORD reason, LPVOID lpReserved)
{
    return DllEntryPoint((HINSTANCE)hModule, reason, lpReserved);
}
