import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Who said the screen's device went.
enum ScreenGoneBy {
  /// The runner's watch: its own device on the screen's adapter, which
  /// Windows removed (`windows/runner/lost_screen.h`).
  watch,

  /// The engine itself: an EGL call of its own failed by a lost context —
  /// said only by the engine Anicel builds
  /// (`tool/flutter_engine/3.47.4`, patch 0002).
  engine,

  /// The app itself: a pixel drawn on the screen's own context was not said
  /// back (`ScreenCanary`), and the runner passed the word on as a loss —
  /// its [ScreenGone.reason] is 0, no system said one.
  pixel,
}

/// The screen's device gone: who said it ([by]), the reason — the HRESULT
/// Windows gave the watch, or the EGL error the engine's call failed by, as
/// an int32 — and the moment the runner saw or heard it. H63 ③ (관제
/// 2026-11-18): the log the app writes is stamped when the app hears it,
/// and the channel and the UI thread lie between the two.
typedef ScreenGone = ({int reason, DateTime seenAt, ScreenGoneBy by});

/// The screen stood again in a context made anew: the loss as it would have
/// been said, and the moment the runner heard it stood.
typedef ScreenStoodAgain = ({ScreenGone lost, DateTime stoodAt});

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
/// where the engine is the one Anicel builds, the engine says so itself and
/// the runner passes its word on ([contextLostMethod]; 🗣️유저 2026-11-22,
/// board a-real-gpu-reset-went-unheard-on-the-main-pc: the engine is
/// mended, and its saying so is the first step). Whoever says it first,
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
/// 🚨★★★WHERE THE ENGINE RESTORES, NONE OF THAT IS SAID AT ALL UNLESS IT
/// FAILS. 🗣️유저 2026-11-22 (board a-real-gpu-reset-went-unheard-on-the-
/// main-pc, relayed): 「Flutter 윈도 엔진을 고쳐 화면이 돌아오게 한다」. The
/// engine Anicel builds (patch 0005) makes its context anew once it hears a
/// loss, and the runner holds the word of the loss for its answer
/// (`flutter_window.cpp`, kScreenContextRestored): Dart hears [went] only
/// where the engine did not stand again, and otherwise [stoodAgain] —
/// whatever the GPU held before it, the images Flutter made and the app's
/// own, is gone, and the screen goes on.
///
/// The method names are spelled again in `flutter_window.cpp`;
/// `a_lost_screen_is_heard_from_the_runner_test` reads both.
abstract final class LostScreen {
  static const channel = MethodChannel('anicel/screen');
  static const wentMethod = 'went';
  static const contextLostMethod = 'contextLost';
  static const contextRestoredMethod = 'contextRestored';
  static const askMethod = 'askWithWindows';
  static const startAgainMethod = 'startAgain';
  static const endMethod = 'end';
  static const standsMethod = 'stands';
  static const pixelNotSaidMethod = 'pixelNotSaid';

  /// The screen's device gone, once it went this run — null till then.
  static ValueListenable<ScreenGone?> get went => _went;
  static final ValueNotifier<ScreenGone?> _went = ValueNotifier(null);

  /// Whether the screen's device went this run.
  static bool get hasGone => _went.value != null;

  /// The last time this run the screen stood again in a context made anew —
  /// null till then. Each time is a new value.
  static ValueListenable<ScreenStoodAgain?> get stoodAgain => _stoodAgain;
  static final ValueNotifier<ScreenStoodAgain?> _stoodAgain = ValueNotifier(
    null,
  );

  /// Hears the runner, for the app's lifetime: `main`, once. A platform
  /// whose runner does not watch never says it. The first word of the
  /// screen going stays, whoever says it: the two say one loss.
  static void listen() {
    channel.setMethodCallHandler((call) async {
      switch ((call.method, call.arguments)) {
        case (
          contextRestoredMethod,
          [
            final int reason,
            final int seenAt,
            final String saidBy,
            final int stoodAt,
          ],
        ):
          if (_goneOf(saidBy, reason, seenAt) case final lost?) {
            _stoodAgain.value = (
              lost: lost,
              stoodAt: DateTime.fromMillisecondsSinceEpoch(stoodAt),
            );
          }
        case (final String method, [final int reason, final int seenAt]):
          _went.value ??= _goneOf(method, reason, seenAt);
      }
      return null;
    });
  }

  /// The screen gone as [method] says it — none for a method of another
  /// word: [reason] as the runner gave it, and [seenAt] in milliseconds
  /// since 1970 UTC.
  ///
  /// ⚠️THE ONE PLACE A WORD IS READ AS A LOSS, for the word said alone and
  /// the word an engine that stood again held. Asked once as a guard and
  /// again for its answer, a word of another method was heard either way
  /// as nothing — or as a throw no test could tell from it.
  static ScreenGone? _goneOf(String method, int reason, int seenAt) {
    final by = switch (method) {
      wentMethod => ScreenGoneBy.watch,
      contextLostMethod => ScreenGoneBy.engine,
      pixelNotSaidMethod => ScreenGoneBy.pixel,
      _ => null,
    };
    if (by == null) {
      return null;
    }
    return (
      reason: reason,
      seenAt: DateTime.fromMillisecondsSinceEpoch(seenAt),
      by: by,
    );
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

  /// Whether the device the runner's watch holds on the screen's adapter
  /// stands, asked of it now and not as the watch last asked — false once
  /// it went, and where the watch holds none; null where no runner
  /// watches.
  static Future<bool?> stands() async {
    try {
      return await channel.invokeMethod<bool>(standsMethod) ?? false;
    } on MissingPluginException {
      return null;
    }
  }

  /// Tells the runner a pixel asked of the screen's own context at
  /// [askedAt] was not said back — a word of a loss it takes through the
  /// door the watch's and the engine's go through, and says back as the
  /// screen gone ([went], by [ScreenGoneBy.pixel]) or stood again
  /// ([stoodAgain]). Nothing where no runner listens.
  ///
  /// 🗣️a-real-gpu-reset-went-unheard-on-the-main-pc-Q1 (유저 2026-11-22),
  /// the option chosen: 「처음엔 기록만 … 실제 사고 한 번이 그 기록으로
  /// 맞다고 확인되면 저장 · 다시 시작 창에 잇는다」 — the one came on
  /// 2026-11-23 20:40 (검증, main PC): the driver logged two errors, the
  /// watch and the app's engine said nothing, and the pixel failed to bind
  /// the screen's context. ⛔Not said to the shell here as a loss: the
  /// runner holds it where its engine restores.
  static Future<void> sayThePixelNotSaid(DateTime askedAt) async {
    try {
      await channel.invokeMethod<void>(pixelNotSaidMethod, [
        askedAt.millisecondsSinceEpoch,
      ]);
    } on MissingPluginException {
      // No runner listens: none watches either, and the pixel is not asked.
    }
  }

  /// Test seam: the screen's device gone, as the runner says it — seen
  /// [seenAt], or now, and said by its watch unless [by] names the engine.
  @visibleForTesting
  static void debugGo([
    int reason = 0x887A0007,
    DateTime? seenAt,
    ScreenGoneBy by = ScreenGoneBy.watch,
  ]) => _went.value ??= (
    reason: reason,
    seenAt: seenAt ?? DateTime.now(),
    by: by,
  );

  /// Test seam: the screen stood again, as the runner says it — of the
  /// loss [lost] it held, at [stoodAt], or now.
  @visibleForTesting
  static void debugStandAgain(ScreenGone lost, [DateTime? stoodAt]) =>
      _stoodAgain.value = (lost: lost, stoodAt: stoodAt ?? DateTime.now());

  /// Test seam: the screen as a launch finds it.
  @visibleForTesting
  static void debugForget() {
    _went.value = null;
    _stoodAgain.value = null;
  }
}
