import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

/// The raster thread not back from the frames handed it: the newest frame
/// it said it drew, the newest handed over and when, and since when
/// nothing was said.
typedef RasterStood = ({
  int drawn,
  int handedOver,
  DateTime handedOverAt,
  DateTime quietSince,
});

/// 🚨A FRAME THE APP HANDS THE ENGINE IS SAID DRAWN WITHIN SECONDS — WHERE
/// NONE IS FOR [patience], THE THREAD THAT DRAWS THE SCREEN STANDS, AND THE
/// APP WRITES WHAT IT WAS DOING. Evidence only: nothing is asked and
/// nothing stopped (`LostScreenEvidence.noteTheRasterStoodOnce`).
///
/// Board a-real-gpu-reset-went-unheard-on-the-main-pc (2026-11-22 16:47,
/// NVIDIA): the driver logged an error of the GPU (nvlddmkm 153), the
/// window stood on its last picture, the app went on answering — and
/// nothing was written: the runner's watch hears a reset of the whole
/// adapter, on a device of its own (`windows/runner/lost_screen.h`), and
/// the canvas engine was sending nothing. Which device stopped is what the
/// next one is to say.
///
/// What this hears, read from the engine (Flutter 3.47.4, `shell/common`):
/// - every frame the raster thread comes back from is said, one it could
///   not put up as well (`rasterizer.cc`, `DoDraw`: `OnFrameRasterized`
///   follows a draw whatever became of it), a second after at most
///   (`shell.cc`, `OnFrameRasterized` — said in batches);
/// - so none said for [patience] after one was handed over is that thread
///   not back from it: in the driver, as far as the app can tell.
///
/// ⛔NOT A SCREEN WHOSE FRAMES FAIL QUIETLY: where the screen's device
/// alone went, each frame fails to be put up and is said drawn as any is.
/// That is asked with a pixel (`ScreenCanary`, Q1 of that card).
///
/// ⛔NOT THE MACHINE STANDING STILL: a timer that comes far later than it
/// was set for — a sleep, a debugger — waited on no raster thread, and
/// waits again.
abstract final class RasterWatch {
  /// How long after a frame was handed over none is said drawn before the
  /// raster thread is said to stand.
  // ⏳My number, not measured: far past a frame's raster and the second its
  // report waits in a batch, and short enough that what the app was doing
  // is still what it is doing.
  static const Duration patience = Duration(seconds: 10);

  /// The raster thread standing, once it stood this run — null till then.
  static ValueListenable<RasterStood?> get stood => _stood;
  static final ValueNotifier<RasterStood?> _stood = ValueNotifier(null);

  static bool _installed = false;

  /// Watches every frame, for the app's lifetime: `main`, once — a
  /// persistent frame callback cannot be removed.
  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    SchedulerBinding.instance
      ..addPersistentFrameCallback(_built)
      ..addTimingsCallback(_drawn);
  }

  /// The newest frame handed over, and when; the newest said drawn.
  static int _handedOver = -1;
  static DateTime _handedOverAt = DateTime(0);
  static int _saidDrawn = -1;

  /// When the newest frame was handed over — the year 0 while none was.
  static DateTime get handedOverAt => _handedOverAt;

  /// Since when a frame handed over waits with nothing said, and what
  /// waits [patience] from then — none while every frame handed over was
  /// said drawn.
  static DateTime _quietSince = DateTime(0);
  static Timer? _waiting;

  /// Test seam: the clock a late timer is told from a standing machine by.
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _now() => (debugClockOverride ?? DateTime.now)();

  /// After the binding's own callback, which hands the frame's scene
  /// over.
  static void _built(Duration _) => handedOver(
    SchedulerBinding.instance.platformDispatcher.frameData.frameNumber,
  );

  static void _drawn(List<FrameTiming> timings) {
    var newest = _saidDrawn;
    for (final timing in timings) {
      if (timing.frameNumber > newest) {
        newest = timing.frameNumber;
      }
    }
    saidDrawn(newest);
  }

  /// The frame numbered [frame] was handed to the engine.
  @visibleForTesting
  static void handedOver(int frame) {
    _handedOver = frame;
    _handedOverAt = _now();
    if (_waiting == null && _stood.value == null) {
      _waitFromNow();
    }
  }

  /// The engine said every frame up to [frame] drawn: the raster thread is
  /// back from them, and whatever was handed over after waits from now.
  @visibleForTesting
  static void saidDrawn(int frame) {
    _saidDrawn = frame;
    _waiting?.cancel();
    _waiting = null;
    if (_handedOver > frame && _stood.value == null) {
      _waitFromNow();
    }
  }

  static void _waitFromNow() {
    _quietSince = _now();
    _waiting = Timer(patience, _late);
  }

  static void _late() {
    _waiting = null;
    if (_now().difference(_quietSince) > patience * 2) {
      _waitFromNow();
      return;
    }
    _stood.value = (
      drawn: _saidDrawn,
      handedOver: _handedOver,
      handedOverAt: _handedOverAt,
      quietSince: _quietSince,
    );
  }

  /// Test seam: a run in which no frame was handed over.
  @visibleForTesting
  static void debugForget() {
    _waiting?.cancel();
    _waiting = null;
    _handedOver = -1;
    _handedOverAt = DateTime(0);
    _saidDrawn = -1;
    _stood.value = null;
  }
}
