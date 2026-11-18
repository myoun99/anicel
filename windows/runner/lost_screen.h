#ifndef RUNNER_LOST_SCREEN_H_
#define RUNNER_LOST_SCREEN_H_

#include <dxgi.h>
#include <windows.h>

#include <string>
#include <thread>
#include <vector>

// 🚨★★★A SCREEN WHOSE GRAPHICS DEVICE WENT IS TOLD BY WINDOWS, NOT BY FLUTTER.
//
// Board a-lost-gpu-leaves-the-window-unpainted. Flutter 3.47.4's Windows
// embedder neither asks for nor hears a reset of the device its screen draws
// on: a present that fails is dropped, and nothing remakes the surface or
// tells anyone (read 2026-11-16). The user's release app twice (11-16 21:08,
// 11-18 15:06, NVIDIA, nvlddmkm 153) kept its sound and playhead going behind
// a window frozen on its last picture; on the Surface (Intel, dxcap
// -forcetdr, 11-18 15:08) the window went white and the first frame after it
// ended the process in Impeller's GLES encoder (render_pass_gles.cc:844).
//
// So the runner watches for itself: a device of its own on the adapter
// Flutter draws on, which Windows removes with the screen's. 🔬Measured on the
// Surface's reset (11-18 15:08): the device was removed
// (DXGI_ERROR_DEVICE_RESET) and a new one opened on the same adapter at once
// — and the event registered for it did NOT fire; asking the device did.
// Hence both, and asked often.
class ScreenWatch {
 public:
  // Watches a device opened on |adapter|, from a thread of its own, and
  // posts |message| to |window| once — its WPARAM the removed reason — when
  // the device goes. A null |adapter| is the system's default.
  ScreenWatch(IDXGIAdapter* adapter, HWND window, UINT message);
  ~ScreenWatch();

  ScreenWatch(const ScreenWatch&) = delete;
  ScreenWatch& operator=(const ScreenWatch&) = delete;

 private:
  HANDLE stop_ = nullptr;
  std::thread thread_;
};

// 🗣️a-lost-gpu-leaves-the-window-unpainted-Q1 (유저 2026-11-16): 「윈도 창으로
// 알리고 저장하고 다시 시작할지 묻는다」 — a window Windows draws, as nothing
// Flutter draws is seen any more. A task dialog: GDI draws it, and it needs
// no graphics device. Answers the index of the button pressed in |buttons|,
// or -1 for a dialog closed without one.
int AskWithWindows(HWND owner, const std::wstring& title,
                   const std::wstring& message,
                   const std::vector<std::wstring>& buttons);

// Starts this executable again for |files| and ends this process — the
// restart of Q1's 「저장하고 다시 시작」.
//
// ⚠️|window| first stops taking handed files (kRunningWindowProp): the next
// Anicel, started for files, hands them to the window that carries it
// (main.cpp, HandToTheRunningWindow) — this one, still standing.
// Returns false, and ends nothing, where the next would not start.
bool StartAgainFor(HWND window, const std::vector<std::wstring>& files);

// Ends this process where it stands: a restart once the next Anicel
// started, and Q5's 「저장하지 않고 종료」 — 🗣️a-lost-gpu-leaves-the-window-
// unpainted-Q5 (유저 2026-11-18): 「버튼하나 더 만들어서 저장하지 않고 종료
// 추가」.
void EndThisProcess();

#endif  // RUNNER_LOST_SCREEN_H_
