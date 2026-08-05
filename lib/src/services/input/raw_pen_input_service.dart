import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton, kSecondaryStylusButton;

import '../../native/qa_tablet_bridge.dart';

/// The Raw Input pen observer (pen program) — Windows only.
///
/// Reads the pen's button truth out of the HID digitizer report itself,
/// underneath Windows Ink and underneath Wintab, because both layers above
/// it lose information we need:
///
/// - Ink rewrites a barrel press into a phantom pen tap before Flutter
///   sees it (kind stylus, pressure 0, PRIMARY button), so the press is
///   indistinguishable from a drawing contact by the time it arrives.
/// - Ink drops the tail end entirely: Flutter's Windows embedder does map
///   PEN_FLAG_INVERTED to invertedStylus, but nothing calls
///   EnableMouseInPointer, so WM_POINTER never arrives and that code is
///   dead. The pen reports as a plain stylus whichever end is down.
/// - Wintab has no portable eraser test at all (CSR_TYPE is
///   manufacturer-defined, and the industry falls back to a cursor-index
///   convention).
///
/// HID states all of it outright on usage page 0x0D — Tip Switch, Barrel
/// Switch, Eraser, Invert — so this service reports DECLARED bits and
/// never infers a button from pressure or from a cursor index.
///
/// Unlike the Wintab sidecar this is NOT user-switchable: it observes a
/// message-only window on its own thread and cannot alter how input
/// reaches the app, so there is no trade-off to expose. Absence of the
/// DLL, of hid.dll, or of a digitizer = permanently idle, silent.
class RawPenInputService {
  RawPenInputService._();

  static final RawPenInputService instance = RawPenInputService._();

  /// Poll cadence — matches the Wintab sidecar; the native side keeps a
  /// snapshot, so a poll is two atomic reads.
  static const Duration pollInterval = Duration(milliseconds: 8);

  /// A report older than this stops speaking for the pen (it left
  /// proximity, or the stream hiccuped).
  static const Duration freshWindow = Duration(milliseconds: 150);

  /// The newest decoded report — the input inspector renders this.
  final ValueNotifier<QaPenRawState?> latest = ValueNotifier<QaPenRawState?>(
    null,
  );

  /// Test hook: replaces the native poll.
  QaPenRawState? Function()? debugPollOverride;

  /// Test hook: the clock the freshness window reads (see the Wintab
  /// service for why a frozen clock matters in widget tests).
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _now() => debugClockOverride?.call() ?? DateTime.now();

  QaTabletBridge? _bridge;
  Timer? _timer;
  bool _observing = false;
  int _lastSequence = -1;
  DateTime _lastReportAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _timer != null;

  /// One-time wiring from the sidecar facade. Windows-only and
  /// unconditional: this path only ever ADDS information the layers above
  /// it dropped, so there is nothing for a user to choose.
  void bind() {
    if (!Platform.isWindows) {
      return;
    }
    start();
  }

  void start() {
    if (_timer != null) {
      return;
    }
    if (debugPollOverride == null) {
      _bridge ??= QaTabletBridge.instanceOrNull;
      final bridge = _bridge;
      if (bridge == null || !bridge.rawInputSupported) {
        return; // Older DLL or non-Windows — stay idle.
      }
      _observing = bridge.startRawInput();
      if (!_observing) {
        return; // No digitizer answered the registration.
      }
    }
    _timer = Timer.periodic(pollInterval, (_) => _pump());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      _bridge?.stopRawInput();
      _observing = false;
    }
    latest.value = null;
    _lastSequence = -1;
  }

  void _pump() {
    final state = debugPollOverride != null
        ? debugPollOverride!()
        : _bridge?.pollRawInput();
    if (state == null) {
      return;
    }
    // Freshness follows the REPORT counter, not the poll: a pen resting
    // in proximity repeats its last flags forever, and that is not news.
    if (state.sequence != _lastSequence) {
      _lastSequence = state.sequence;
      _lastReportAt = _now();
    }
    latest.value = state;
  }

  QaPenRawState? _freshState(DateTime? now) {
    if (_timer == null) {
      return null;
    }
    final state = latest.value;
    if (state == null) {
      return null;
    }
    if ((now ?? _now()).difference(_lastReportAt) > freshWindow) {
      return null;
    }
    return state;
  }

  /// The pen's buttons as FLUTTER button bits, or null when no fresh
  /// report speaks for this moment.
  ///
  /// Either end touching is a PRIMARY (drawing) contact — the tail draws
  /// too, it just draws as the eraser. Which end it was is [freshInverted].
  int? freshButtons({DateTime? now}) {
    final state = _freshState(now);
    if (state == null) {
      return null;
    }
    var bits = 0;
    if (state.tip || state.eraser) {
      bits |= kPrimaryButton;
    }
    if (state.barrel) {
      bits |= kPrimaryStylusButton;
    }
    if (state.secondaryBarrel) {
      bits |= kSecondaryStylusButton;
    }
    return bits;
  }

  /// Whether the pen is turned TAIL-DOWN right now; null = no fresh
  /// report.
  ///
  /// HID Invert reports while merely HOVERING, which is what lets the tail
  /// mapping engage before the eraser ever touches the surface.
  bool? freshInverted({DateTime? now}) {
    final state = _freshState(now);
    if (state == null) {
      return null;
    }
    // Eraser (contact) implies inverted even on a device that omits the
    // Invert usage — the tail is what is touching.
    return state.inverted || state.eraser;
  }

  @visibleForTesting
  void debugInjectState(QaPenRawState state) {
    if (state.sequence != _lastSequence) {
      _lastSequence = state.sequence;
      _lastReportAt = _now();
    }
    latest.value = state;
  }

  @visibleForTesting
  void debugReset() {
    stop();
    debugPollOverride = null;
    debugClockOverride = null;
    _bridge = null;
    _lastReportAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
