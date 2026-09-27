// Anicel Raw Input pen sidecar (pen program) - Windows only.
//
// Reads the pen's BUTTON truth out of the HID digitizer report itself,
// underneath Windows Ink and underneath Wintab. The HID usage tables
// define each of these as its own usage on page 0x0D:
//
//   0x42 Tip Switch   0x44 Barrel Switch   0x45 Eraser
//   0x3C Invert       0x5A Secondary Barrel Switch
//
// so "the barrel is down" and "this is the eraser end" arrive as bits the
// hardware DECLARES, not as something inferred from pressure or from a
// vendor-specific cursor index. That is the whole reason this file
// exists: Windows Ink rewrites a barrel press into a phantom pen tap
// before Flutter ever sees it, and Wintab has no portable eraser test
// (CSR_TYPE is manufacturer-defined, and Wacom's own docs warn it
// answers with garbage on a freshly plugged tablet).
//
// And the pen's LEAN (desktop-pen-tilt): X Tilt 0x3D and Y Tilt 0x3E, read
// in the unit the descriptor declares (qa_pen_hid_axis.h). Flutter's
// Windows embedder takes POINTER_PEN_INFO's pressure and rotation and
// drops its tilt, so a brush that leans with the pen had nothing to read.
//
// PURE OBSERVATION, by construction:
//   - A message-only window on its OWN thread receives WM_INPUT. Flutter's
//     window and message loop are never touched, so nothing here can
//     change how input is delivered to the app.
//   - RIDEV_INPUTSINK, and NEVER RIDEV_NOLEGACY: the legacy WM_MOUSE*
//     messages are what the whole app actually runs on, and asking the
//     system to stop sending them would brick it exactly the way the
//     non-system Wintab context did.
//   - hid.dll is loaded DYNAMICALLY and its absence is a normal silent
//     state, same contract as wintab32.dll next door.
//
// ABI v2: qpr_abi_version / qpr_start / qpr_stop / qpr_poll.
//   v2: qpr_poll also hands over the report's tilt (see qpr_poll).

#ifdef _WIN32

#include <windows.h>
#include <stdint.h>

#include "qa_pen_hid_axis.h"

// ---------------------------------------------------------------------------
// Hand-declared HID parsing ABI (hidpi.h is in the SDK, but declaring the
// entry points we use keeps this file's "no vendor headers, no link
// dependency" shape identical to the Wintab sidecar's).
// ---------------------------------------------------------------------------

typedef USHORT QPR_USAGE;
typedef LONG QPR_NTSTATUS;

#define QPR_HIDP_STATUS_SUCCESS ((QPR_NTSTATUS)0x00110000L)
#define QPR_HIDP_REPORT_TYPE_INPUT 0

typedef QPR_NTSTATUS(WINAPI *HidP_GetUsages_t)(int report_type,
                                               QPR_USAGE usage_page,
                                               USHORT link_collection,
                                               QPR_USAGE *usage_list,
                                               PULONG usage_length,
                                               PVOID preparsed_data,
                                               PCHAR report, ULONG report_len);

// HIDP_VALUE_CAPS: the declaration of one value — its range, its unit.
// Every field is at most four bytes wide and none is a pointer, so the
// layout is the same 72 bytes in a 32-bit and a 64-bit process.
typedef struct {
  QPR_USAGE UsagePage;
  UCHAR ReportID;
  BOOLEAN IsAlias;
  USHORT BitField;
  USHORT LinkCollection;
  QPR_USAGE LinkUsage;
  QPR_USAGE LinkUsagePage;
  BOOLEAN IsRange;
  BOOLEAN IsStringRange;
  BOOLEAN IsDesignatorRange;
  BOOLEAN IsAbsolute;
  BOOLEAN HasNull;
  UCHAR Reserved;
  USHORT BitSize;
  USHORT ReportCount;
  USHORT Reserved2[5];
  ULONG UnitsExp;
  ULONG Units;
  LONG LogicalMin;
  LONG LogicalMax;
  LONG PhysicalMin;
  LONG PhysicalMax;
  USHORT UsageOrRange[8];  // The NotRange / Range union; not read here.
} QPR_VALUE_CAPS;

typedef char qpr_value_caps_is_72_bytes[sizeof(QPR_VALUE_CAPS) == 72 ? 1 : -1];

typedef QPR_NTSTATUS(WINAPI *HidP_GetSpecificValueCaps_t)(
    int report_type, QPR_USAGE usage_page, USHORT link_collection,
    QPR_USAGE usage, QPR_VALUE_CAPS *value_caps, PUSHORT value_caps_length,
    PVOID preparsed_data);

typedef QPR_NTSTATUS(WINAPI *HidP_GetUsageValue_t)(
    int report_type, QPR_USAGE usage_page, USHORT link_collection,
    QPR_USAGE usage, PULONG usage_value, PVOID preparsed_data, PCHAR report,
    ULONG report_len);

// HID digitizer usage page and the usages we care about.
#define QPR_USAGE_PAGE_DIGITIZER 0x0D
#define QPR_USAGE_PEN 0x02
#define QPR_USAGE_X_TILT 0x3D
#define QPR_USAGE_Y_TILT 0x3E
#define QPR_USAGE_INVERT 0x3C
#define QPR_USAGE_TIP_SWITCH 0x42
#define QPR_USAGE_BARREL_SWITCH 0x44
#define QPR_USAGE_ERASER 0x45
#define QPR_USAGE_SECONDARY_BARREL 0x5A

// The flag word handed to Dart.
#define QPR_FLAG_TIP 0x01
#define QPR_FLAG_BARREL 0x02
#define QPR_FLAG_ERASER 0x04
#define QPR_FLAG_INVERT 0x08
#define QPR_FLAG_SECONDARY_BARREL 0x10

static HMODULE qpr_hid = NULL;
static HidP_GetUsages_t qpr_HidP_GetUsages = NULL;
// The lean's two: allowed to be missing, since the buttons need neither.
static HidP_GetSpecificValueCaps_t qpr_HidP_GetSpecificValueCaps = NULL;
static HidP_GetUsageValue_t qpr_HidP_GetUsageValue = NULL;

static HANDLE qpr_thread = NULL;
static DWORD qpr_thread_id = 0;
static HANDLE qpr_ready = NULL;
static volatile LONG qpr_started = 0;

// The latest decoded report. `seq` lets Dart tell "nothing new" from "a
// report that happens to repeat the previous flags".
static volatile LONG qpr_flags = 0;
static volatile LONG qpr_seq = 0;

// The latest report's tilt, as ONE word so a reader never pairs one
// report's X with another's Y: bit 32 set when the report carried both
// tilts, then X and Y in hundredths of a degree as two signed 16-bit
// halves (a pen's reach is ±90°, well inside them).
static volatile LONG64 qpr_tilt = 0;

// Preparsed data is per DEVICE and immutable, so one slot covers the
// normal case (a single pen digitizer) without a lock: a different
// device simply refreshes it — and with it the tilt axes it declares.
static HANDLE qpr_cached_device = NULL;
static PVOID qpr_cached_preparsed = NULL;
static qa_hid_axis qpr_tilt_x_axis;
static qa_hid_axis qpr_tilt_y_axis;
static int qpr_device_tilts = 0;

static int qpr_load(void) {
  if (qpr_hid != NULL) {
    return 1;
  }
  qpr_hid = LoadLibraryW(L"hid.dll");
  if (qpr_hid == NULL) {
    return 0;
  }
  qpr_HidP_GetUsages =
      (HidP_GetUsages_t)GetProcAddress(qpr_hid, "HidP_GetUsages");
  if (qpr_HidP_GetUsages == NULL) {
    FreeLibrary(qpr_hid);
    qpr_hid = NULL;
    return 0;
  }
  qpr_HidP_GetSpecificValueCaps = (HidP_GetSpecificValueCaps_t)GetProcAddress(
      qpr_hid, "HidP_GetSpecificValueCaps");
  qpr_HidP_GetUsageValue =
      (HidP_GetUsageValue_t)GetProcAddress(qpr_hid, "HidP_GetUsageValue");
  return 1;
}

// How [usage] is declared on [preparsed], into [axis]; 0 when the device
// declares no such value.
static int qpr_axis_of(PVOID preparsed, QPR_USAGE usage, qa_hid_axis *axis) {
  if (qpr_HidP_GetSpecificValueCaps == NULL) {
    return 0;
  }
  // Room for a device that declares the usage in more than one report;
  // the pen's own is the first.
  QPR_VALUE_CAPS caps[8];
  USHORT length = 8;
  if (qpr_HidP_GetSpecificValueCaps(QPR_HIDP_REPORT_TYPE_INPUT,
                                    QPR_USAGE_PAGE_DIGITIZER, 0, usage, caps,
                                    &length, preparsed) !=
          QPR_HIDP_STATUS_SUCCESS ||
      length == 0) {
    return 0;
  }
  axis->bit_size = caps[0].BitSize;
  axis->logical_min = caps[0].LogicalMin;
  axis->logical_max = caps[0].LogicalMax;
  axis->physical_min = caps[0].PhysicalMin;
  axis->physical_max = caps[0].PhysicalMax;
  axis->units = caps[0].Units;
  axis->units_exp = caps[0].UnitsExp;
  return 1;
}

// [usage]'s angle in [report], in degrees, into *[degrees]; 0 when the
// report carries none (another report ID) or its axis declares no angle.
static int qpr_angle_in(PCHAR report, ULONG length, PVOID preparsed,
                        QPR_USAGE usage, const qa_hid_axis *axis,
                        double *degrees) {
  ULONG raw = 0;
  if (qpr_HidP_GetUsageValue(QPR_HIDP_REPORT_TYPE_INPUT,
                             QPR_USAGE_PAGE_DIGITIZER, 0, usage, &raw,
                             preparsed, report,
                             length) != QPR_HIDP_STATUS_SUCCESS) {
    return 0;
  }
  return qa_hid_axis_degrees(axis, raw, degrees);
}

// [degrees] as a signed 16-bit count of hundredths.
static LONG64 qpr_centi(double degrees) {
  if (degrees > 90.0) {
    degrees = 90.0;
  }
  if (degrees < -90.0) {
    degrees = -90.0;
  }
  const int centi = (int)(degrees * 100.0 + (degrees < 0 ? -0.5 : 0.5));
  return (LONG64)(uint16_t)(int16_t)centi;
}

// The tilt word for one report — 0 when it carries no tilt.
static LONG64 qpr_tilt_word(PCHAR report, ULONG length, PVOID preparsed) {
  double x = 0;
  double y = 0;
  if (!qpr_device_tilts || qpr_HidP_GetUsageValue == NULL ||
      !qpr_angle_in(report, length, preparsed, QPR_USAGE_X_TILT,
                    &qpr_tilt_x_axis, &x) ||
      !qpr_angle_in(report, length, preparsed, QPR_USAGE_Y_TILT,
                    &qpr_tilt_y_axis, &y)) {
    return 0;
  }
  return ((LONG64)1 << 32) | (qpr_centi(x) << 16) | qpr_centi(y);
}

static PVOID qpr_preparsed_for(HANDLE device) {
  if (device == qpr_cached_device && qpr_cached_preparsed != NULL) {
    return qpr_cached_preparsed;
  }
  UINT size = 0;
  if (GetRawInputDeviceInfoW(device, RIDI_PREPARSEDDATA, NULL, &size) != 0 ||
      size == 0) {
    return NULL;
  }
  PVOID data = HeapAlloc(GetProcessHeap(), 0, size);
  if (data == NULL) {
    return NULL;
  }
  if (GetRawInputDeviceInfoW(device, RIDI_PREPARSEDDATA, data, &size) ==
      (UINT)-1) {
    HeapFree(GetProcessHeap(), 0, data);
    return NULL;
  }
  if (qpr_cached_preparsed != NULL) {
    HeapFree(GetProcessHeap(), 0, qpr_cached_preparsed);
  }
  qpr_cached_device = device;
  qpr_cached_preparsed = data;
  // A lean is two tilts: a device that declares one alone reports none.
  qpr_device_tilts =
      qpr_axis_of(data, QPR_USAGE_X_TILT, &qpr_tilt_x_axis) &&
      qpr_axis_of(data, QPR_USAGE_Y_TILT, &qpr_tilt_y_axis);
  return data;
}

static void qpr_handle_input(HRAWINPUT handle) {
  UINT size = 0;
  if (GetRawInputData(handle, RID_INPUT, NULL, &size,
                      sizeof(RAWINPUTHEADER)) != 0 ||
      size == 0) {
    return;
  }
  BYTE stack_buffer[1024];
  BYTE *buffer = stack_buffer;
  BYTE *heap_buffer = NULL;
  if (size > sizeof(stack_buffer)) {
    heap_buffer = (BYTE *)HeapAlloc(GetProcessHeap(), 0, size);
    if (heap_buffer == NULL) {
      return;
    }
    buffer = heap_buffer;
  }
  if (GetRawInputData(handle, RID_INPUT, buffer, &size,
                      sizeof(RAWINPUTHEADER)) != size) {
    goto done;
  }
  RAWINPUT *raw = (RAWINPUT *)buffer;
  if (raw->header.dwType != RIM_TYPEHID) {
    goto done;
  }
  PVOID preparsed = qpr_preparsed_for(raw->header.hDevice);
  if (preparsed == NULL) {
    goto done;
  }
  const DWORD count = raw->data.hid.dwCount;
  const DWORD stride = raw->data.hid.dwSizeHid;
  if (count == 0 || stride == 0) {
    goto done;
  }
  for (DWORD i = 0; i < count; i += 1) {
    PCHAR report = (PCHAR)(raw->data.hid.bRawData + (size_t)i * stride);
    QPR_USAGE usages[32];
    ULONG usage_count = 32;
    if (qpr_HidP_GetUsages(QPR_HIDP_REPORT_TYPE_INPUT,
                           QPR_USAGE_PAGE_DIGITIZER, 0, usages, &usage_count,
                           preparsed, report,
                           stride) != QPR_HIDP_STATUS_SUCCESS) {
      continue;
    }
    LONG flags = 0;
    for (ULONG u = 0; u < usage_count; u += 1) {
      switch (usages[u]) {
        case QPR_USAGE_TIP_SWITCH:
          flags |= QPR_FLAG_TIP;
          break;
        case QPR_USAGE_BARREL_SWITCH:
          flags |= QPR_FLAG_BARREL;
          break;
        case QPR_USAGE_ERASER:
          flags |= QPR_FLAG_ERASER;
          break;
        case QPR_USAGE_INVERT:
          flags |= QPR_FLAG_INVERT;
          break;
        case QPR_USAGE_SECONDARY_BARREL:
          flags |= QPR_FLAG_SECONDARY_BARREL;
          break;
        default:
          break;
      }
    }
    InterlockedExchange64(&qpr_tilt, qpr_tilt_word(report, stride, preparsed));
    InterlockedExchange(&qpr_flags, flags);
    InterlockedIncrement(&qpr_seq);
  }

done:
  if (heap_buffer != NULL) {
    HeapFree(GetProcessHeap(), 0, heap_buffer);
  }
}

static LRESULT CALLBACK qpr_wndproc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  if (message == WM_INPUT) {
    qpr_handle_input((HRAWINPUT)lparam);
    // The system still needs its cleanup pass for this message.
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static DWORD WINAPI qpr_thread_main(LPVOID param) {
  (void)param;
  HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSW wc;
  ZeroMemory(&wc, sizeof(wc));
  wc.lpfnWndProc = qpr_wndproc;
  wc.hInstance = instance;
  wc.lpszClassName = L"AnicelPenRawSink";
  // A duplicate class registration across restarts is fine; only a real
  // failure matters.
  if (RegisterClassW(&wc) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    SetEvent(qpr_ready);
    return 0;
  }
  HWND hwnd = CreateWindowExW(0, wc.lpszClassName, NULL, 0, 0, 0, 0, 0,
                              HWND_MESSAGE, NULL, instance, NULL);
  if (hwnd == NULL) {
    SetEvent(qpr_ready);
    return 0;
  }
  RAWINPUTDEVICE device;
  device.usUsagePage = QPR_USAGE_PAGE_DIGITIZER;
  device.usUsage = QPR_USAGE_PEN;
  // INPUTSINK = deliver even when this (invisible) window is not in the
  // foreground. NOLEGACY is deliberately absent — see the file header.
  device.dwFlags = RIDEV_INPUTSINK;
  device.hwndTarget = hwnd;
  if (!RegisterRawInputDevices(&device, 1, sizeof(device))) {
    DestroyWindow(hwnd);
    SetEvent(qpr_ready);
    return 0;
  }
  InterlockedExchange(&qpr_started, 1);
  SetEvent(qpr_ready);

  MSG msg;
  while (GetMessageW(&msg, NULL, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  // Unregister before the target window dies.
  device.dwFlags = RIDEV_REMOVE;
  device.hwndTarget = NULL;
  RegisterRawInputDevices(&device, 1, sizeof(device));
  DestroyWindow(hwnd);
  InterlockedExchange(&qpr_started, 0);
  return 0;
}

__declspec(dllexport) int32_t qpr_abi_version(void) { return 2; }

// Starts the observer thread. Returns 1 when raw pen reports will flow.
// Idempotent; a machine without hid.dll or without a digitizer simply
// answers 0 and stays silent.
__declspec(dllexport) int32_t qpr_start(void) {
  if (InterlockedCompareExchange(&qpr_started, 0, 0) != 0) {
    return 1;
  }
  if (!qpr_load()) {
    return 0;
  }
  if (qpr_thread != NULL) {
    return 0; // A previous thread is still winding down.
  }
  qpr_ready = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (qpr_ready == NULL) {
    return 0;
  }
  qpr_thread = CreateThread(NULL, 0, qpr_thread_main, NULL, 0, &qpr_thread_id);
  if (qpr_thread == NULL) {
    CloseHandle(qpr_ready);
    qpr_ready = NULL;
    return 0;
  }
  // The registration either succeeded or failed by the time the thread
  // signals; 2s is a generous ceiling for window creation.
  WaitForSingleObject(qpr_ready, 2000);
  CloseHandle(qpr_ready);
  qpr_ready = NULL;
  return InterlockedCompareExchange(&qpr_started, 0, 0) != 0 ? 1 : 0;
}

__declspec(dllexport) void qpr_stop(void) {
  if (qpr_thread == NULL) {
    return;
  }
  PostThreadMessageW(qpr_thread_id, WM_QUIT, 0, 0);
  WaitForSingleObject(qpr_thread, 2000);
  CloseHandle(qpr_thread);
  qpr_thread = NULL;
  qpr_thread_id = 0;
  InterlockedExchange(&qpr_flags, 0);
  InterlockedExchange64(&qpr_tilt, 0);
  // The observer thread is gone, so nothing else can be reading the
  // cached descriptor.
  if (qpr_cached_preparsed != NULL) {
    HeapFree(GetProcessHeap(), 0, qpr_cached_preparsed);
    qpr_cached_preparsed = NULL;
    qpr_cached_device = NULL;
    qpr_device_tilts = 0;
  }
}

// Snapshots the newest decoded report into [out]:
//   out[0] = flag word (QPR_FLAG_*), out[1] = monotonic report counter,
//   and with [cap] of 5 (v2) its lean: out[2] X Tilt and out[3] Y Tilt in
//   degrees, out[4] 1 when the report carried both, 0 when it carried none.
// Returns 1 when the observer is live, 0 otherwise.
__declspec(dllexport) int32_t qpr_poll(float *out, int32_t cap) {
  if (out == NULL || cap < 2 ||
      InterlockedCompareExchange(&qpr_started, 0, 0) == 0) {
    return 0;
  }
  out[0] = (float)InterlockedCompareExchange(&qpr_flags, 0, 0);
  // Masked to 24 bits because the transport is float: past 2^24 adjacent
  // integers stop being representable and the counter would silently
  // stall, which reads as "no new report" — the exact opposite of what it
  // is for. Wrapping is harmless; only CHANGE is ever tested.
  out[1] = (float)(InterlockedCompareExchange(&qpr_seq, 0, 0) & 0xFFFFFF);
  if (cap >= 5) {
    const LONG64 tilt = InterlockedCompareExchange64(&qpr_tilt, 0, 0);
    out[2] = (float)(int16_t)(uint16_t)((tilt >> 16) & 0xFFFF) / 100.0f;
    out[3] = (float)(int16_t)(uint16_t)(tilt & 0xFFFF) / 100.0f;
    out[4] = (tilt >> 32) & 1 ? 1.0f : 0.0f;
  }
  return 1;
}

#endif // _WIN32
