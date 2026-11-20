// register_mf.cpp - Registers or removes the persistent Windows 11 Media Foundation
// virtual camera ("MH Virtualcam") via mfsensorgroup.dll!MFCreateVirtualCamera.
// Safely exits with code 0 on Windows 10 (where DirectShow filter is used instead).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfvirtualcamera.h>
#include <stdio.h>
#include <string.h>

static const wchar_t* kFriendlyName = L"HD USB Webcam";
static const wchar_t* kSourceClsid  = L"{F6A0C342-9B5D-4E10-AC34-7D801F2E5C63}";

typedef HRESULT (STDAPICALLTYPE *PFN_MFCreateVirtualCamera)(
    MFVirtualCameraType type,
    MFVirtualCameraLifetime lifetime,
    MFVirtualCameraAccess access,
    LPCWSTR friendlyName,
    LPCWSTR sourceId,
    const GUID* categories,
    ULONG categoryCount,
    IMFVirtualCamera** virtualCamera);

static void EnsureServiceRunning(const wchar_t* serviceName)
{
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) return;
    SC_HANDLE svc = OpenServiceW(scm, serviceName, SERVICE_START | SERVICE_QUERY_STATUS);
    if (svc) {
        SERVICE_STATUS status = {};
        if (QueryServiceStatus(svc, &status) && status.dwCurrentState != SERVICE_RUNNING) {
            StartServiceW(svc, 0, nullptr);
            Sleep(300);
        }
        CloseServiceHandle(svc);
    }
    CloseServiceHandle(scm);
}

int wmain(int argc, wchar_t** argv)
{
    bool uninstall = (argc > 1 && (_wcsicmp(argv[1], L"--uninstall") == 0 || _wcsicmp(argv[1], L"-u") == 0));

    HMODULE hMod = LoadLibraryW(L"mfsensorgroup.dll");
    if (!hMod) {
        wprintf(L"Windows 11 Media Foundation Virtual Camera API not available on this OS (DirectShow remains active).\n");
        return 0;
    }

    auto pfnCreate = (PFN_MFCreateVirtualCamera)GetProcAddress(hMod, "MFCreateVirtualCamera");
    if (!pfnCreate) {
        wprintf(L"MFCreateVirtualCamera not exported on this Windows build (DirectShow remains active).\n");
        FreeLibrary(hMod);
        return 0;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    bool comInit = SUCCEEDED(hr);
    MFStartup(MF_VERSION, MFSTARTUP_LITE);

    if (!uninstall) {
        EnsureServiceRunning(L"FrameServer");
        EnsureServiceRunning(L"FrameServerMonitor");
    }

    IMFVirtualCamera* vcam = nullptr;
    hr = pfnCreate(
        MFVirtualCameraType_SoftwareCameraSource,
        MFVirtualCameraLifetime_System,
        MFVirtualCameraAccess_AllUsers,
        kFriendlyName,
        kSourceClsid,
        nullptr,
        0,
        &vcam);

    if (SUCCEEDED(hr) && vcam) {
        if (uninstall) {
            hr = vcam->Remove();
            wprintf(L"MH Virtualcam MF camera remove: 0x%08X\n", (unsigned)hr);
        } else {
            hr = vcam->Start(nullptr);
            wprintf(L"MH Virtualcam MF camera start: 0x%08X\n", (unsigned)hr);
        }
        vcam->Release();
    } else {
        wprintf(L"MFCreateVirtualCamera returned 0x%08X\n", (unsigned)hr);
    }

    MFShutdown();
    if (comInit) CoUninitialize();
    FreeLibrary(hMod);
    return 0;
}
