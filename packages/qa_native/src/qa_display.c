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
// Times are in microseconds of the performance counter - the clock Dart's
// timeline reads on Windows, and so the clock the engine's frame times are
// on. The compositor stamps its vblanks with the same counter.

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
