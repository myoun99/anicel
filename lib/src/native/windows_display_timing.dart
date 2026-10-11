import 'dart:developer' show Timeline;
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// The real vblank, and a wait that ends on a given microsecond — what a
/// frame of a run needs to land on its vblank (`presentSlotMicros`).
///
/// Both are on the FRAME CLOCK: the microseconds the engine's frame times
/// are on — Dart's timeline clock, which the engine takes them from.
abstract interface class DisplayTiming {
  /// Now, on the frame clock.
  int get nowMicros;

  /// A real vblank and the refresh period, on the frame clock; null when
  /// the compositor does not say.
  ({int vblankMicros, double periodMicros})? vblankGrid();

  /// Blocks the calling thread until [micros] on the frame clock.
  void waitUntil(int micros);
}

/// Windows' own answers, straight from the system DLLs: the compositor's
/// timing (`DwmGetCompositionTimingInfo`) and a high-resolution waitable
/// timer.
///
/// 🚨THE TWO CLOCKS ARE ONE ONLY BECAUSE BOTH ARE THE PERFORMANCE COUNTER —
/// Dart's monotonic microseconds are, on Windows, and the compositor stamps
/// its vblank with it. [instance] reads the two side by side and stands
/// down when they disagree: a vblank on another clock would put every
/// hand-off in the wrong place, which is worse than none.
final class WindowsDisplayTiming implements DisplayTiming {
  WindowsDisplayTiming._(
    this._timingInfo,
    this._counter,
    this._frequency,
    this._timer,
    this._setTimer,
    this._waitFor,
  );

  /// `DWM_TIMING_INFO` is packed: 292 bytes, `qpcRefreshPeriod` at 12 and
  /// `qpcVBlank` at 28 (both 64-bit, read as two halves — the offsets are
  /// not 8-aligned).
  static const int _infoBytes = 292;
  static const int _refreshPeriodAt = 12;
  static const int _vblankAt = 28;

  final int Function(int, Pointer<Uint8>) _timingInfo;
  final int Function(Pointer<Int64>) _counter;
  final int _frequency;
  final int _timer;
  final int Function(int, Pointer<Int64>, int, Pointer<Void>, Pointer<Void>,
      int) _setTimer;
  final int Function(int, int) _waitFor;

  final Pointer<Uint8> _info = calloc<Uint8>(_infoBytes);
  final Pointer<Int64> _due = calloc<Int64>();

  static WindowsDisplayTiming? _instance;
  static bool _tried = false;

  /// The timing, or null off Windows, when a DLL refuses, or when the
  /// compositor's clock is not the frame clock.
  static WindowsDisplayTiming? get instance {
    if (!_tried) {
      _tried = true;
      _instance = Platform.isWindows ? _open() : null;
    }
    return _instance;
  }

  static WindowsDisplayTiming? _open() {
    try {
      final dwm = DynamicLibrary.open('dwmapi.dll');
      final kernel = DynamicLibrary.open('kernel32.dll');
      final frequency = calloc<Int64>();
      final int hz;
      try {
        kernel.lookupFunction<Int32 Function(Pointer<Int64>),
            int Function(Pointer<Int64>)>('QueryPerformanceFrequency')(
          frequency,
        );
        hz = frequency.value;
      } finally {
        calloc.free(frequency);
      }
      if (hz <= 0) {
        return null;
      }
      final create = kernel.lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Utf16>, Uint32, Uint32),
          int Function(Pointer<Void>, Pointer<Utf16>, int, int)>(
        'CreateWaitableTimerExW',
      );
      // CREATE_WAITABLE_TIMER_HIGH_RESOLUTION (Windows 10 1803 on); the
      // plain timer where it is refused — it only wakes coarser, and the
      // spin in [waitUntil] takes up the rest.
      const highResolution = 0x00000002;
      const allAccess = 0x1F0003;
      var timer = create(nullptr, nullptr, highResolution, allAccess);
      if (timer == 0) {
        timer = create(nullptr, nullptr, 0, allAccess);
      }
      if (timer == 0) {
        return null;
      }
      final timing = WindowsDisplayTiming._(
        dwm.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>),
            int Function(int, Pointer<Uint8>)>('DwmGetCompositionTimingInfo'),
        kernel.lookupFunction<Int32 Function(Pointer<Int64>),
            int Function(Pointer<Int64>)>('QueryPerformanceCounter'),
        hz,
        timer,
        kernel.lookupFunction<
            Int32 Function(IntPtr, Pointer<Int64>, Int32, Pointer<Void>,
                Pointer<Void>, Int32),
            int Function(int, Pointer<Int64>, int, Pointer<Void>,
                Pointer<Void>, int)>('SetWaitableTimer'),
        kernel.lookupFunction<Uint32 Function(IntPtr, Uint32),
            int Function(int, int)>('WaitForSingleObject'),
      );
      return timing._counterIsTheFrameClock() ? timing : null;
    } on Object {
      return null;
    }
  }

  bool _counterIsTheFrameClock() {
    final before = Timeline.now;
    final counter = _counterMicros();
    final after = Timeline.now;
    return counter >= before - 1000 && counter <= after + 1000;
  }

  int _micros(int ticks) =>
      (ticks ~/ _frequency) * Duration.microsecondsPerSecond +
      (ticks % _frequency) * Duration.microsecondsPerSecond ~/ _frequency;

  int _counterMicros() {
    _counter(_due);
    return _micros(_due.value);
  }

  int _u64(int at) =>
      (_info + at).cast<Uint32>().value |
      ((_info + at + 4).cast<Uint32>().value << 32);

  @override
  int get nowMicros => Timeline.now;

  @override
  ({int vblankMicros, double periodMicros})? vblankGrid() {
    _info.cast<Uint32>().value = _infoBytes;
    if (_timingInfo(0, _info) != 0) {
      return null;
    }
    final periodTicks = _u64(_refreshPeriodAt);
    final vblankTicks = _u64(_vblankAt);
    if (periodTicks <= 0 || vblankTicks <= 0) {
      return null;
    }
    return (
      vblankMicros: _micros(vblankTicks),
      periodMicros: periodTicks * Duration.microsecondsPerSecond / _frequency,
    );
  }

  /// The timer sleeps to within half a millisecond of [micros] (its
  /// resolution); a spin on the frame clock takes the rest.
  @override
  void waitUntil(int micros) {
    const spinMicros = 500;
    final sleep = micros - spinMicros - Timeline.now;
    if (sleep > 0) {
      // Relative due times are negative, in 100ns units. The wait gives up
      // a little after the timer was due, whatever it does.
      _due.value = -sleep * 10;
      if (_setTimer(_timer, _due, 0, nullptr, nullptr, 0) != 0) {
        _waitFor(_timer, sleep ~/ 1000 + 2);
      }
    }
    while (Timeline.now < micros) {}
  }
}
