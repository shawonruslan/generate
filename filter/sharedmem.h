// sharedmem.h - Frame sharing protocol between the controller app and the
// DirectShow filter. The controller writes BGRA32 frames here; the filter
// reads them and delivers them to Chrome / Edge / Firefox / Zoom / Teams / OBS.
//
// Layout: [ MVCFrameHeader ][ BGRA32 pixel data, HeaderSize bytes in ]
// The mapping is always sized for the maximum frame (3840x2160 BGRA) so the
// output resolution can change at runtime without remapping.
#pragma once
#include <windows.h>

#define MVC_SHARED_MEM_NAME   L"Local\\MHVirtualCamFrame"
#define MVC_SHARED_MEM_NAME_A  "Local\\MHVirtualCamFrame"
#define MVC_MAGIC             0x4D485643u  // "MHVC"
#define MVC_HEADER_SIZE       256
#define MVC_MAX_WIDTH         3840
#define MVC_MAX_HEIGHT        2160
#define MVC_MAX_FRAME_BYTES   (MVC_MAX_WIDTH * MVC_MAX_HEIGHT * 4)
#define MVC_TOTAL_BYTES       (MVC_HEADER_SIZE + MVC_MAX_FRAME_BYTES)

struct MVCFrameHeader {
    volatile LONG  Magic;        // MVC_MAGIC once initialised
    volatile LONG  Width;        // current frame width  (pixels)
    volatile LONG  Height;       // current frame height (pixels)
    volatile LONG  Fps;          // target frames per second
    volatile LONG  IsActive;     // 1 = controller is streaming, 0 = idle
    volatile LONG  FrameNumber;  // increments on every new frame (low 32)
    volatile LONG  FrameNumberHi;// increments on overflow (high 32)
    volatile LONG  Writing;      // 1 while the controller is mid-copy
    BYTE           Reserved[224];
};
