#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <vector>

#include "launch_splash.h"
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

  // Lets Dart put this window full screen and back (I-103-Q2). The
  // channel's constants say why.
  void ListenForFullScreen();

  // Puts this window full screen over its monitor, or back where it stood,
  // and says on the channel which it is now.
  void SetFullScreen(bool on);

  // The view's messages on their way to the engine: a modifier Windows has
  // let go of is let go of in the engine too (F-411), and a pen is noted for
  // its leave to be handed over (F-427, pen_leaves.h). The constants by
  // kLetGoWithWindows say why.
  static LRESULT CALLBACK LetGoWithWindows(HWND view, UINT message,
                                           WPARAM wparam, LPARAM lparam,
                                           UINT_PTR id, DWORD_PTR window);

  // A modifier key-down handed to the engine and not yet let go of: the key
  // and its shape — the scan code and the extended bit, which name the
  // physical key the engine records.
  struct HeldModifier {
    WPARAM key;
    LPARAM shape;
  };
  std::vector<HeldModifier> held_modifiers_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Where Dart says a text field took or let go of the keyboard.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      ime_channel_;

  // Where Dart asks for full screen, and hears what the window did.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Whether the window covers its monitor, and how it stood before — its
  // place, its size, whether it was maximized, and its frame's style.
  bool full_screen_ = false;
  WINDOWPLACEMENT placement_before_full_screen_ = {sizeof(WINDOWPLACEMENT)};
  LONG_PTR style_before_full_screen_ = 0;

  // Whether the app has drawn a frame, and so has someone to answer a close.
  bool app_can_answer_ = false;

  // Stands on screen from before the engine starts until its first frame.
  LaunchSplash launch_splash_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
