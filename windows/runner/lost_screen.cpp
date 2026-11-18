#include "lost_screen.h"

#include <commctrl.h>
#include <d3d11_4.h>
#include <wrl/client.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

// How often the watch asks its device. Asking is a call into the runtime and
// no work on the GPU; what it costs is the moment after a reset in which the
// app does not yet know. 🔬On the Surface a frame drawn in that moment ended
// the process (11-18 15:08), so the moment is kept short.
constexpr DWORD kAskEveryMs = 100;

// Above the ids a task dialog gives its own buttons (IDOK, IDCANCEL, ...).
constexpr int kFirstButton = 100;

ComPtr<ID3D11Device> OpenOn(IDXGIAdapter* adapter) {
  ComPtr<ID3D11Device> device;
  const HRESULT hr = ::D3D11CreateDevice(
      adapter, adapter ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE,
      nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &device, nullptr, nullptr);
  return SUCCEEDED(hr) ? device : nullptr;
}

void Watch(ComPtr<ID3D11Device> device, HANDLE stop, HWND window,
           UINT message) {
  // Auto-reset: an event that fired for a device still standing must not
  // stay raised and spin the loop.
  HANDLE removed = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
  ComPtr<ID3D11Device4> device4;
  DWORD cookie = 0;
  const bool registered =
      removed != nullptr && SUCCEEDED(device.As(&device4)) &&
      SUCCEEDED(device4->RegisterDeviceRemovedEvent(removed, &cookie));
  const HANDLE waits[] = {stop, removed};
  for (;;) {
    const DWORD waited = ::WaitForMultipleObjects(registered ? 2 : 1, waits,
                                                  FALSE, kAskEveryMs);
    if (waited == WAIT_OBJECT_0) {
      break;
    }
    const HRESULT reason = device->GetDeviceRemovedReason();
    if (reason != S_OK) {
      ::PostMessageW(window, message, static_cast<WPARAM>(reason), 0);
      break;
    }
  }
  if (registered) {
    device4->UnregisterDeviceRemoved(cookie);
  }
  if (removed != nullptr) {
    ::CloseHandle(removed);
  }
}

std::wstring Quoted(const std::wstring& argument) {
  return L"\"" + argument + L"\"";
}

}  // namespace

ScreenWatch::ScreenWatch(IDXGIAdapter* adapter, HWND window, UINT message) {
  ComPtr<ID3D11Device> device = OpenOn(adapter);
  if (!device) {
    return;
  }
  stop_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (stop_ == nullptr) {
    return;
  }
  thread_ = std::thread(Watch, device, stop_, window, message);
}

ScreenWatch::~ScreenWatch() {
  if (stop_ == nullptr) {
    return;
  }
  ::SetEvent(stop_);
  if (thread_.joinable()) {
    thread_.join();
  }
  ::CloseHandle(stop_);
}

int AskWithWindows(HWND owner, const std::wstring& title,
                   const std::wstring& message,
                   const std::vector<std::wstring>& buttons) {
  std::vector<TASKDIALOG_BUTTON> made;
  for (size_t i = 0; i < buttons.size(); ++i) {
    made.push_back({kFirstButton + static_cast<int>(i), buttons[i].c_str()});
  }
  TASKDIALOGCONFIG config = {sizeof(config)};
  config.hwndParent = owner;
  config.dwFlags =
      TDF_POSITION_RELATIVE_TO_WINDOW | TDF_ALLOW_DIALOG_CANCELLATION;
  config.pszWindowTitle = L"Anicel";
  config.pszMainIcon = TD_WARNING_ICON;
  config.pszMainInstruction = title.c_str();
  config.pszContent = message.c_str();
  config.cButtons = static_cast<UINT>(made.size());
  config.pButtons = made.data();
  config.nDefaultButton = made.empty() ? 0 : made.front().nButtonID;
  int pressed = 0;
  if (FAILED(::TaskDialogIndirect(&config, &pressed, nullptr, nullptr))) {
    return -1;
  }
  const int index = pressed - kFirstButton;
  return index >= 0 && index < static_cast<int>(buttons.size()) ? index : -1;
}

bool StartAgainFor(HWND window, const std::vector<std::wstring>& files) {
  const std::wstring self = ExecutableOf(::GetCurrentProcess());
  if (self.empty()) {
    return false;
  }
  std::wstring command = Quoted(self);
  for (const std::wstring& file : files) {
    command += L" " + Quoted(file);
  }
  ::RemovePropW(window, kRunningWindowProp);
  STARTUPINFOW startup = {sizeof(startup)};
  PROCESS_INFORMATION started = {};
  if (!::CreateProcessW(self.c_str(), command.data(), nullptr, nullptr, FALSE,
                        0, nullptr, nullptr, &startup, &started)) {
    ::SetPropW(window, kRunningWindowProp, reinterpret_cast<HANDLE>(1));
    return false;
  }
  ::CloseHandle(started.hThread);
  ::CloseHandle(started.hProcess);
  // What there was to keep is saved: Dart asks for this only once every
  // save landed in its file.
  EndThisProcess();
  return true;
}

void EndThisProcess() {
  // ⛔Not by closing the window. The engine's teardown lets go of what drew
  // on the gone device, and on the Surface the first touch of it after the
  // reset ended the process in a FML_CHECK (11-18 15:08) — a crash report
  // for an end that was asked for.
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
}
