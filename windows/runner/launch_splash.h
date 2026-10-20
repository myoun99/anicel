#ifndef RUNNER_LAUNCH_SPLASH_H_
#define RUNNER_LAUNCH_SPLASH_H_

#include <windows.h>

#include <string>
#include <thread>
#include <vector>

// The picture that stands in the middle of the screen from the moment the
// app is launched until its window shows (I-106-Q3/Q4/Q5, user 2026-10-20:
// the teal A and the white name, nothing behind them — the desktop shows
// through — closed at the first Flutter frame, on every desktop), saying
// under the name what the launch is doing (I-106, 2026-10-21) with dots
// that turn once a second.
//
// A layered window with per-pixel alpha, on a thread of its own: the
// dots keep turning while this thread is busy starting the engine.
class LaunchSplash {
 public:
  LaunchSplash() = default;
  ~LaunchSplash();

  LaunchSplash(const LaunchSplash&) = delete;
  LaunchSplash& operator=(const LaunchSplash&) = delete;

  // Shows the splash centred on |monitor|'s work area, and returns once it
  // is on screen. Shows nothing when the picture cannot be read — the app
  // starts the same without it.
  void Show(HMONITOR monitor);

  // Says the runner's own stage |index| (0 the engine, 1 the plugins), by
  // the name the last launch left. From this thread.
  void SayRunnerStage(size_t index);

  // Says a stage Dart names, in the face of |face_files| (tab-separated,
  // relative to flutter_assets; empty is the OS's face). From this thread.
  void SayStage(const std::string& face_files, const std::string& name);

  // Takes the splash away. Safe to call when nothing is shown.
  void Close();

 private:
  void Post(std::string face_files, std::string name);

  std::thread thread_;
  HWND window_ = nullptr;

  // What the last launch left (lib/src/native/launch_splash.dart).
  std::string face_files_;
  std::vector<std::string> stage_names_;
};

#endif  // RUNNER_LAUNCH_SPLASH_H_
