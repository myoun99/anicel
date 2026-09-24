#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Asks the app whether |window| may close, and closes it when the app lets
  // go. The WM_CLOSE case in MessageHandler says why the runner asks.
  void AskTheAppToClose(HWND window);

  // Lets Dart switch |view|'s IME on while a text field holds the keyboard
  // and off everywhere else. The channel's constants say why.
  void ListenForTheIme(HWND view);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Where Dart says a text field took or let go of the keyboard.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      ime_channel_;

  // Whether the app has drawn a frame, and so has someone to answer a close.
  bool app_can_answer_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
