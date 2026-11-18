import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 🚨★★★A SCREEN WHOSE GRAPHICS DEVICE WENT IS ONE THE APP NO LONGER DRAWS
/// ON — IT ASKS WITH WINDOWS' WINDOWS, SAVES AND STARTS AGAIN.
///
/// Board a-lost-gpu-leaves-the-window-unpainted. Flutter's Windows embedder
/// neither hears nor recovers a reset of the device its screen draws on: the
/// user's release app twice kept its sound and playhead going behind a window
/// frozen on its last picture (11-16, 11-18, NVIDIA), and on the Surface
/// (Intel, 11-18 15:08) the first frame drawn after the reset ended the
/// process. So the Windows runner watches for itself
/// (`windows/runner/lost_screen.h`) and says it here ([wentMethod]) — and
/// from then on:
///
/// - no frame is drawn (`stopDrawingTheScreen`);
/// - 🗣️Q1 (유저 2026-11-16): 「윈도 창으로 알리고 저장하고 다시 시작할지
///   묻는다」 — the app asks with a window Windows draws ([askWithWindows]),
///   and so does every window the save it runs would open: the doors of a
///   question, a notice and a wait (`askConfirm`, `showAppNotice`,
///   `runWithAppProgress`) read [hasGone];
/// - Anicel starts again for the files it saved ([startAgainFor]) — or,
///   🗣️Q5 (유저 2026-11-18): 「버튼하나 더 만들어서 저장하지 않고 종료
///   추가」, ends unsaved ([end]).
///
/// The method names are spelled again in `flutter_window.cpp`;
/// `a_lost_screen_is_heard_from_the_runner_test` reads both.
abstract final class LostScreen {
  static const channel = MethodChannel('anicel/screen');
  static const wentMethod = 'went';
  static const askMethod = 'askWithWindows';
  static const startAgainMethod = 'startAgain';
  static const endMethod = 'end';

  /// The reason Windows gave for the device going (an HRESULT), once it
  /// went this run — null till then.
  static ValueListenable<int?> get went => _went;
  static final ValueNotifier<int?> _went = ValueNotifier(null);

  /// Whether the screen's device went this run.
  static bool get hasGone => _went.value != null;

  /// Hears the runner, for the app's lifetime: `main`, once. A platform
  /// whose runner does not watch never says it.
  static void listen() {
    channel.setMethodCallHandler((call) async {
      final reason = call.arguments;
      if (call.method == wentMethod && reason is int) {
        _went.value ??= reason;
      }
      return null;
    });
  }

  /// Asks [title] and [message] with a window Windows draws, and answers
  /// the index in [buttons] of the one pressed — -1 for the window closed
  /// without one.
  static Future<int> askWithWindows(
    String title,
    String message,
    List<String> buttons,
  ) async {
    final pressed = await channel.invokeMethod<int>(askMethod, [
      title,
      message,
      ...buttons,
    ]);
    return pressed ?? -1;
  }

  /// Starts Anicel again for [files] and ends this one — and answers false,
  /// ending nothing, where the next would not start.
  static Future<bool> startAgainFor(List<String> files) async =>
      await channel.invokeMethod<bool>(startAgainMethod, files) ?? false;

  /// Ends Anicel where it stands, nothing saved: the runner ends the
  /// process without the engine's teardown, which touches the gone device.
  static Future<void> end() => channel.invokeMethod<void>(endMethod);

  /// Test seam: the screen's device gone, as the runner says it.
  @visibleForTesting
  static void debugGo([int reason = 0x887A0007]) => _went.value ??= reason;

  /// Test seam: the screen as a launch finds it.
  @visibleForTesting
  static void debugForget() => _went.value = null;
}
