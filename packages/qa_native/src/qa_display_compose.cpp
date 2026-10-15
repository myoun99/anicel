// The compositor kept composing on every vblank while a clock runs - what
// lands a clock's frame on the glass on the same vblank after the one it
// claimed, every time (the app's PresentPacing).
//
// 🚨WINDOWS' COMPOSITOR COMPOSES ON DEMAND (measured 2026-10-13 on a 144Hz
// screen, the compositor's own per-frame statistics against the vblank a
// frame claimed): a composition frame reaches the glass on the second vblank
// after it STARTS, and an idle compositor starts one the moment a picture is
// handed to it, a busy one only at the next vblank. So the same hand-off
// reached the glass two vblanks on or three, as the rest of the desktop
// happened to keep the compositor idle or busy - 39-47 film frames in a
// hundred a refresh off their neighbours. A compositor that is never idle
// takes every picture at the vblank after it is handed over: one visual with
// nothing in it, swaying forever on a composition target of the app's own
// window, gives it a change to show at every vblank and nothing to see.
// 🔬A flip-model test window handed over 0.5-5.5ms past a vblank: on the
// glass three vblanks on, 100 in a hundred, with a swaying visual of any
// window of any process on the screen; 45-56 in a hundred off without.
//
// C++ because DirectComposition's interfaces have no C binding. dcomp.dll is
// loaded the first time it is asked for, as dwmapi is in qa_display.c.

#include <windows.h>
#include <dcomp.h>
#include <stdint.h>

namespace {

typedef HRESULT(WINAPI* qa_dcomp_create_fn)(IUnknown*, REFIID, void**);

// The app's window: the runner's (windows/runner/win32_window.cpp names its
// class), shown, in this process.
const wchar_t kAppWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

struct Composing {
  IDCompositionDesktopDevice* device;
  IDCompositionTarget* target;
  IDCompositionVisual2* visual;
  IDCompositionAnimation* sway;
};

Composing g_composing = {nullptr, nullptr, nullptr, nullptr};

qa_dcomp_create_fn qa_dcomp_create(void) {
  static qa_dcomp_create_fn fn;
  static int tried;
  if (!tried) {
    tried = 1;
    HMODULE dcomp = LoadLibraryW(L"dcomp.dll");
    if (dcomp != nullptr) {
      fn = reinterpret_cast<qa_dcomp_create_fn>(reinterpret_cast<void*>(
          GetProcAddress(dcomp, "DCompositionCreateDevice2")));
    }
  }
  return fn;
}

BOOL CALLBACK qa_find_app_window(HWND hwnd, LPARAM found) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  wchar_t name[64];
  if (pid != GetCurrentProcessId() || !IsWindowVisible(hwnd) ||
      GetClassNameW(hwnd, name, 64) == 0 ||
      lstrcmpW(name, kAppWindowClass) != 0) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(found) = hwnd;
  return FALSE;
}

template <typename T>
void qa_release(T*& object) {
  if (object != nullptr) {
    object->Release();
    object = nullptr;
  }
}

void qa_compose_stop(void) {
  if (g_composing.target != nullptr) {
    g_composing.target->SetRoot(nullptr);
    g_composing.device->Commit();
  }
  qa_release(g_composing.sway);
  qa_release(g_composing.visual);
  qa_release(g_composing.target);
  qa_release(g_composing.device);
}

int32_t qa_compose_start(void) {
  if (g_composing.device != nullptr) {
    return 1;
  }
  const qa_dcomp_create_fn create = qa_dcomp_create();
  HWND window = nullptr;
  EnumWindows(qa_find_app_window, reinterpret_cast<LPARAM>(&window));
  if (create == nullptr || window == nullptr) {
    return 0;
  }
  Composing& c = g_composing;
  // No rendering device: the visual never has content to draw.
  if (FAILED(create(nullptr, __uuidof(IDCompositionDesktopDevice),
                    reinterpret_cast<void**>(&c.device))) ||
      FAILED(c.device->CreateTargetForHwnd(window, TRUE, &c.target)) ||
      FAILED(c.device->CreateVisual(&c.visual)) ||
      FAILED(c.device->CreateAnimation(&c.sway)) ||
      FAILED(c.sway->AddSinusoidal(0.0, 0.0f, 1.0f, 31.0f, 0.0f)) ||
      FAILED(c.visual->SetOffsetX(c.sway)) ||
      FAILED(c.target->SetRoot(c.visual)) || FAILED(c.device->Commit())) {
    qa_compose_stop();
    return 0;
  }
  return 1;
}

}  // namespace

// qa_display.c's qa_display_compose_every_vblank, on Windows.
extern "C" int32_t qa_display_compose_win(int32_t on) {
  if (on == 0) {
    qa_compose_stop();
    return 0;
  }
  return qa_compose_start();
}
