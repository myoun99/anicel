import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
/// - macOS: the tablet pressure Flutter's embedder drops — or that the
///   event is not a tablet's at all. A local event monitor writes it.
enum PenLedgerState {
  /// The platform measured this; the reading's value is it.
  measured,

  /// UIKit's estimate: the measured value is still to come.
  estimated,

  /// The sample carries no pressure at all — a mouse, on macOS.
  noPressure,
}

typedef PenLedgerReading = ({PenLedgerState state, double value});

abstract final class QaPenLedger {
  /// The ledger's readers, or null where there is none: another platform,
  /// or a build whose native side predates it.
  static final ({double Function(int) force, double Function(int) altitude})?
  _read = _open();

  static ({double Function(int) force, double Function(int) altitude})?
  _open() {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return null;
    }
    try {
      final process = DynamicLibrary.process();
      double Function(int) reader(String name) => process
          .lookupFunction<Double Function(Int64), double Function(int)>(name);
      final read = (
        force: reader('qa_pen_ledger_value'),
        altitude: reader('qa_pen_ledger_altitude'),
      );
      process.lookupFunction<Void Function(), void Function()>(
        'qa_pen_ledger_start',
      )();
      return read;
    } on Object {
      return null;
    }
  }

  /// Replace the native ledger in tests — the test binding runs on no
  /// platform that keeps one.
  @visibleForTesting
  static PenLedgerReading? Function(Duration at)? debugForce;

  @visibleForTesting
  static PenLedgerReading? Function(Duration at)? debugAltitude;

  /// Starts keeping the ledger now rather than at the first sample, so the
  /// very first stroke is on it too (macOS installs its event monitor
  /// here), and answers whether it is kept at all. Safe to call again.
  static bool start() =>
      debugForce != null || debugAltitude != null || _read != null;

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
}
