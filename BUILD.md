# Build guide - MH Virtualcam

## Requirements

- Windows 10/11
- Visual Studio 2022 with these workloads:
  - **.NET desktop development** (for the controller app)
  - **Desktop development with C++** (for the DirectShow filter)
- .NET 8 SDK (installed with VS2022)

## Step 1 - DirectShow BaseClasses (one-time, for the filter only)

The filter uses Microsoft's DirectShow BaseClasses (`streams.h`,
`strmbase.lib`), which ship with the Windows classic samples:

1. Download/clone: https://github.com/microsoft/Windows-classic-samples
2. Open `Samples\Win7Samples\multimedia\directshow\baseclasses\BaseClasses.sln`
   in VS2022, build **Release x64** and **Release Win32**.
3. Set an environment variable pointing at that folder:

   `DSHOW_BASE = C:\path\to\Windows-classic-samples\Samples\Win7Samples\multimedia\directshow\baseclasses`

   (Or set the `DSHOW_BASE` property inside the filter project in VS.)

## Step 2 - Build

1. Open `MHVirtualCam.sln` in Visual Studio 2022.
2. Configuration: **Release**, Platform: **x64**. Build Solution.
   - The app restores OpenCvSharp from NuGet automatically (internet needed
     on first build).
3. Also build the **filter project alone** with Platform **Win32** so 32-bit
   apps can see the camera too.

Outputs:
- App: `app\bin\Release\net8.0-windows\MHVirtualCam.exe`
- Filter x64: `filter\x64\Release\MHVirtualCamFilter.dll`
- Filter x86: `filter\Release\MHVirtualCamFilter.dll`

## Step 3 - Register and run

1. Right-click `register-filter.bat` -> **Run as administrator**.
2. Run `MHVirtualCam.exe`.
3. Add media, press **Start Virtual Camera**, pick
   **MH Virtualcam** in Zoom/Teams/Discord/Chrome.

To remove: run `unregister-filter.bat` as administrator.

## Troubleshooting

- **Camera not listed in an app:** that app needs the other bitness DLL -
  register both x64 and Win32 builds. Restart the meeting app after
  registering.
- **Camera listed but black in Chrome/Meet:** start the controller app and
  press Start Virtual Camera first; the filter shows a dark placeholder
  until the app is streaming.
- **Teams (new) does not see DirectShow cameras for some tenants:** use the
  camera in Zoom/Discord/Chrome to verify; this is a known Teams-side
  limitation with virtual DirectShow devices, not a filter bug.
