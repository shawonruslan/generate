// filter.h - MH Virtualcam DirectShow source filter.
// Built on the DirectShow BaseClasses (CSource / CSourceStream).
// Advertises YUY2, RGB24, and RGB32 formats with proper IAMStreamConfig,
// IKsPropertySet, IAMFilterMiscFlags, and QPC-paced frame delivery for
// browsers (Chrome/Edge/Firefox) and desktop apps (Zoom/Teams/Discord/OBS).
#pragma once
#include <streams.h>
#include "sharedmem.h"

class CMHCamPin : public CSourceStream, public IAMStreamConfig, public IKsPropertySet
{
public:
    CMHCamPin(HRESULT* phr, CSource* pFilter);
    ~CMHCamPin();

    // CSourceStream
    HRESULT FillBuffer(IMediaSample* pSample) override;
    HRESULT DecideBufferSize(IMemAllocator* pAlloc, ALLOCATOR_PROPERTIES* pProps) override;
    HRESULT CheckMediaType(const CMediaType* pMediaType) override;
    HRESULT GetMediaType(int iPosition, CMediaType* pMediaType) override;
    HRESULT SetMediaType(const CMediaType* pMediaType) override;
    HRESULT OnThreadCreate() override;
    HRESULT OnThreadDestroy() override;
    STDMETHODIMP Notify(IBaseFilter* pSender, Quality q) override { return E_NOTIMPL; }

    // IUnknown for IAMStreamConfig / IKsPropertySet
    DECLARE_IUNKNOWN
    STDMETHODIMP NonDelegatingQueryInterface(REFIID riid, void** ppv) override;

    // IAMStreamConfig
    STDMETHODIMP SetFormat(AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP GetFormat(AM_MEDIA_TYPE** ppmt) override;
    STDMETHODIMP GetNumberOfCapabilities(int* piCount, int* piSize) override;
    STDMETHODIMP GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pCaps) override;

    // IKsPropertySet (required by browsers & capture apps to recognise a camera)
    STDMETHODIMP Set(REFGUID guidPropSet, DWORD dwID, void* pInstanceData, DWORD cbInstanceData,
                     void* pPropData, DWORD cbPropData) override;
    STDMETHODIMP Get(REFGUID guidPropSet, DWORD dwID, void* pInstanceData, DWORD cbInstanceData,
                     void* pPropData, DWORD cbPropData, DWORD* pcbReturned) override;
    STDMETHODIMP QuerySupported(REFGUID guidPropSet, DWORD dwID, DWORD* pTypeSupport) override;

private:
    bool    OpenSharedMemory();
    void    CloseSharedMemory();
    void    CopyFrameTo(BYTE* pData, long outSize);
    void    PaceFrame();

    HANDLE            m_hMap = nullptr;
    MVCFrameHeader*   m_pHeader = nullptr;
    const BYTE*       m_pPixels = nullptr;
    GUID              m_subtype = MEDIASUBTYPE_YUY2;
    int               m_width = 1280;
    int               m_height = 720;
    int               m_fps = 30;
    bool              m_topDown = false;
    REFERENCE_TIME    m_frameDuration = UNITS / 30;
    LONGLONG          m_frameNumber = 0;
    LARGE_INTEGER     m_qpcFreq = {};
    LARGE_INTEGER     m_nextFrameQpc = {};
    bool              m_timerResSet = false;
    CCritSec          m_critSec;
};

class CMHCamFilter : public CSource, public IAMFilterMiscFlags
{
public:
    static CUnknown* WINAPI CreateInstance(LPUNKNOWN punk, HRESULT* phr);

    DECLARE_IUNKNOWN
    STDMETHODIMP NonDelegatingQueryInterface(REFIID riid, void** ppv) override;

    // IAMFilterMiscFlags
    ULONG STDMETHODCALLTYPE GetMiscFlags() override { return AM_FILTER_MISC_FLAGS_IS_SOURCE; }

private:
    CMHCamFilter(LPUNKNOWN punk, HRESULT* phr);
};
