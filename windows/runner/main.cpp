#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

BOOL CALLBACK FindTheRunningWindow(HWND window, LPARAM found) {
  if (::GetPropW(window, kRunningWindowProp) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(found) = window;
  return FALSE;
}

// |file| as the running Anicel can find it: a path given from a command line
// is read against THIS process's folder, which the running one does not have.
std::string Absolute(const std::string& file) {
  const int wide_length =
      ::MultiByteToWideChar(CP_UTF8, 0, file.c_str(), -1, nullptr, 0);
  if (wide_length <= 0) {
    return file;
  }
  std::wstring wide(wide_length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, file.c_str(), -1, wide.data(),
                        wide_length);
  const DWORD full_length =
      ::GetFullPathNameW(wide.c_str(), 0, nullptr, nullptr);
  if (full_length == 0) {
    return file;
  }
  std::wstring full(full_length, L'\0');
  if (::GetFullPathNameW(wide.c_str(), full_length, full.data(), nullptr) ==
      0) {
    return file;
  }
  return Utf8FromUtf16(full.c_str());
}

// 🗣️open-door-windows-open-with-Q1 (유저 2026-10-22: 「떠 있는 창의 새
// 탭으로」): the files this Anicel was started for go to the one already
// running, which brings itself forward — and this one ends. With no files,
// no running window, or one that does not take them in time, this Anicel
// runs and opens them itself. flutter_window.cpp's kHandedFilesChannel says
// the rest.
bool HandToTheRunningWindow(const std::vector<std::string>& files) {
  if (files.empty()) {
    return false;
  }
  HWND running = nullptr;
  ::EnumWindows(FindTheRunningWindow, reinterpret_cast<LPARAM>(&running));
  if (running == nullptr) {
    return false;
  }
  std::string paths;
  for (const std::string& file : files) {
    paths += Absolute(file);
    paths.push_back('\0');
  }
  COPYDATASTRUCT data = {kHandedFilesTag, static_cast<DWORD>(paths.size()),
                         paths.data()};
  DWORD_PTR taken = FALSE;
  if (!::SendMessageTimeoutW(running, WM_COPYDATA, 0,
                             reinterpret_cast<LPARAM>(&data),
                             SMTO_ABORTIFHUNG, 5000, &taken) ||
      !taken) {
    return false;
  }
  if (::IsIconic(running)) {
    ::ShowWindow(running, SW_RESTORE);
  }
  ::SetForegroundWindow(running);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // A frame's one picture is patched where it stands through Flutter GPU
  // (one-picture-per-frame, D7-2-Q3 유저 2026-10-24) — off unless asked for.
  project.set_enable_flutter_gpu(true);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (HandToTheRunningWindow(command_line_arguments)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Anicel", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
