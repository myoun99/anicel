// The display's own timing: where its vblanks are, and a wait that ends on
// a given microsecond - what a clock's frame needs to be handed to the GPU
// so it lands on the vblank it was made for (the app's PresentPacing).
//
// Only Windows says: there the engine begins its frames on a vsync grid of
// its own and presents without waiting for a vblank, so the compositor's
// timing (DWM) is the only word on where the real vblanks are. Everywhere
// else the engine's vsync IS the display's, and nothing here is asked for:
// qa_display_vblank answers 0 and the wait returns at once.
//
// 🚨THE COMPOSITOR HAS ONE CLOCK AND EVERY SCREEN ITS OWN VBLANKS (measured
// 2026-10-15, four screens of 144, 59.94, 59.95 and 60Hz): DWM's timing is
// that clock, so a window on a slower screen is on a grid its pictures do
// not land on. qa_display_window_screens names the vblanks of the screens
// the window lies on; the compositor's per-target statistics are the only
// word on those (Windows 11 on — without them there is no such answer, and
// the app stays on the compositor's clock as it always was).
//
// Times are in microseconds of the performance counter - the clock Dart's
// timeline reads on Windows, and so the clock the engine's frame times are
// on. The compositor stamps its vblanks with the same counter.

// NULL is <stddef.h>'s. <windows.h> brings it on Windows, so a build there
// never missed it; gcc and Apple clang stopped at the first NULL outside the
// Windows block (2026-10-15, the bundle PR's CI and the round's Apple builds).
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

#if defined(_WIN32)
#include <windows.h>

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

// DWM_TIMING_INFO as dwmapi.h declares it, packed - only the fields up to
// the vblank are read, and the call is made with the whole size. Declared
// here so the build needs neither the header's packing pragma nor an import
// library: dwmapi is loaded the first time it is asked for.
#pragma pack(push, 1)
typedef struct {
  UINT32 cbSize;
  UINT32 rateRefreshNumerator;
  UINT32 rateRefreshDenominator;
  UINT64 qpcRefreshPeriod;
  UINT32 rateComposeNumerator;
  UINT32 rateComposeDenominator;
  UINT64 qpcVBlank;
  BYTE rest[292 - 36];
} qa_dwm_timing_info;
#pragma pack(pop)

typedef HRESULT(WINAPI* qa_dwm_timing_fn)(HWND, qa_dwm_timing_info*);

static qa_dwm_timing_fn qa_dwm_timing(void) {
  static qa_dwm_timing_fn fn;
  static int tried;
  if (!tried) {
    tried = 1;
    HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
    if (dwm != NULL) {
      fn = (qa_dwm_timing_fn)(void*)GetProcAddress(
          dwm, "DwmGetCompositionTimingInfo");
    }
  }
  return fn;
}

static int64_t qa_display_frequency(void) {
  static LARGE_INTEGER frequency;
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  return frequency.QuadPart;
}

// Counter ticks to microseconds, the whole seconds and the remainder apart:
// the product of the counter and a million overflows 64 bits within hours.
static int64_t qa_display_micros(int64_t ticks) {
  const int64_t hz = qa_display_frequency();
  return (ticks / hz) * 1000000 + (ticks % hz) * 1000000 / hz;
}

static int64_t qa_display_now(void) {
  LARGE_INTEGER counter;
  QueryPerformanceCounter(&counter);
  return qa_display_micros(counter.QuadPart);
}

// COMPOSITION_FRAME_STATS, _TARGET_ID, _STATS and _TARGET_STATS as
// dcomptypes.h declares them. Declared here for the reason DWM's is: the
// build needs no recent SDK, and dcomp.dll is asked for them at run time
// because only Windows 11 has them.
typedef struct {
  UINT64 startTime;
  UINT64 targetTime;
  UINT64 framePeriod;
} qa_comp_frame_stats;

typedef struct {
  LUID displayAdapterLuid;
  LUID renderAdapterLuid;
  UINT vidPnSourceId;
  UINT vidPnTargetId;
  UINT uniqueId;
} qa_comp_target_id;

typedef struct {
  UINT presentCount;
  UINT refreshCount;
  UINT virtualRefreshCount;
  UINT64 time;
} qa_comp_stats;

typedef struct {
  UINT outstandingPresents;
  UINT64 presentTime;
  UINT64 vblankDuration;
  qa_comp_stats presentedStats;
  qa_comp_stats completedStats;
} qa_comp_target_stats;

#define QA_COMP_FRAME_ID_COMPLETED 2
#define QA_COMP_MAX_TARGETS 16

typedef HRESULT(WINAPI* qa_comp_frame_id_fn)(int, UINT64*);
typedef HRESULT(WINAPI* qa_comp_stats_fn)(UINT64, qa_comp_frame_stats*, UINT,
                                          qa_comp_target_id*, UINT*);
typedef HRESULT(WINAPI* qa_comp_target_stats_fn)(UINT64,
                                                 const qa_comp_target_id*,
                                                 qa_comp_target_stats*);

static qa_comp_frame_id_fn qa_comp_frame_id;
static qa_comp_stats_fn qa_comp_stats_of;
static qa_comp_target_stats_fn qa_comp_target_stats_of;

static int qa_comp_loaded(void) {
  static int tried;
  if (!tried) {
    tried = 1;
    HMODULE dcomp = LoadLibraryW(L"dcomp.dll");
    if (dcomp != NULL) {
      qa_comp_frame_id = (qa_comp_frame_id_fn)(void*)GetProcAddress(
          dcomp, "DCompositionGetFrameId");
      qa_comp_stats_of = (qa_comp_stats_fn)(void*)GetProcAddress(
          dcomp, "DCompositionGetStatistics");
      qa_comp_target_stats_of = (qa_comp_target_stats_fn)(void*)GetProcAddress(
          dcomp, "DCompositionGetTargetStatistics");
    }
  }
  return qa_comp_frame_id != NULL && qa_comp_stats_of != NULL &&
         qa_comp_target_stats_of != NULL;
}

// qa_display_compose.cpp: the app's window, or NULL.
HWND qa_display_app_window(void);

typedef struct {
  LUID adapter;
  UINT target;
  int64_t period_ns;
} qa_screen;

typedef struct {
  WCHAR names[QA_COMP_MAX_TARGETS][CCHDEVICENAME];
  int count;
} qa_monitor_names;

static BOOL CALLBACK qa_monitor_named(HMONITOR monitor, HDC dc, LPRECT clip,
                                      LPARAM names) {
  (void)dc;
  (void)clip;
  qa_monitor_names* found = (qa_monitor_names*)names;
  MONITORINFOEXW info;
  ZeroMemory(&info, sizeof(info));
  info.cbSize = sizeof(info);
  if (found->count < QA_COMP_MAX_TARGETS &&
      GetMonitorInfoW(monitor, (MONITORINFO*)&info)) {
    lstrcpynW(found->names[found->count], info.szDevice, CCHDEVICENAME);
    found->count += 1;
  }
  return TRUE;
}

// The screens under the window's CLIENT area: its outer rect stands 8 pixels
// past a maximized window's screen, onto whatever lies beside it.
static int qa_screens_under(HWND window, qa_screen* screens) {
  RECT client;
  POINT origin = {0, 0};
  if (!GetClientRect(window, &client) || !ClientToScreen(window, &origin)) {
    return 0;
  }
  OffsetRect(&client, origin.x, origin.y);
  qa_monitor_names names;
  names.count = 0;
  EnumDisplayMonitors(NULL, &client, qa_monitor_named, (LPARAM)&names);

  DISPLAYCONFIG_PATH_INFO paths[QA_COMP_MAX_TARGETS];
  DISPLAYCONFIG_MODE_INFO modes[QA_COMP_MAX_TARGETS * 2];
  UINT32 path_count = QA_COMP_MAX_TARGETS;
  UINT32 mode_count = QA_COMP_MAX_TARGETS * 2;
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths, &mode_count,
                         modes, NULL) != ERROR_SUCCESS) {
    return 0;
  }
  int count = 0;
  for (UINT32 i = 0; i < path_count; i += 1) {
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source;
    ZeroMemory(&source, sizeof(source));
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = paths[i].sourceInfo.adapterId;
    source.header.id = paths[i].sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS) {
      continue;
    }
    const DISPLAYCONFIG_RATIONAL rate = paths[i].targetInfo.refreshRate;
    for (int n = 0; n < names.count && rate.Numerator != 0; n += 1) {
      if (lstrcmpW(names.names[n], source.viewGdiDeviceName) == 0) {
        screens[count].adapter = paths[i].targetInfo.adapterId;
        screens[count].target = paths[i].targetInfo.id;
        screens[count].period_ns =
            (int64_t)(1e9 * rate.Denominator / rate.Numerator);
        count += 1;
        break;
      }
    }
  }
  return count;
}

// Where the window lies, read at most this often: a look asks every frame,
// and a window moves far less often than that.
#define QA_SCREENS_FRESH_US 250000

static int qa_screens_now(qa_screen* screens) {
  static qa_screen held[QA_COMP_MAX_TARGETS];
  static int count;
  static int64_t read_at;
  const int64_t now = qa_display_now();
  if (read_at == 0 || now - read_at >= QA_SCREENS_FRESH_US) {
    read_at = now;
    const HWND window = qa_display_app_window();
    count = window == NULL ? 0 : qa_screens_under(window, held);
  }
  CopyMemory(screens, held, sizeof(held));
  return count;
}

// The timer the wait sleeps on: high-resolution where the system has one
// (Windows 10 1803 on), the plain one otherwise - it only wakes coarser,
// and the spin at the end takes up the rest.
static HANDLE qa_display_timer(void) {
  static HANDLE timer;
  static int tried;
  if (!tried) {
    tried = 1;
    timer = CreateWaitableTimerExW(NULL, NULL,
                                   CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                   TIMER_ALL_ACCESS);
    if (timer == NULL) {
      timer = CreateWaitableTimerExW(NULL, NULL, 0, TIMER_ALL_ACCESS);
    }
  }
  return timer;
}
#endif

// A real vblank and the refresh period: out2[0] the vblank, in
// microseconds; out2[1] the period, in NANOseconds (a period is a fraction
// of a microsecond off a whole one, and a run counts thousands of them).
// 1 when the compositor said, 0 when there is none to ask or it refused.
QA_EXPORT int32_t qa_display_vblank(int64_t* out2) {
  if (out2 == NULL) {
    return 0;
  }
#if defined(_WIN32)
  const qa_dwm_timing_fn timing = qa_dwm_timing();
  if (timing == NULL) {
    return 0;
  }
  qa_dwm_timing_info info;
  ZeroMemory(&info, sizeof(info));
  info.cbSize = (UINT32)sizeof(info);
  if (FAILED(timing(NULL, &info)) || info.qpcRefreshPeriod == 0 ||
      info.qpcVBlank == 0) {
    return 0;
  }
  out2[0] = qa_display_micros((int64_t)info.qpcVBlank);
  out2[1] = (int64_t)((double)info.qpcRefreshPeriod * 1e9 /
                      (double)qa_display_frequency());
  return 1;
#else
  return 0;
#endif
}

// The screens the app's window lies on, at most [max]: out[2n] a real vblank
// of the n-th, in microseconds, out[2n + 1] its refresh period, in
// NANOseconds, as qa_display_vblank has them. The count; 0 with no app window
// to ask about, where the compositor keeps no such statistics (before
// Windows 11), and everywhere but Windows.
QA_EXPORT int32_t qa_display_window_screens(int64_t* out, int32_t max) {
  if (out == NULL) {
    return 0;
  }
#if defined(_WIN32)
  if (!qa_comp_loaded()) {
    return 0;
  }
  qa_screen screens[QA_COMP_MAX_TARGETS];
  const int count = qa_screens_now(screens);
  UINT64 frame = 0;
  qa_comp_frame_stats stats;
  qa_comp_target_id ids[QA_COMP_MAX_TARGETS];
  UINT id_count = 0;
  if (count == 0 ||
      FAILED(qa_comp_frame_id(QA_COMP_FRAME_ID_COMPLETED, &frame)) ||
      FAILED(qa_comp_stats_of(frame, &stats, QA_COMP_MAX_TARGETS, ids,
                              &id_count))) {
    return 0;
  }
  int32_t answered = 0;
  for (int s = 0; s < count && answered < max; s += 1) {
    for (UINT i = 0; i < id_count && i < QA_COMP_MAX_TARGETS; i += 1) {
      qa_comp_target_stats target;
      if (ids[i].vidPnTargetId != screens[s].target ||
          ids[i].displayAdapterLuid.LowPart != screens[s].adapter.LowPart ||
          ids[i].displayAdapterLuid.HighPart != screens[s].adapter.HighPart ||
          FAILED(qa_comp_target_stats_of(frame, &ids[i], &target)) ||
          target.presentedStats.time == 0) {
        continue;
      }
      out[2 * answered] =
          qa_display_micros((int64_t)target.presentedStats.time);
      // 🚨THE MODE'S PERIOD, NOT THE LAST REFRESH'S (2026-11-02): a screen
      // that stretches a refresh for a late picture says so in
      // vblankDuration — 16.68ms, then 18.6 — and a grid laid at 18.6 is off
      // by two milliseconds a refresh.
      out[2 * answered + 1] = screens[s].period_ns;
      answered += 1;
      break;
    }
  }
  return answered;
#else
  (void)max;
  return 0;
#endif
}

// Blocks the calling thread until [deadline_us] on qa_display_vblank's
// clock: the timer sleeps to within half a millisecond of it (its
// resolution), a spin takes the rest. Gives up a little after the timer was
// due, whatever the timer does. Returns at once where there is no display
// to wait for.
QA_EXPORT void qa_display_wait_until_us(int64_t deadline_us) {
#if defined(_WIN32)
  const int64_t spin_us = 500;
  const int64_t sleep_us = deadline_us - spin_us - qa_display_now();
  const HANDLE timer = qa_display_timer();
  if (sleep_us > 0 && timer != NULL) {
    LARGE_INTEGER due;
    // Relative due times are negative, in 100ns units.
    due.QuadPart = -sleep_us * 10;
    if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
      WaitForSingleObject(timer, (DWORD)(sleep_us / 1000 + 2));
    }
  }
  while (qa_display_now() < deadline_us) {
    YieldProcessor();
  }
#else
  (void)deadline_us;
#endif
}

#if defined(_WIN32)
// qa_display_compose.cpp: DirectComposition has no C binding.
int32_t qa_display_compose_win(int32_t on);
#endif

// Keeps the compositor composing on every vblank (on != 0), or lets it rest
// again (0) - so a picture handed over between two vblanks is taken at the
// second of them, however idle the rest of the desktop leaves it
// (qa_display_compose.cpp has the measurement). 1 while it is kept
// composing, 0 when it rests or cannot be kept: where there is no app
// window to compose on, and everywhere but Windows, whose compositors take
// their frames on the display's own vsync.
QA_EXPORT int32_t qa_display_compose_every_vblank(int32_t on) {
#if defined(_WIN32)
  return qa_display_compose_win(on);
#else
  (void)on;
  return 0;
#endif
}
