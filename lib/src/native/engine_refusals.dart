import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuDeviceWent, GpuRefused;

import 'app_gpu_engine.dart'
    show appGpuEngineIsGone, appGpuEngineOpen, appGpuEngineWentBy;
import 'app_kernels_ahead.dart' show openTheAppsEngineAgain;

/// 🚨A JOB THE GRAPHICS DEVICE REFUSED IS TOLD — ONCE A CAUSE, A RUN.
///
/// 🗣️gpu-canonical-store-Q14 (유저 2026-11-11): 「공통 알림 창으로 한 번
/// 알린다」 — 「실패가 처음 났을 때 공통 알림 창(닫기 버튼)을 한 번 띄운다 …
/// 같은 실행에서 같은 까닭으로는 다시 띄우지 않는다. 획이 사라진 경우와
/// 캔버스가 멈춘 경우 둘 다 같은 창이다」. ↩️Till then a refusal reached the
/// console alone: a stroke was gone, or the canvas stood on the picture it
/// showed, and nothing said whether the app had stopped.
///
/// ONE home. A refusal is thrown as what it is ([GpuRefused]) and ends
/// where every error of the app's ends — reported to Flutter by what caught
/// it (a paint, a pen's lift, a frame's making) or uncaught, on its way out
/// of a future — and both doors are watched here ([install]). ⛔Nothing
/// that catches one says so itself: a catch that told would be a second
/// place to forget.
///
/// A cause is the refusal's own type, named by what threw it — the engine's
/// answer, room for tiles (`TileRoomRefused`), a read back
/// (`GpuReadFailed`). A refusal comes again at every stroke and frame once
/// it starts, and its cause is told once.
///
/// 🚨A DEVICE THAT IS GONE IS ONE CAUSE, whatever is refused for it
/// ([appGpuEngineIsGone]): the driver took it away, and every job of every
/// type is refused from then on — a read back, a landing, a frame. ↩️By
/// type alone that one cause was told once a type.
///
/// 🚨AND THE APP OPENS ANOTHER ENGINE FOR IT, IN PLACE OF TELLING A
/// REFUSAL. 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은
/// 꺼지지 않고 새 장치를 열어 사본으로 되살린다」. The first refusal heard of
/// a device that is gone is where the app learns that it went (관제
/// 2026-11-11 22:3x: 「방아쇠는 거절을 듣는 한 곳이 「장치가 갔다」를 처음 들을
/// 때」): after the turn it is heard in, the app lets that engine go and
/// opens another behind the launch's wait window
/// ([openTheAppsEngineAgain]), and once it stands on it says that the
/// device started again, and why as far as anything says
/// ([openedAnother], [wentBy]) — 🗣️유저 2026-11-11
/// (a-lost-gpu-device-keeps-the-unsaved-tiles-Q1): 「그래픽 장치가 다시
/// 시작되었다고 알린다」 · 「그래픽장치가 왜 다시시작되었는지는 알수있게」.
/// What is refused while it does is that one loss, and said by no window.
/// Each device that goes is one such opening (관제 2026-11-13 10:11: 「두
/// 번째 손실은 새 사건이다」).
///
/// ⚖️BUT NOT WITHIN [openAnotherApart] OF THE LAST OPENING. A device that
/// goes again that soon is told as a refusal is — Q14's sentence, 「저장한 뒤
/// 앱을 다시 시작해 주세요」 — and the app stays on the engine that is gone,
/// which it can still be saved from. What took a device may take the next
/// the same way, with no hand in it — a job of this app's that hangs it,
/// run again by the frame the canvas stands on — and each turn of that is
/// a wait window over every input; and Windows counts a device's hangs: by
/// default it stops the whole machine at the sixth where five came, each
/// recovered from, within one minute (Microsoft Learn, "Timeout detection
/// and recovery", `TdrLimitCount` · `TdrLimitTime`; read 2026-11-13).
/// 🗣️a-lost-gpu-device-keeps-the-unsaved-tiles-Q2 (유저 2026-11-13): 「1분
/// 안에 또 꺼지면 되살리지 않는다」 — the bound and its minute, built
/// before they were asked of, as the user chose them.
///
/// And where no engine stands in the place of the one let go — none would
/// open, or its device went as it was made ready — that is told as a
/// refusal is, the same cause.
abstract final class EngineRefusals {
  /// Tells a cause the first time it is heard this run: the shell shows
  /// its window at each telling (`HomePage`).
  ///
  /// 🚨TOLD AFTER THE TURN IT IS HEARD IN: an error ends wherever it is
  /// thrown, in a paint too, and no window can be asked for there.
  static Listenable get told => _told;
  static final _Told _told = _Told();
  static final Set<Object> _causes = {};

  /// The cause of every refusal once the app's device is gone.
  static const Object _deviceGone = #deviceGone;

  /// Tells that the app stands on another engine, opened in place of one
  /// whose device went ([wentBy] says why): the shell says so at each
  /// telling (`HomePage`).
  static Listenable get openedAnother => _openedAnother;
  static final _Told _openedAnother = _Told();

  /// Why the device of the engine last let go went, as far as anything
  /// says ([GpuDeviceWent]).
  static GpuDeviceWent get wentBy => _wentBy;
  static GpuDeviceWent _wentBy = GpuDeviceWent.unsaid;

  /// How long after it opened another engine the app opens none more.
  static const Duration openAnotherApart = Duration(minutes: 1);

  /// Test seam: the clock [openAnotherApart] is read by.
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _now() => (debugClockOverride ?? DateTime.now)();

  /// How the app opens another engine in place of one that is gone.
  static Future<void> Function() _openAnother = openTheAppsEngineAgain;

  /// Whether another is being opened now, and when the last one was.
  static bool _opensAnother = false;
  static DateTime? _openedAnotherAt;

  /// Watches both doors, for the app's lifetime: `main`, once — each still
  /// hears what it heard. [openAnother] is how the app opens another
  /// engine: the launch's own path, but for a test that stands in for it.
  static void install({
    Future<void> Function() openAnother = openTheAppsEngineAgain,
  }) {
    _openAnother = openAnother;
    final reported = FlutterError.onError;
    FlutterError.onError = (details) {
      _hear(details.exception);
      reported?.call(details);
    };
    final uncaught = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _hear(error);
      return uncaught?.call(error, stack) ?? false;
    };
  }

  static void _hear(Object error) {
    if (error is! GpuRefused || _opensAnother) {
      return;
    }
    if (!appGpuEngineIsGone) {
      _tellOnce(error.runtimeType);
    } else if (_mayOpenAnother) {
      _opensAnother = true;
      scheduleMicrotask(_letGoAndOpenAnother);
    } else {
      _tellOnce(_deviceGone);
    }
  }

  static void _tellOnce(Object cause) {
    if (_causes.add(cause)) {
      scheduleMicrotask(_told.tell);
    }
  }

  static bool get _mayOpenAnother {
    final last = _openedAnotherAt;
    return last == null || _now().difference(last) >= openAnotherApart;
  }

  /// ⚠️After the turn the refusal was heard in — a paint's, where no box
  /// may be marked and no window asked for ([openTheAppsEngineAgain] does
  /// both).
  static Future<void> _letGoAndOpenAnother() async {
    // Asked of the engine that is gone, before it is the app's no more.
    final by = appGpuEngineWentBy;
    _openedAnotherAt = _now();
    try {
      await _openAnother();
    } finally {
      _opensAnother = false;
    }
    // Asked of the app's engine, not of what opened it: none is open
    // where one would not open, and one may be gone as it was made ready.
    if (appGpuEngineOpen.value == null || appGpuEngineIsGone) {
      _tellOnce(_deviceGone);
      return;
    }
    // The device that went is the app's no more: one that goes after it
    // is another, and a cause of its own.
    _causes.remove(_deviceGone);
    _wentBy = by;
    _openedAnother.tell();
  }

  /// Test seam: no cause told and no engine opened, as a launch finds it.
  @visibleForTesting
  static void debugForget() {
    _causes.clear();
    _opensAnother = false;
    _openedAnotherAt = null;
    _wentBy = GpuDeviceWent.unsaid;
    _openAnother = openTheAppsEngineAgain;
  }
}

final class _Told extends ChangeNotifier {
  void tell() => notifyListeners();
}
