import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/foundation.dart';

import 'qa_engine_abi.dart';

/// What the platform said about one pen sample — the PEN LEDGER `qa_native`
/// keeps (`qa_pen_ledger_apple.m`, H43): written natively BEFORE Flutter
/// hears of the sample, read here by the sample's own timestamp.
///
/// ⚠️A channel could not carry this. A channel message and a pointer event
/// travel two queues with no order between them, and the brush has to know
/// about THIS sample while it handles THIS sample; a read through FFI of a
/// record written before the event reached Flutter cannot arrive late.
///
/// - iOS: UIKit's word on Apple Pencil force and altitude — whether each is
///   still an ESTIMATE, and the measured value once UIKit sends it
///   (`touchesEstimatedPropertiesUpdated`, which Flutter's engine drops).
///   The Runner's view controller writes it.
/// - macOS: the tablet pressure and tilt Flutter's embedder drops — or that
///   the event is not a tablet's at all. A local event monitor writes it.
enum PenLedgerState {
  /// The platform measured this; the reading's value is it.
  measured,

  /// UIKit's estimate: the measured value is still to come.
  estimated,

  /// UIKit's estimate that no update will correct — FINAL, in Apple's word,
  /// but nothing measured it: the constant a Pencil's first samples carry
  /// (H43, build 1065, where this read as [measured]).
  estimatedFinal,

  /// The sample carries no pressure at all — a mouse, on macOS.
  noPressure,
}

typedef PenLedgerReading = ({PenLedgerState state, double value});

/// AppKit's scaled tilt of one sample — `NSEvent.tilt`, −1..1 each way.
typedef PenLedgerTilt = ({double x, double y});

typedef _LedgerReaders = ({
  double Function(int) force,
  double Function(int) altitude,
  int Function(int, Pointer<Double>) tilt,
});

abstract final class QaPenLedger {
  /// The ledger's readers, or null where there is none: another platform,
  /// or a build whose native side predates it.
  static final _LedgerReaders? _read = _open();

  static _LedgerReaders? _open() {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return null;
    }
    // Through the ONE door every engine loader uses: on Apple it is the
    // process the plugin compiled the engine into, behind the ABI gate.
    final engine = openQaEngineLibrary();
    if (engine == null) {
      return null;
    }
    try {
      double Function(int) reader(String name) => engine
          .lookupFunction<Double Function(Int64), double Function(int)>(name);
      final read = (
        force: reader('qa_pen_ledger_value'),
        altitude: reader('qa_pen_ledger_altitude'),
        tilt: engine
            .lookupFunction<
              Int32 Function(Int64, Pointer<Double>),
              int Function(int, Pointer<Double>)
            >('qa_pen_ledger_tilt'),
      );
      engine.lookupFunction<Void Function(), void Function()>(
        'qa_pen_ledger_start',
      )();
      return read;
    } on Object {
      return null;
    }
  }

  /// Where the native side writes a tilt's two numbers — one, for the life
  /// of the process: the brush asks on the UI isolate, one sample at a
  /// time.
  static final Pointer<Double> _tiltXy = malloc<Double>(2);

  /// Replace the native ledger in tests — the test binding runs on no
  /// platform that keeps one.
  @visibleForTesting
  static PenLedgerReading? Function(Duration at)? debugForce;

  @visibleForTesting
  static PenLedgerReading? Function(Duration at)? debugAltitude;

  @visibleForTesting
  static PenLedgerTilt? Function(Duration at)? debugTilt;

  /// Starts keeping the ledger now rather than at the first sample, so the
  /// very first stroke is on it too (macOS installs its event monitor
  /// here), and answers whether it is kept at all. Safe to call again.
  static bool start() =>
      debugForce != null ||
      debugAltitude != null ||
      debugTilt != null ||
      _read != null;

  /// What the ledger holds for the FORCE of the sample Flutter stamped [at]
  /// — UIKit force on iOS, NSEvent pressure (0..1) on macOS — or null when
  /// it holds nothing for it.
  static PenLedgerReading? forceAt(Duration at) {
    final override = debugForce;
    if (override != null) {
      return override(at);
    }
    return decode(_read?.force(at.inMicroseconds));
  }

  /// What the ledger holds for the ALTITUDE of the sample Flutter stamped
  /// [at], in radians from the surface (UIKit's `altitudeAngle`) — or null
  /// when it holds nothing, which is always on macOS.
  static PenLedgerReading? altitudeAt(Duration at) {
    final override = debugAltitude;
    if (override != null) {
      return override(at);
    }
    return decode(_read?.altitude(at.inMicroseconds));
  }

  /// AppKit's tilt of the sample Flutter stamped [at] — or null when the
  /// ledger holds none for it: no record, a mouse, or iOS, where the lean
  /// rides the pointer itself (desktop-pen-tilt).
  static PenLedgerTilt? tiltAt(Duration at) {
    final override = debugTilt;
    if (override != null) {
      return override(at);
    }
    final read = _read;
    if (read == null || read.tilt(at.inMicroseconds, _tiltXy) == 0) {
      return null;
    }
    return (x: _tiltXy[0], y: _tiltXy[1]);
  }

  /// The native answer (`qa_pen_ledger_value` / `qa_pen_ledger_altitude`)
  /// as a reading: the codes below, or the value itself.
  @visibleForTesting
  static PenLedgerReading? decode(double? value) {
    if (value == null || value == _none) {
      return null;
    }
    if (value == _estimated) {
      return (state: PenLedgerState.estimated, value: 0.0);
    }
    if (value == _estimatedFinal) {
      return (state: PenLedgerState.estimatedFinal, value: 0.0);
    }
    if (value == _noPressure) {
      return (state: PenLedgerState.noPressure, value: 0.0);
    }
    return (state: PenLedgerState.measured, value: value);
  }

  // The native answers' codes: every real value is a force, a pressure or an
  // angle above the surface, never below zero.
  static const double _none = -1;
  static const double _estimated = -2;
  static const double _noPressure = -3;
  static const double _estimatedFinal = -4;
}
