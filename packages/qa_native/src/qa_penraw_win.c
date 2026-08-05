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
// ABI v1: qpr_abi_version / qpr_start / qpr_stop / qpr_poll.

#ifdef _WIN32

#include <windows.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Hand-declared HID parsing ABI (hidpi.h is in the SDK, but declaring the
// three entry points we use keeps this file's "no vendor headers, no link
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

// HID digitizer usage page and the button usages we care about.
#define QPR_USAGE_PAGE_DIGITIZER 0x0D
#define QPR_USAGE_PEN 0x02
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

static HANDLE qpr_thread = NULL;
static DWORD qpr_thread_id = 0;
static HANDLE qpr_ready = NULL;
static volatile LONG qpr_started = 0;

// The latest decoded report. `seq` lets Dart tell "nothing new" from "a
// report that happens to repeat the previous flags".
static volatile LONG qpr_flags = 0;
static volatile LONG qpr_seq = 0;

// Preparsed data is per DEVICE and immutable, so one slot covers the
// normal case (a single pen digitizer) without a lock: a different
// device simply refreshes it.
static HANDLE qpr_cached_device = NULL;
static PVOID qpr_cached_preparsed = NULL;

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
  return 1;
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

__declspec(dllexport) int32_t qpr_abi_version(void) { return 1; }

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
  // The observer thread is gone, so nothing else can be reading the
  // cached descriptor.
  if (qpr_cached_preparsed != NULL) {
    HeapFree(GetProcessHeap(), 0, qpr_cached_preparsed);
    qpr_cached_preparsed = NULL;
    qpr_cached_device = NULL;
  }
}

// Snapshots the newest decoded report into [out]:
//   out[0] = flag word (QPR_FLAG_*), out[1] = monotonic report counter.
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
  return 1;
}

#endif // _WIN32
