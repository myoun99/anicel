#include "flutter_window.h"

#include <commctrl.h>
#include <flutter/standard_method_codec.h>
#include <imm.h>

#include <algorithm>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

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

// 🚨★★★I-57-Q3 — THE ACCESSIBILITY TREE WAITS FOR A SCREEN READER.
//
// 유저 2026-10-15: 「스크린리더가 켜져 있을 때만 받는다 — 릴리즈도」. Windows
// turns the tree on for any Flutter window whatever speaks UI Automation asks
// (an IME does), so the app takes that request only while the flag Narrator,
// NVDA and JAWS raise is up (lib/src/ui/platform_semantics_gate.dart). The
// flag changes with a WM_SETTINGCHANGE for SPI_SETSCREENREADER, sent to every
// top-level window: the runner says so on this channel, and the app reads the
// flag again. test/ui/windows_takes_semantics_only_for_a_screen_reader_test.dart
// reads this literal and sends it to the app.
constexpr char kScreenReaderChannel[] = "anicel/screen_reader";

// 🚨★★★F-427 — A WINDOW THAT HEARS AGAIN SAYS SO.
//
// 유저 2026-10-21: 「펜으로는 그리거나 패널열거나 다 가능한데 마우스로 아무
// 조작도 안먹히는 상황이 찾아옴 … 입력 인스펙터 켜보니 펜은 정상인데
// 마우스는 움직여도 아예 아무 줄도 갱신안됨」.
//
// The app keeps a mouse out while a pen is in range (F-400,
// lib/src/ui/input/pen_echoes.dart): Windows echoes the pen as a mouse. A
// pen's range ends at the removal the engine (Flutter 3.47.4,
// flutter_window.cc) sends on the view's WM_POINTERLEAVE — and a window
// Windows has disabled, under a file dialog a pen tapped open, hears no
// WM_POINTERLEAVE. A pen that left while the dialog was up stayed in range
// to the app until it restarted, and every real mouse was its echo.
// 🧪tool/probe/pen_probe_main.dart drives that into this runner.
//
// So when the window is enabled again the runner says so on this channel,
// and every pen the app holds in range leaves; one still over the window
// comes back with its next move. ⛔Not by handing the engine the leave it
// missed: the engine reads the pointer's information for it, and Windows
// drops that for a pen pressed as the dialog came up — the probe kept that
// pen in range so. test/ui/input/pen_echoes_test.dart reads this literal
// and sends it to the app.
constexpr char kWindowHearsAgainChannel[] = "anicel/window_hears_again";

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

// 🗣️I-103-Q2 — THE WINDOW GOES FULL SCREEN WHEN DART SAYS SO.
//
// 유저 2026-10-16: 「데스크톱만 켜고 끄기, 모바일은 지금처럼 늘 전체 화면」.
// On, the frame, the title bar and the taskbar give way and the window
// covers its monitor; off, it is back where it stood, at its size, maximized
// if it was. Raymond Chen's way ("How do I switch a window between normal
// and fullscreen?"): the overlapped-window style off and the monitor's whole
// rect on, the placement kept to come back to.
//
// The runner says what the window did on the same channel
// (kFullScreenChanged) — as the Mac's and Linux's runners say what their
// OS's own switch did — and Dart's mark follows that, never the asking.
// test/architecture/the_window_is_switched_one_way_test.dart reads these.
constexpr char kWindowChannel[] = "anicel/window";
constexpr char kSetFullScreen[] = "setFullScreen";
constexpr char kFullScreenChanged[] = "fullScreenChanged";

// 🗣️I-116 — THE WINDOW OPENS WHERE THE LAST RUN LEFT IT.
//
// 유저 2026-10-21: 「닫고 열때 마지막크기/위치로 열고싶음」. Once the window
// has moved or changed size the runner says its placement — the normal rect
// in workspace coordinates and whether it is maximized — and Dart keeps it
// (lib/src/native/window_place.dart); at the next start Dart hands it back
// before the first frame, and the window is placed while still hidden.
// SetWindowPlacement puts a rect no monitor shows any longer onto one that
// does. A full-screen window says nothing: what it comes back to is the
// placement kept for that. test/architecture/the_window_keeps_its_place_test.dart
// reads these.
constexpr char kWindowPlaceChannel[] = "anicel/window_place";
constexpr char kSetPlace[] = "setPlace";
constexpr char kPlaceChanged[] = "placeChanged";

// I-106 (user, 2026-10-21): the launch splash says the stages Dart runs —
// [face files, name] — after the two the runner says itself
// (lib/src/native/launch_splash.dart says why).
constexpr char kLaunchChannel[] = "anicel/launch";
constexpr char kSayStage[] = "stage";

// 🗣️open-door-windows-open-with-Q1 — A FILE OPENED WITH ANICEL WHILE ONE RUNS
// OPENS IN THAT ONE.
//
// 유저 2026-10-22 (board): 「떠 있는 창의 새 탭으로」. For a file opened from
// the Explorer Windows starts another Anicel, whoever is running; that one
// hands its paths to the running window (main.cpp, HandToTheRunningWindow)
// and ends before it makes a window of its own. This window takes them in a
// WM_COPYDATA tagged kHandedFilesTag and says them to Dart on this channel,
// where they go through the one door a drop goes through — as the files a
// launch is handed do (lib/src/native/handed_files.dart). It carries
// kRunningWindowProp only from its first frame on: before that nothing in
// Dart hears the channel, and a second Anicel opens the file itself.
// test/architecture/a_file_opened_again_joins_the_running_window_test.dart
// reads these.
constexpr char kHandedFilesChannel[] = "anicel/handed_files";
constexpr char kOpenHanded[] = "open";

// 🚨★★★A SCREEN WHOSE DEVICE WENT (lost_screen.h says why the runner
// watches). The runner says so on this channel — once, the reason Windows
// gave and the moment the watch saw it, [int32, int64 ms since 1970 UTC]
// (H63 ③) — and Dart asks the user with Windows' own windows and has the
// runner start Anicel again for the files it saved
// (a-lost-gpu-leaves-the-window-unpainted-Q1), or end it unsaved (Q5). And
// Dart asks whether the watch's device stands, now, before it draws a pixel
// of its own to read back (a-real-gpu-reset-went-unheard-on-the-main-pc-Q1).
// test/architecture/a_lost_screen_is_heard_from_the_runner_test.dart reads
// these literals.
constexpr char kScreenChannel[] = "anicel/screen";
constexpr char kScreenWent[] = "went";
constexpr char kAskWithWindows[] = "askWithWindows";
constexpr char kStartAgain[] = "startAgain";
constexpr char kEnd[] = "end";
constexpr char kScreenStands[] = "stands";
// Posted by the watch's thread: the channel speaks on this one.
constexpr UINT kScreenWentMessage = WM_APP + 0x153;
// 🚨THE ENGINE'S OWN WORD THAT ITS SCREEN'S CONTEXT IS LOST, heard where the
// engine is the one Anicel builds (tool/flutter_engine/3.47.4, patch 0002):
// an EGL call of the embedder's that fails by EGL_CONTEXT_LOST posts every
// top-level window of the process the message registered by this name, its
// WPARAM the EGL error. Flutter's own engine posts none, and the watch above
// is all that speaks. Said on the channel as the engine's
// (kScreenContextLost) with the moment the runner heard it: the app does by
// it what it does by the watch's word, and writes who said it.
// 🗣️유저 2026-11-22 (board a-real-gpu-reset-went-unheard-on-the-main-pc):
// 「그게 젤 근본해결이고 버전고정되고 올릴때마다 신경써야하는건
// 이해하고있고」 — the engine is mended, and this is its first step.
// test/architecture/a_lost_screen_is_heard_from_the_runner_test.dart reads
// the name here and in the patch.
constexpr char kScreenContextLost[] = "contextLost";
constexpr wchar_t kEngineContextLostMessage[] =
    L"FlutterWindowsEglContextLost";

// 🚨★★★WHERE THE ENGINE RESTORES, THE WORD OF A LOSS WAITS FOR ITS ANSWER.
// 🗣️유저 2026-11-22 (board a-real-gpu-reset-went-unheard-on-the-main-pc,
// relayed): 「Flutter 윈도 엔진을 고쳐 화면이 돌아오게 한다」 — step two, the
// screen comes back without Anicel starting again. The engine Anicel builds
// (patch 0005) makes its context anew once it hears a loss, and posts every
// top-level window of the process the message registered by this name: its
// WPARAM 1 where it renders again, 0 where not. A library that exports
// kEngineToldOfALoss is such an engine (the patch says so of it).
//
// So, where the engine restores, the first word of a loss — the watch's or
// the engine's own — is not said to Dart but held (HearTheScreenGo); the
// watch's word is passed to the engine, which may not have heard of the
// loss at all (an app that draws nothing makes no EGL call that fails). The
// answer decides: it stands again, and Dart hears kScreenContextRestored
// with the word held and the moment it stood; it does not, or says nothing
// within kEngineAnswersWithin, and Dart hears the word held, as it is said
// where the engine is Flutter's own — the ask, the save and the start again
// stand as they are. ⏳The time is 공통's (11-23), not measured: the engine
// itself waits at most 2 s twice for its raster thread, then makes the
// display anew and draws.
// test/architecture/a_lost_screen_is_heard_from_the_runner_test.dart reads
// these literals, and the names in the patch.
constexpr char kScreenContextRestored[] = "contextRestored";
constexpr wchar_t kEngineContextRestoredMessage[] =
    L"FlutterWindowsEglContextRestored";
constexpr char kEngineToldOfALoss[] = "FlutterDesktopGLContextWasLost";
constexpr UINT kEngineAnswersWithin = 8000;
// The timer that waits for the answer.
constexpr UINT_PTR kEngineAnswerTimer = 0x154;

// 🚨★★★F-411 — A MODIFIER WINDOWS LET GO OF IS LET GO OF IN THE ENGINE TOO.
//
// 유저 2026-10-19: 「입력 인스펙터 확인하니 보통은 D held [D]라면 D held
// [Shift right, D] 라고 되있었음 … 다른 앱 … 정상으로 쉬프트없이 q라고
// 입력됨 … 앱 재기동하니까 해결되있음」.
//
// The engine (Flutter 3.47.4, keyboard_key_embedder_handler.cc) records a key
// by its physical key — the scan code and the extended bit — and before every
// key event syncs Shift, Ctrl, Alt and the Windows keys to GetKeyState. But
// it syncs ONE physical key per virtual key, the last one it saw
// (UpdateLastSeenCriticalKey). A key-down of another shape — the fake Shift
// Windows sends round a gray arrow while Shift is held, E0 36 for the right
// one — is a key of its own there, named Shift Right; the real Shift going up
// makes the real key the last seen, and nothing lets the other go. Every
// reader of the record (the shortcut table, the framework's own shortcuts,
// ModifierKeys) then holds Shift until the app restarts, while Windows and
// every other app do not. 🧪tool/probe/shift_probe_main.dart drives that
// shape into this runner: before this, D held [Shift Right, Key D].
//
// So the runner sees the view's key messages before the engine, keeps each
// modifier key-down it hands over by its shape, and once Windows says that
// key is up hands the engine the same shape's key-up — the way the engine
// itself forges Ctrl Left's up round AltGr (keyboard_manager.cc). An up the
// engine holds nothing for it drops (`had_record`), so one too many costs
// nothing. ⛔Not by dropping the extended Shift messages: that is one shape
// that leaves a key behind, not the only one the record can be handed.
constexpr UINT_PTR kLetGoWithWindows = 0x411;

// The bits of a key message's LPARAM that name its physical key: the scan
// code (16-23) and the extended bit (24).
constexpr LPARAM kKeyShape = 0x01FF0000;

// A key-up's other bits: one stroke, the key was down, and it goes up.
constexpr LPARAM kKeyUp = static_cast<LPARAM>(0xC0000001);

// What GetKeyState is asked of a modifier's key message — either side of
// Shift, Ctrl and Alt as one, as Windows names them in the message; each
// Windows key alone. 0 for a key that is no modifier.
int ModifierAskedOf(WPARAM key) {
  switch (key) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
      return VK_SHIFT;
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
      return VK_CONTROL;
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
      return VK_MENU;
    case VK_LWIN:
    case VK_RWIN:
      return static_cast<int>(key);
    default:
      return 0;
  }
}

bool IsKeyMessage(UINT message) {
  return message == WM_KEYDOWN || message == WM_SYSKEYDOWN ||
         message == WM_KEYUP || message == WM_SYSKEYUP;
}

// The id Windows gives the engine's message (kEngineContextLostMessage) this
// session — the same to every caller that registers the name. Zero where it
// would not register.
UINT EngineContextLostMessage() {
  static const UINT message =
      ::RegisterWindowMessageW(kEngineContextLostMessage);
  return message;
}

// The id of the engine's answer (kEngineContextRestoredMessage), as above.
UINT EngineContextRestoredMessage() {
  static const UINT message =
      ::RegisterWindowMessageW(kEngineContextRestoredMessage);
  return message;
}

// The engine's door to be told of a loss (kEngineToldOfALoss) — null where
// the engine does not restore, Flutter's own among them.
using TellTheEngine = void (*)();
TellTheEngine EngineThatRestores() {
  static const TellTheEngine tell = [] {
    const HMODULE engine = ::GetModuleHandleW(L"flutter_windows.dll");
    return engine == nullptr ? nullptr
                             : reinterpret_cast<TellTheEngine>(
                                   ::GetProcAddress(engine, kEngineToldOfALoss));
  }();
  return tell;
}

// Says on |channel| by |method| that the screen went: the reason and the
// moment, [int32, int64 ms since 1970 UTC]. Nothing before Dart is listened
// for.
void SayTheScreenWent(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const char* method,
    WPARAM reason,
    LPARAM seen_at) {
  if (channel == nullptr) {
    return;
  }
  channel->InvokeMethod(
      method,
      std::make_unique<flutter::EncodableValue>(flutter::EncodableList{
          flutter::EncodableValue(static_cast<int32_t>(reason)),
          flutter::EncodableValue(static_cast<int64_t>(seen_at)),
      }));
}

// Says on |channel| that the screen stood again in a context made anew:
// the word of the loss as it would have been said ([int32 reason, int64
// seen at, the method it is said by]) and the moment it stood, [int64].
void SayTheScreenStoodAgain(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const char* said_by,
    WPARAM reason,
    LPARAM seen_at,
    LPARAM stood_at) {
  if (channel == nullptr) {
    return;
  }
  channel->InvokeMethod(
      kScreenContextRestored,
      std::make_unique<flutter::EncodableValue>(flutter::EncodableList{
          flutter::EncodableValue(static_cast<int32_t>(reason)),
          flutter::EncodableValue(static_cast<int64_t>(seen_at)),
          flutter::EncodableValue(std::string(said_by)),
          flutter::EncodableValue(static_cast<int64_t>(stood_at)),
      }));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Before the engine starts: starting it is the wait the splash covers.
  launch_splash_.Show(
      ::MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTOPRIMARY));
  launch_splash_.SayRunnerStage(0);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  launch_splash_.SayRunnerStage(1);
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  ListenForTheIme(flutter_controller_->view()->GetNativeWindow());
  ListenForFullScreen();
  ListenForPlace();
  ListenForLaunchStages();
  ListenForTheScreen();
  files_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kHandedFilesChannel,
          &flutter::StandardMethodCodec::GetInstance());
  ::SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                      LetGoWithWindows, kLetGoWithWindows,
                      reinterpret_cast<DWORD_PTR>(this));

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Maximized when the last run left it so, and not full screen over it.
    ::ShowWindow(GetHandle(), show_maximized_ && !full_screen_
                                  ? SW_SHOWMAXIMIZED
                                  : SW_SHOWNORMAL);
    // After the window shows, so the screen is never left with neither.
    launch_splash_.Close();
    // A frame means Dart is running, and its platform channel is listening.
    app_can_answer_ = true;
    // And it hears the files a second Anicel hands over.
    ::SetPropW(GetHandle(), kRunningWindowProp, reinterpret_cast<HANDLE>(1));
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // A window going away takes no more files.
  if (GetHandle()) {
    ::RemovePropW(GetHandle(), kRunningWindowProp);
  }
  // The watch posts to this window, which is going.
  screen_watch_ = nullptr;
  // The channels speak through the engine's messenger, so they go first.
  screen_channel_ = nullptr;
  ime_channel_ = nullptr;
  window_channel_ = nullptr;
  place_channel_ = nullptr;
  launch_channel_ = nullptr;
  files_channel_ = nullptr;
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
  if (message == kScreenWentMessage) {
    HearTheScreenGo(kScreenWent, wparam, lparam);
    return 0;
  }
  // The engine's word carries no moment: the runner's, as it hears it.
  if (const UINT lost = EngineContextLostMessage();
      lost != 0 && message == lost) {
    HearTheScreenGo(kScreenContextLost, wparam, UnixMillisecondsNow());
    return 0;
  }
  if (const UINT restored = EngineContextRestoredMessage();
      restored != 0 && message == restored) {
    HearTheEngineAnswer(wparam == 1);
    return 0;
  }
  if (message == WM_TIMER && wparam == kEngineAnswerTimer) {
    HearTheEngineAnswer(false);
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
    case WM_DPICHANGED:
      // A placement handed back is already in the pixels of the monitor
      // it lands on; the size Windows suggests would scale it twice.
      if (placing_) {
        return 0;
      }
      break;
    case WM_ENTERSIZEMOVE:
      sizing_ = true;
      break;
    case WM_EXITSIZEMOVE:
      sizing_ = false;
      SayPlace();
      break;
    case WM_WINDOWPOSCHANGED: {
      // Maximized, snapped or moved by a key: once, not at every step of a
      // drag, which WM_EXITSIZEMOVE says at its end.
      const auto* pos = reinterpret_cast<const WINDOWPOS*>(lparam);
      if (!sizing_ && (~pos->flags & (SWP_NOMOVE | SWP_NOSIZE))) {
        SayPlace();
      }
      break;
    }
    case WM_ENABLE:
      if (wparam && flutter_controller_) {
        flutter_controller_->engine()->messenger()->Send(
            kWindowHearsAgainChannel, nullptr, 0);
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data && data->dwData == kHandedFilesTag && files_channel_) {
        SayHandedFiles(*data);
        return TRUE;
      }
      break;
    }
    case WM_SETTINGCHANGE:
      if (wparam == SPI_SETSCREENREADER && flutter_controller_) {
        flutter_controller_->engine()->messenger()->Send(kScreenReaderChannel,
                                                         nullptr, 0);
      }
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

LRESULT CALLBACK FlutterWindow::LetGoWithWindows(HWND view, UINT message,
                                                 WPARAM wparam, LPARAM lparam,
                                                 UINT_PTR id,
                                                 DWORD_PTR window) {
  if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(view, LetGoWithWindows, id);
  } else if (IsKeyMessage(message)) {
    std::vector<HeldModifier>& held =
        reinterpret_cast<FlutterWindow*>(window)->held_modifiers_;
    const LPARAM shape = lparam & kKeyShape;
    const auto is_this_key = [wparam, shape](const HeldModifier& modifier) {
      return modifier.key == wparam && modifier.shape == shape;
    };
    // Before this key reaches the engine, so it is read with the modifiers
    // Windows holds.
    std::vector<HeldModifier> let_go;
    for (auto it = held.begin(); it != held.end();) {
      if (!is_this_key(*it) && ::GetKeyState(ModifierAskedOf(it->key)) >= 0) {
        let_go.push_back(*it);
        it = held.erase(it);
      } else {
        ++it;
      }
    }
    for (const HeldModifier& modifier : let_go) {
      ::DefSubclassProc(view, WM_KEYUP, modifier.key, modifier.shape | kKeyUp);
    }
    if (ModifierAskedOf(wparam) != 0) {
      const auto same = std::find_if(held.begin(), held.end(), is_this_key);
      const bool down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
      if (down && same == held.end()) {
        held.push_back({wparam, shape});
      } else if (!down && same != held.end()) {
        held.erase(same);
      }
    }
  }
  return ::DefSubclassProc(view, message, wparam, lparam);
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

void FlutterWindow::ListenForLaunchStages() {
  launch_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kLaunchChannel,
          &flutter::StandardMethodCodec::GetInstance());
  launch_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* said =
            std::get_if<flutter::EncodableList>(call.arguments());
        const std::string* face =
            said && said->size() == 2 ? std::get_if<std::string>(&(*said)[0])
                                      : nullptr;
        const std::string* name =
            said && said->size() == 2 ? std::get_if<std::string>(&(*said)[1])
                                      : nullptr;
        if (call.method_name() != kSayStage || !face || !name) {
          result->NotImplemented();
          return;
        }
        launch_splash_.SayStage(*face, *name);
        result->Success();
      });
}

void FlutterWindow::ListenForTheScreen() {
  screen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kScreenChannel,
          &flutter::StandardMethodCodec::GetInstance());
  screen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        // No words: the watch's device, asked now (ScreenWatch::Stands).
        if (call.method_name() == kScreenStands) {
          result->Success(flutter::EncodableValue(
              screen_watch_ != nullptr && screen_watch_->Stands()));
          return;
        }
        const auto* said =
            std::get_if<flutter::EncodableList>(call.arguments());
        std::vector<std::wstring> words;
        for (const flutter::EncodableValue& word :
             said ? *said : flutter::EncodableList()) {
          const auto* text = std::get_if<std::string>(&word);
          if (!text) {
            result->Error("not-words");
            return;
          }
          words.push_back(Utf16FromUtf8(*text));
        }
        // [title, message, button...]: the index of the button pressed.
        if (call.method_name() == kAskWithWindows && words.size() >= 3) {
          const std::vector<std::wstring> buttons(words.begin() + 2,
                                                  words.end());
          result->Success(flutter::EncodableValue(
              AskWithWindows(GetHandle(), words[0], words[1], buttons)));
          return;
        }
        // [file...]: answers only where the next Anicel would not start.
        if (call.method_name() == kStartAgain) {
          result->Success(
              flutter::EncodableValue(StartAgainFor(GetHandle(), words)));
          return;
        }
        if (call.method_name() == kEnd) {
          EndThisProcess();
          return;
        }
        result->NotImplemented();
      });
  WatchTheScreen();
}

void FlutterWindow::WatchTheScreen() {
  // Only on the adapter Flutter says it draws on: a device on another would
  // hear another GPU's resets.
  IDXGIAdapter* adapter = nullptr;
  if (flutter_controller_->engine()->GetGraphicsAdapter(&adapter)) {
    screen_watch_ =
        std::make_unique<ScreenWatch>(adapter, GetHandle(), kScreenWentMessage);
    adapter->Release();
  }
}

void FlutterWindow::HearTheScreenGo(const char* method,
                                    WPARAM reason,
                                    LPARAM seen_at) {
  const TellTheEngine tell = EngineThatRestores();
  if (tell == nullptr) {
    SayTheScreenWent(screen_channel_.get(), method, reason, seen_at);
    return;
  }
  // Of the loss that was answered, or of the one held: one loss, whoever
  // says it first.
  if (seen_at <= stood_again_at_ || held_word_.has_value()) {
    return;
  }
  held_word_ = HeldWord{method, reason, seen_at};
  ::SetTimer(GetHandle(), kEngineAnswerTimer, kEngineAnswersWithin, nullptr);
  // The engine says a loss once till it stands again: told of the one it
  // said itself, it does nothing more.
  tell();
}

void FlutterWindow::HearTheEngineAnswer(bool stands) {
  ::KillTimer(GetHandle(), kEngineAnswerTimer);
  // An answer to no word held: one after the time ran out, which Dart was
  // told of as a loss, and asks of.
  if (!held_word_.has_value()) {
    return;
  }
  const HeldWord word = *held_word_;
  held_word_.reset();
  if (!stands) {
    SayTheScreenWent(screen_channel_.get(), word.method, word.reason,
                     word.seen_at);
    return;
  }
  // The removed device's watch goes before the moment is taken: what it
  // posted, it posted before it.
  screen_watch_ = nullptr;
  stood_again_at_ = UnixMillisecondsNow();
  WatchTheScreen();
  SayTheScreenStoodAgain(screen_channel_.get(), word.method, word.reason,
                         word.seen_at, stood_again_at_);
}

void FlutterWindow::ListenForFullScreen() {
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const bool* on = std::get_if<bool>(call.arguments());
        if (call.method_name() != kSetFullScreen || on == nullptr) {
          result->NotImplemented();
          return;
        }
        SetFullScreen(*on);
        result->Success();
      });
}

void FlutterWindow::SetFullScreen(bool on) {
  HWND window = GetHandle();
  if (on && !full_screen_) {
    MONITORINFO monitor = {sizeof(monitor)};
    if (!::GetWindowPlacement(window, &placement_before_full_screen_) ||
        !::GetMonitorInfo(
            ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
      return;
    }
    // Still hidden at the start, the window is not maximized yet: what it
    // comes back to is what it will be shown as.
    if (show_maximized_ && !::IsWindowVisible(window)) {
      placement_before_full_screen_.showCmd = SW_SHOWMAXIMIZED;
    }
    style_before_full_screen_ = ::GetWindowLongPtr(window, GWL_STYLE);
    ::SetWindowLongPtr(window, GWL_STYLE,
                       style_before_full_screen_ & ~WS_OVERLAPPEDWINDOW);
    const RECT& screen = monitor.rcMonitor;
    ::SetWindowPos(window, HWND_TOP, screen.left, screen.top,
                   screen.right - screen.left, screen.bottom - screen.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    full_screen_ = true;
  } else if (!on && full_screen_) {
    ::SetWindowLongPtr(window, GWL_STYLE, style_before_full_screen_);
    ::SetWindowPlacement(window, &placement_before_full_screen_);
    ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    full_screen_ = false;
  }
  // Said whether it moved or already stood so: Dart's mark is the window's.
  window_channel_->InvokeMethod(
      kFullScreenChanged,
      std::make_unique<flutter::EncodableValue>(full_screen_));
}

void FlutterWindow::ListenForPlace() {
  place_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowPlaceChannel,
          &flutter::StandardMethodCodec::GetInstance());
  place_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* frame = std::get_if<flutter::EncodableMap>(call.arguments());
        const auto number = [frame](const char* key) -> std::optional<LONG> {
          const auto it = frame->find(flutter::EncodableValue(key));
          const double* value = it == frame->end()
                                    ? nullptr
                                    : std::get_if<double>(&it->second);
          if (value == nullptr) {
            return std::nullopt;
          }
          return static_cast<LONG>(*value);
        };
        if (call.method_name() != kSetPlace || frame == nullptr) {
          result->NotImplemented();
          return;
        }
        const auto left = number("left");
        const auto top = number("top");
        const auto width = number("width");
        const auto height = number("height");
        const auto maximized = frame->find(flutter::EncodableValue("maximized"));
        const bool* is_maximized = maximized == frame->end()
                                       ? nullptr
                                       : std::get_if<bool>(&maximized->second);
        if (!left || !top || !width || !height || !is_maximized) {
          result->NotImplemented();
          return;
        }
        SetPlace({*left, *top, *left + *width, *top + *height},
                 *is_maximized);
        result->Success();
      });
}

void FlutterWindow::SetPlace(const RECT& normal, bool maximized) {
  HWND window = GetHandle();
  WINDOWPLACEMENT placement = {sizeof(placement)};
  if (!::GetWindowPlacement(window, &placement)) {
    return;
  }
  placement.rcNormalPosition = normal;
  if (full_screen_) {
    placement_before_full_screen_.rcNormalPosition = normal;
    placement_before_full_screen_.showCmd =
        maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
    return;
  }
  const bool shown = ::IsWindowVisible(window);
  // Hidden until the first frame: placed so, and shown maximized then.
  placement.showCmd =
      !shown ? SW_HIDE : (maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  show_maximized_ = maximized;
  placing_ = true;
  ::SetWindowPlacement(window, &placement);
  placing_ = false;
}

void FlutterWindow::SayPlace() {
  HWND window = GetHandle();
  WINDOWPLACEMENT placement = {sizeof(placement)};
  if (!place_channel_ || placing_ || full_screen_ ||
      !::IsWindowVisible(window) || ::IsIconic(window) ||
      !::GetWindowPlacement(window, &placement)) {
    return;
  }
  const RECT& normal = placement.rcNormalPosition;
  flutter::EncodableMap frame = {
      {flutter::EncodableValue("left"),
       flutter::EncodableValue(static_cast<double>(normal.left))},
      {flutter::EncodableValue("top"),
       flutter::EncodableValue(static_cast<double>(normal.top))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(static_cast<double>(normal.right - normal.left))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(static_cast<double>(normal.bottom - normal.top))},
      {flutter::EncodableValue("maximized"),
       flutter::EncodableValue(placement.showCmd == SW_SHOWMAXIMIZED)},
  };
  place_channel_->InvokeMethod(
      kPlaceChanged, std::make_unique<flutter::EncodableValue>(frame));
}

void FlutterWindow::SayHandedFiles(const COPYDATASTRUCT& data) {
  const char* bytes = static_cast<const char*>(data.lpData);
  flutter::EncodableList paths;
  std::string path;
  for (DWORD i = 0; bytes && i < data.cbData; ++i) {
    if (bytes[i] != '\0') {
      path.push_back(bytes[i]);
      continue;
    }
    if (!path.empty()) {
      paths.emplace_back(path);
    }
    path.clear();
  }
  if (!path.empty()) {
    paths.emplace_back(path);
  }
  if (paths.empty()) {
    return;
  }
  files_channel_->InvokeMethod(
      kOpenHanded, std::make_unique<flutter::EncodableValue>(paths));
}
