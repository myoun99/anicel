import 'dart:developer' show Timeline;
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// Where a window's pictures land: a real vblank of its screen on the frame
/// clock, that screen's refresh period, and how often the compositor
/// composes — the same period but on a screen slower than its clock.
typedef VblankGrid = ({
  int vblankMicros,
  double periodMicros,
  double composedEveryMicros,
});

/// A vblank and a refresh period, as the compositor or one screen says them.
typedef RefreshLine = ({int vblankMicros, double periodMicros});

/// Within this much of the compositor's period a screen is on its clock:
/// the two are read apart, and differ in their last digits.
const double _onItsClock = 1.01;

/// 🚨THE GRID OF A WINDOW ON [screens] — THE FASTEST OF THEM (유저
/// 2026-11-02: 「주사율 다른 모니터 둘에 걸쳐있으면 높은쪽을 기반으로
/// 하도록」) — under a compositor on [composed]: its own clock where that
/// is the fastest it lies on, or nobody said which screens it lies on.
///
/// ⛔Faster than the compositor's clock is the compositor's clock: nothing
/// was measured there (card playback-pacing-knows-one-display-only).
VblankGrid gridOfTheWindow({
  required RefreshLine composed,
  required Iterable<RefreshLine> screens,
}) {
  final composedEvery = composed.periodMicros;
  RefreshLine? fastest;
  for (final screen in screens) {
    if (fastest == null || screen.periodMicros < fastest.periodMicros) {
      fastest = screen;
    }
  }
  final line = fastest == null || fastest.periodMicros <= composedEvery * _onItsClock
      ? composed
      : fastest;
  return (
    vblankMicros: line.vblankMicros,
    periodMicros: line.periodMicros,
    composedEveryMicros: composedEvery,
  );
}

/// The real vblank, and a wait that ends on a given microsecond — what a
/// clock's frame needs to land on the vblank it claimed (`PresentClaims`).
///
/// Both are on the FRAME CLOCK: the microseconds the engine's frame times
/// are on — Dart's timeline clock, which the engine takes them from.
abstract interface class DisplayTiming {
  /// Now, on the frame clock.
  int get nowMicros;

  /// Where the window's pictures land; null when the display does not say.
  VblankGrid? vblankGrid();

  /// Blocks the calling thread until [micros] on the frame clock.
  void waitUntil(int micros);

  /// Keeps the compositor composing on every vblank, or lets it rest again
  /// ([on] false) — whether it is kept composing now. A picture handed over
  /// between two vblanks is then taken at the second of them, however idle
  /// the rest of the desktop leaves the compositor.
  bool composeEveryVblank({required bool on});
}

/// The engine's own answers (`qa_display_vblank`,
/// `qa_display_window_screens`, `qa_display_wait_until_us`,
/// `qa_display_compose_every_vblank`): Windows' compositor timing (DWM), its
/// statistics of the screens under the app's window, a high-resolution
/// waitable timer, and a visual with nothing in it swaying on the app's
/// window for as long as the compositor is to compose on every vblank.
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
  QaDisplayTiming._(
    this._vblank,
    this._windowScreens,
    this._waitUntil,
    this._compose,
  );

  /// The most screens a window is read to lie on.
  static const int _maxScreens = 8;

  final int Function(Pointer<Int64>) _vblank;
  final int Function(Pointer<Int64>, int) _windowScreens;
  final void Function(int) _waitUntil;
  final int Function(int) _compose;
  final Pointer<Int64> _out = calloc<Int64>(2);
  final Pointer<Int64> _screens = calloc<Int64>(2 * _maxScreens);

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
      library.lookupFunction<
        Int32 Function(Pointer<Int64>, Int32),
        int Function(Pointer<Int64>, int)
      >('qa_display_window_screens'),
      library.lookupFunction<Void Function(Int64), void Function(int)>(
        'qa_display_wait_until_us',
      ),
      library.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'qa_display_compose_every_vblank',
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
  VblankGrid? vblankGrid() {
    if (_vblank(_out) == 0) {
      return null;
    }
    final count = _windowScreens(_screens, _maxScreens);
    return gridOfTheWindow(
      composed: (vblankMicros: _out[0], periodMicros: _out[1] / 1000),
      screens: [
        for (var i = 0; i < count; i += 1)
          (
            vblankMicros: _screens[2 * i],
            periodMicros: _screens[2 * i + 1] / 1000,
          ),
      ],
    );
  }

  @override
  void waitUntil(int micros) => _waitUntil(micros);

  @override
  bool composeEveryVblank({required bool on}) => _compose(on ? 1 : 0) != 0;
}
