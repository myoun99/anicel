#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <imm.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// 🚨★★★F-128 — THE CLOSE BUTTON ASKS THE APP, WHATEVER ELSE THE PROCESS RUNS.
//
// 유저 2026-09-14: 「그림 그렸는데 닫으려고 할때 편집한게 있으니 저장하라는
// 메시지가 언제부턴가 안뜸」.
//
// Flutter's Windows engine puts a WM_CLOSE to the app only while this window
// is the LAST parentless top-level window of the whole process
// (WindowsLifecycleManager::IsLastWindowOfProcess, Flutter 3.44). Measured on
// the Release build (2026-09-15), the process has two: this one and a hidden
// 「GDI+ Hook Window」 that GDI+ starts on a thread of its own — and pdfium.dll
// is the one bundled binary that links gdiplus.dll. So the close went straight
// to DefWindowProc, and a session with unsaved drawing closed without a word.
//
// ⛔Not by hiding, owning or re-parenting that window. It belongs to GDI+, and
// the next library with a helper window of its own would turn the question
// off again in silence. Whether the app may close is a question about THIS
// window.
//
// So the runner asks — with the framework's own question on the framework's
// own channel, spelled the way the engine's PlatformHandler spells it — and
// Dart keeps ONE door for every desktop: AppLifecycleListener.onExitRequested.
// test/ui/the_close_button_asks_the_app_test.dart reads these literals and
// sends them to the app, so the two halves cannot drift apart unseen.
constexpr char kPlatformChannel[] = "flutter/platform";
constexpr char kRequestAppExit[] =
    R"({"method":"System.requestAppExit","args":{"type":"cancelable"}})";
// What an app that lets go answers, inside the JSON codec's success envelope.
constexpr char kAppSaidExit[] = R"("response":"exit")";

// Posted instead of destroying the window inside the reply: the reply runs
// inside the engine's own dispatch, and destroying the window tears the
// engine down. The engine posts its re-sent WM_CLOSE for the same reason.
constexpr UINT kCloseApproved = WM_APP + 0x128;

// 🚨★★★I-19 ④ — THE IME LISTENS ONLY WHILE A TEXT FIELD DOES.
//
// 유저 2026-09-13: 「일본어 키보드나 한국어 상태등 키보드가 영어가 아닐때도
// 대응하도록」 — 「지금은 일본어 히라가나상태로 치면 이상한 텍스트입력기?
// 같은 게 뜸」.
//
// Flutter's Windows engine drops every key an IME takes (VK_PROCESSKEY: 「These
// key presses are considered handled and not sent to Flutter」) and never
// turns the window's IME off, so with a Japanese or Korean IME composing no
// shortcut ever sees a key, and the IME composes into a window of its own.
// Dart knows when a text field holds the keyboard (KeyboardImeSwitch) and
// says so here; the view's input context follows. The way Chromium keeps its
// IME off outside an editable field.
//
// test/ui/shortcuts/the_ime_listens_only_with_a_text_field_test.dart reads
// these literals, so the two halves cannot drift apart unseen.
constexpr char kKeyboardChannel[] = "anicel/keyboard";
constexpr char kSetImeOpen[] = "setImeOpen";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  ListenForTheIme(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    // A frame means Dart is running, and its platform channel is listening.
    app_can_answer_ = true;
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // The channel speaks through the engine's messenger, so it goes first.
  ime_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // ⚠️BEFORE the engine sees it. Where the engine WOULD ask (a process with
  // one parentless window), passing the close on as well would ask twice.
  // Until the first frame nothing in Dart can answer, so the close goes
  // through — as the engine lets it through before Dart listens.
  if (message == WM_CLOSE && flutter_controller_ && app_can_answer_) {
    AskTheAppToClose(hwnd);
    return 0;
  }
  if (message == kCloseApproved) {
    // What DefWindowProc does with a WM_CLOSE nobody stopped.
    ::DestroyWindow(hwnd);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AskTheAppToClose(HWND window) {
  const std::string request(kRequestAppExit);
  flutter_controller_->engine()->messenger()->Send(
      kPlatformChannel, reinterpret_cast<const uint8_t*>(request.data()),
      request.size(), [window](const uint8_t* reply, size_t reply_size) {
        // No answer, a cancel or an error: the window stays — which is what
        // the engine's own question does with anything but "exit".
        if (reply == nullptr) {
          return;
        }
        const std::string answer(reinterpret_cast<const char*>(reply),
                                 reply_size);
        if (answer.find(kAppSaidExit) != std::string::npos) {
          ::PostMessage(window, kCloseApproved, 0, 0);
        }
      });
}

void FlutterWindow::ListenForTheIme(HWND view) {
  ime_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kKeyboardChannel,
          &flutter::StandardMethodCodec::GetInstance());
  ime_channel_->SetMethodCallHandler(
      [view](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const bool* open = std::get_if<bool>(call.arguments());
        if (call.method_name() != kSetImeOpen || open == nullptr) {
          result->NotImplemented();
          return;
        }
        // IACE_DEFAULT hands the view its own input context back, in the
        // mode the user left it; no context at all is how Win32 turns the
        // IME off for one window.
        ::ImmAssociateContextEx(view, nullptr, *open ? IACE_DEFAULT : 0);
        result->Success();
      });
}
