import 'dart:developer' show Timeline;
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// The real vblank, and a wait that ends on a given microsecond — what a
/// clock's frame needs to land on the vblank it claimed (`PresentClaims`).
///
/// Both are on the FRAME CLOCK: the microseconds the engine's frame times
/// are on — Dart's timeline clock, which the engine takes them from.
abstract interface class DisplayTiming {
  /// Now, on the frame clock.
  int get nowMicros;

  /// A real vblank and the refresh period, on the frame clock; null when
  /// the display does not say.
  ({int vblankMicros, double periodMicros})? vblankGrid();

  /// Blocks the calling thread until [micros] on the frame clock.
  void waitUntil(int micros);
}

/// The engine's own answers (`qa_display_vblank`,
/// `qa_display_wait_until_us`): Windows' compositor timing (DWM) and a
/// high-resolution waitable timer.
///
/// 🚨THE TWO CLOCKS ARE ONE ONLY BECAUSE BOTH ARE THE PERFORMANCE COUNTER —
/// Dart's monotonic microseconds are, on Windows, and the compositor stamps
/// its vblanks with it. [instance] reads the two side by side and stands
/// down when they disagree: a vblank on another clock would put every
/// hand-off in the wrong place, which is worse than none.
///
/// Null where the engine has no display to ask — every platform but
/// Windows, whose engine vsync IS the display's — or where no engine loads.
final class QaDisplayTiming implements DisplayTiming {
  QaDisplayTiming._(this._vblank, this._waitUntil);

  final int Function(Pointer<Int64>) _vblank;
  final void Function(int) _waitUntil;
  final Pointer<Int64> _out = calloc<Int64>(2);

  static QaDisplayTiming? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  static QaDisplayTiming? get instance {
    if (!_tried) {
      _tried = true;
      _instance = _open();
    }
    return _instance;
  }

  static QaDisplayTiming? _open() {
    final library = openQaEngineLibrary();
    if (library == null) {
      return null;
    }
    final timing = QaDisplayTiming._(
      library.lookupFunction<
        Int32 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('qa_display_vblank'),
      library.lookupFunction<Void Function(Int64), void Function(int)>(
        'qa_display_wait_until_us',
      ),
    );
    final grid = timing.vblankGrid();
    if (grid == null) {
      return null;
    }
    // A vblank is within a few refreshes of now on the frame clock — the
    // compositor names the next one or two — when the clocks are one.
    final apart = (grid.vblankMicros - Timeline.now).abs();
    return apart < Duration.microsecondsPerSecond ? timing : null;
  }

  @override
  int get nowMicros => Timeline.now;

  @override
  ({int vblankMicros, double periodMicros})? vblankGrid() {
    if (_vblank(_out) == 0) {
      return null;
    }
    return (vblankMicros: _out[0], periodMicros: _out[1] / 1000);
  }

  @override
  void waitUntil(int micros) => _waitUntil(micros);
}
