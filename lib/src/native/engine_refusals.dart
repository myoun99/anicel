import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuRefused;

import 'app_gpu_engine.dart' show appGpuEngineIsGone;

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

  /// Watches both doors, for the app's lifetime: `main`, once — each still
  /// hears what it heard.
  static void install() {
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
    if (error is! GpuRefused) {
      return;
    }
    final cause = appGpuEngineIsGone ? _deviceGone : error.runtimeType;
    if (_causes.add(cause)) {
      scheduleMicrotask(_told.tell);
    }
  }

  /// Test seam: no cause told, as a launch finds it.
  @visibleForTesting
  static void debugForget() => _causes.clear();
}

final class _Told extends ChangeNotifier {
  void tell() => notifyListeners();
}
