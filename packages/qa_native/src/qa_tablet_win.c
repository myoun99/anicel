// Anicel Wintab sidecar (pen program, PEN-2) - Windows only.
//
// The CSP-style second tablet backend: talks to the tablet DRIVER
// directly through wintab32.dll, bypassing the OS pointer
// classification entirely. The app keeps consuming Flutter's pointer
// events for position/gestures; this bridge supplies the DRIVER's
// pressure/tilt stream so a pen that the OS misreports (as touch/mouse)
// still paints with full pressure.
//
// Contract (mirrors the qa_engine FFI idiom):
//   - wintab32.dll is loaded DYNAMICALLY; absence of a driver is a
//     normal, silent state (qat_available() == 0) - never a link error.
//   - The Dart side POLLS the packet queue (no window subclassing, no
//     message pump dependency): WTPacketsGet drains without CXO_MESSAGES.
//   - All Wintab structs/constants are hand-declared below (the vendor
//     header set is not in the Windows SDK; the LOGCONTEXT layout and
//     PK_* serialization order are stable, documented ABI).
//
// ABI v1: qat_abi_version / qat_available / qat_open / qat_poll /
//         qat_close / qat_device_name.

#ifdef _WIN32

#include <windows.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Hand-declared Wintab ABI (subset).
// ---------------------------------------------------------------------------

typedef DWORD WTPKT;
typedef DWORD FIX32;
typedef HANDLE HCTX;

#define WTI_DEFCONTEXT 3
#define WTI_DEVICES 100
#define WTI_DEFSYSCTX 4

#define DVC_NAME 1
#define DVC_NPRESSURE 15
#define DVC_ORIENTATION 17

#define CXO_SYSTEM 0x0001

// WTPKT field bits - packets serialize present fields in ASCENDING bit
// order; the PACKET struct below must list fields in exactly that order.
#define PK_TIME 0x0004
#define PK_BUTTONS 0x0040
#define PK_X 0x0080
#define PK_Y 0x0100
#define PK_NORMAL_PRESSURE 0x0400
#define PK_ORIENTATION 0x1000

typedef struct {
  int axMin;
  int axMax;
  int axUnits;
  FIX32 axResolution;
} QAT_AXIS;

typedef struct {
  int orAzimuth;
  int orAltitude;
  int orTwist;
} QAT_ORIENTATION;

// LOGCONTEXTW: the documented, fixed Wintab context layout.
typedef struct {
  WCHAR lcName[40];
  UINT lcOptions;
  UINT lcStatus;
  UINT lcLocks;
  UINT lcMsgBase;
  UINT lcDevice;
  UINT lcPktRate;
  WTPKT lcPktData;
  WTPKT lcPktMode;
  WTPKT lcMoveMask;
  DWORD lcBtnDnMask;
  DWORD lcBtnUpMask;
  LONG lcInOrgX;
  LONG lcInOrgY;
  LONG lcInOrgZ;
  LONG lcInExtX;
  LONG lcInExtY;
  LONG lcInExtZ;
  LONG lcOutOrgX;
  LONG lcOutOrgY;
  LONG lcOutOrgZ;
  LONG lcOutExtX;
  LONG lcOutExtY;
  LONG lcOutExtZ;
  FIX32 lcSensX;
  FIX32 lcSensY;
  FIX32 lcSensZ;
  BOOL lcSysMode;
  int lcSysOrgX;
  int lcSysOrgY;
  int lcSysExtX;
  int lcSysExtY;
  FIX32 lcSysSensX;
  FIX32 lcSysSensY;
} QAT_LOGCONTEXTW;

// Our packet: lcPktData = TIME | BUTTONS | X | Y | NORMAL_PRESSURE |
// ORIENTATION, serialized in that (ascending-bit) order.
#pragma pack(push, 1)
typedef struct {
  DWORD pkTime;
  DWORD pkButtons;
  LONG pkX;
  LONG pkY;
  UINT pkNormalPressure;
  QAT_ORIENTATION pkOrientation;
} QAT_PACKET;
#pragma pack(pop)

#define QAT_PKTDATA \
  (PK_TIME | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_ORIENTATION)

typedef UINT(WINAPI *WTInfoW_t)(UINT, UINT, LPVOID);
typedef HCTX(WINAPI *WTOpenW_t)(HWND, QAT_LOGCONTEXTW *, BOOL);
typedef BOOL(WINAPI *WTClose_t)(HCTX);
typedef int(WINAPI *WTPacketsGet_t)(HCTX, int, LPVOID);
typedef int(WINAPI *WTQueueSizeSet_t)(HCTX, int);
typedef BOOL(WINAPI *WTEnable_t)(HCTX, BOOL);
typedef BOOL(WINAPI *WTOverlap_t)(HCTX, BOOL);

static HMODULE qat_wintab = NULL;
static WTInfoW_t qat_WTInfoW = NULL;
static WTOpenW_t qat_WTOpenW = NULL;
static WTClose_t qat_WTClose = NULL;
static WTPacketsGet_t qat_WTPacketsGet = NULL;
static WTQueueSizeSet_t qat_WTQueueSizeSet = NULL;
static WTEnable_t qat_WTEnable = NULL;
static WTOverlap_t qat_WTOverlap = NULL;

static HCTX qat_ctx = NULL;
static double qat_pressure_scale = 0.0;
static int qat_altitude_max = 900; // Wintab convention: tenths of degrees.
static WCHAR qat_name[64];

static int qat_load(void) {
  if (qat_wintab != NULL) {
    return 1;
  }
  qat_wintab = LoadLibraryW(L"wintab32.dll");
  if (qat_wintab == NULL) {
    return 0;
  }
  qat_WTInfoW = (WTInfoW_t)GetProcAddress(qat_wintab, "WTInfoW");
  qat_WTOpenW = (WTOpenW_t)GetProcAddress(qat_wintab, "WTOpenW");
  qat_WTClose = (WTClose_t)GetProcAddress(qat_wintab, "WTClose");
  qat_WTPacketsGet = (WTPacketsGet_t)GetProcAddress(qat_wintab, "WTPacketsGet");
  qat_WTQueueSizeSet =
      (WTQueueSizeSet_t)GetProcAddress(qat_wintab, "WTQueueSizeSet");
  qat_WTEnable = (WTEnable_t)GetProcAddress(qat_wintab, "WTEnable");
  qat_WTOverlap = (WTOverlap_t)GetProcAddress(qat_wintab, "WTOverlap");
  if (qat_WTInfoW == NULL || qat_WTOpenW == NULL || qat_WTClose == NULL ||
      qat_WTPacketsGet == NULL) {
    FreeLibrary(qat_wintab);
    qat_wintab = NULL;
    return 0;
  }
  return 1;
}

// The top-level window of THIS process (the Flutter runner window):
// Wintab wants an HWND to scope the context to.
typedef struct {
  DWORD pid;
  HWND found;
} QAT_FINDW;

static BOOL CALLBACK qat_enum_proc(HWND hwnd, LPARAM lparam) {
  QAT_FINDW *find = (QAT_FINDW *)lparam;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == find->pid && IsWindowVisible(hwnd) &&
      GetWindow(hwnd, GW_OWNER) == NULL) {
    find->found = hwnd;
    return FALSE;
  }
  return TRUE;
}

static HWND qat_app_window(void) {
  QAT_FINDW find;
  find.pid = GetCurrentProcessId();
  find.found = NULL;
  EnumWindows(qat_enum_proc, (LPARAM)&find);
  return find.found;
}

__declspec(dllexport) int32_t qat_abi_version(void) { return 1; }

// 1 = wintab32 loads AND WTInfo reports an installed driver/device.
__declspec(dllexport) int32_t qat_available(void) {
  if (!qat_load()) {
    return 0;
  }
  return qat_WTInfoW(0, 0, NULL) != 0 ? 1 : 0;
}

// UTF-16 device name into [out] (cap in WCHARs); returns length.
__declspec(dllexport) int32_t qat_device_name(uint16_t *out, int32_t cap) {
  if (!qat_available() || out == NULL || cap <= 0) {
    return 0;
  }
  qat_name[0] = 0;
  qat_WTInfoW(WTI_DEVICES, DVC_NAME, qat_name);
  int32_t n = 0;
  while (n < cap - 1 && qat_name[n] != 0 && n < 63) {
    out[n] = (uint16_t)qat_name[n];
    n += 1;
  }
  out[n] = 0;
  return n;
}

// Opens the polling context. Returns 1 on success. Idempotent.
__declspec(dllexport) int32_t qat_open(void) {
  if (qat_ctx != NULL) {
    return 1;
  }
  if (!qat_available()) {
    return 0;
  }
  HWND hwnd = qat_app_window();
  if (hwnd == NULL) {
    return 0;
  }
  QAT_LOGCONTEXTW context;
  ZeroMemory(&context, sizeof(context));
  // A SYSTEM context is what "observe alongside the OS" actually MEANS in
  // Wintab, and the default to clone is WTI_DEFSYSCTX. The driver keeps
  // driving the system cursor - legacy mouse/Ink events go on flowing to
  // the window - while our queue fills in parallel.
  //
  // The opposite reading bricked the app: a NON-system (digitizing)
  // context is not a quiet observer, it DECLARES "this app takes the
  // tablet directly, no mouse emulation needed", so the driver stops
  // synthesizing pointer input for the window. Picking Wintab in Input
  // Settings killed the cursor outright (and the choice is persisted, so
  // a restart came up dead too).
  if (qat_WTInfoW(WTI_DEFSYSCTX, 0, &context) == 0) {
    return 0;
  }
  context.lcOptions |= (UINT)CXO_SYSTEM;
  context.lcPktData = QAT_PKTDATA;
  context.lcPktMode = 0; // absolute
  context.lcMoveMask = QAT_PKTDATA;
  qat_ctx = qat_WTOpenW(hwnd, &context, TRUE);
  if (qat_ctx == NULL) {
    return 0;
  }
  if (qat_WTQueueSizeSet != NULL) {
    qat_WTQueueSizeSet(qat_ctx, 128);
  }
  // Pressure scale from the device's normal-pressure axis.
  QAT_AXIS pressure;
  ZeroMemory(&pressure, sizeof(pressure));
  if (qat_WTInfoW(WTI_DEVICES, DVC_NPRESSURE, &pressure) != 0 &&
      pressure.axMax > pressure.axMin) {
    qat_pressure_scale = 1.0 / (double)(pressure.axMax - pressure.axMin);
  } else {
    qat_pressure_scale = 1.0 / 1023.0;
  }
  QAT_AXIS orient[3];
  ZeroMemory(orient, sizeof(orient));
  if (qat_WTInfoW(WTI_DEVICES, DVC_ORIENTATION, orient) != 0 &&
      orient[1].axMax > 0) {
    qat_altitude_max = orient[1].axMax;
  }
  return 1;
}

// Drains queued packets into [out] as records of 6 floats:
//   [pressure 0..1, tiltAzimuthDeg, tiltAltitude 0..1, timeMs, buttons,
//    reserved]
// Returns the record count (<= cap). 0 = nothing queued (or not open).
__declspec(dllexport) int32_t qat_poll(float *out, int32_t cap) {
  if (qat_ctx == NULL || out == NULL || cap <= 0) {
    return 0;
  }
  enum { kMax = 64 };
  QAT_PACKET packets[kMax];
  int want = cap < kMax ? cap : kMax;
  int got = qat_WTPacketsGet(qat_ctx, want, packets);
  for (int i = 0; i < got; i += 1) {
    float *record = out + (size_t)i * 6;
    double pressure = (double)packets[i].pkNormalPressure * qat_pressure_scale;
    if (pressure < 0.0) {
      pressure = 0.0;
    }
    if (pressure > 1.0) {
      pressure = 1.0;
    }
    record[0] = (float)pressure;
    record[1] = (float)(packets[i].pkOrientation.orAzimuth / 10.0);
    record[2] = qat_altitude_max > 0
                    ? (float)packets[i].pkOrientation.orAltitude /
                          (float)qat_altitude_max
                    : 0.0f;
    record[3] = (float)packets[i].pkTime;
    record[4] = (float)packets[i].pkButtons;
    record[5] = 0.0f;
  }
  return got;
}

__declspec(dllexport) void qat_close(void) {
  if (qat_ctx != NULL) {
    qat_WTClose(qat_ctx);
    qat_ctx = NULL;
  }
}

#endif // _WIN32
