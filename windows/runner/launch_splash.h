#ifndef RUNNER_LAUNCH_SPLASH_H_
#define RUNNER_LAUNCH_SPLASH_H_

#include <windows.h>

// The picture that stands in the middle of the screen from the moment the
// app is launched until its window shows (I-106-Q3/Q4/Q5, user 2026-10-20:
// the teal A and the white name, nothing behind them — the desktop shows
// through — closed at the first Flutter frame, on every desktop).
//
// A layered window with per-pixel alpha: the compositor draws it from the
// bitmap it was handed, so it stays on screen while this thread is busy
// starting the engine and never needs a WM_PAINT.
class LaunchSplash {
 public:
  LaunchSplash() = default;
  ~LaunchSplash();

  LaunchSplash(const LaunchSplash&) = delete;
  LaunchSplash& operator=(const LaunchSplash&) = delete;

  // Shows the splash centred on |monitor|'s work area. Shows nothing when
  // the picture cannot be read — the app starts the same without it.
  void Show(HMONITOR monitor);

  // Takes the splash away. Safe to call when nothing is shown.
  void Close();

 private:
  HWND window_ = nullptr;
};

#endif  // RUNNER_LAUNCH_SPLASH_H_
