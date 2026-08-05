import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../native/qa_tablet_bridge.dart';
import '../../ui/input/app_input_settings.dart';

/// The Wintab pen stream (pen program, PEN-2) — the CSP-style second
/// tablet backend, as a PRESSURE SIDECAR:
///
/// Flutter's pointer events keep driving position and every gesture; this
/// service polls the DRIVER's packet queue (through [QaTabletBridge]) and
/// holds the freshest contact pressure/tilt. The brush canvas consults
/// [freshContactPressure] per pointer sample — so a pen the OS misreports
/// (as touch, or as mouse with Ink unchecked) still paints with the
/// driver's full pressure.
///
/// Lifecycle: [bind] once at app start — the service follows
/// [AppInput.settings] (`tabletService == wintab` starts polling, anything
/// else stops it). Absence of the DLL/driver = permanently idle, silent.
class WintabPenService {
  WintabPenService._();

  static final WintabPenService instance = WintabPenService._();

  /// Poll cadence: the Wintab queue holds ~128 packets and drivers report
  /// 133–200Hz — 8ms drains comfortably ahead of loss.
  static const Duration pollInterval = Duration(milliseconds: 8);

  /// A pressure sample older than this no longer overrides pointer events
  /// (the pen left proximity / the stream hiccuped).
  static const Duration freshWindow = Duration(milliseconds: 150);

  /// How many packets may arrive with ZERO pointer events before the
  /// service calls this path DEAD and demotes itself.
  ///
  /// The guard exists because the failure it catches is unrecoverable by
  /// hand: the service choice is persisted, so a Wintab context that eats
  /// the window's pointer input comes up eating it again after a restart,
  /// with no working pointer left to reach Input Settings and undo it.
  /// Packets flowing while NOTHING reaches the window means the driver
  /// stopped synthesizing pointer input for us.
  ///
  /// Drivers stream 133–200Hz, so this is ~1–1.5s of real pen use. It is
  /// deliberately generous, and any pointer event at all (mouse included)
  /// clears the suspicion for the session: a false demotion silently
  /// rewrites a working user's settings, which is worse than missing one
  /// — a missed case still leaves the mouse to fix it by hand.
  static const int deadPathPacketBudget = 200;

  /// Test hook: replaces the bridge's poll (packets in, wall-clocked as
  /// now). Null = the real DLL.
  List<QaTabletPacket> Function()? debugPollOverride;

  /// The freshest driver packet (null until one arrives) — the input
  /// inspector renders this line when live.
  final ValueNotifier<QaTabletPacket?> latest = ValueNotifier<QaTabletPacket?>(
    null,
  );

  /// Raised when [deadPathPacketBudget] tripped and the service put the
  /// setting back to [TabletService.standard] on its own — Input Settings
  /// reads this to explain why the choice reverted.
  final ValueNotifier<bool> autoDemoted = ValueNotifier<bool>(false);

  /// How a safety demotion PERSISTS. The service knows when the path went
  /// dead; the session owns the settings store, and the demotion has to
  /// survive the restart that would otherwise reopen the dead context.
  void Function(AppInputSettings settings)? persistSettings;

  QaTabletBridge? _bridge;
  Timer? _timer;
  bool _opened = false;
  DateTime _lastPacketAt = DateTime.fromMillisecondsSinceEpoch(0);
  VoidCallback? _settingsListener;
  int _packetsWithoutPointer = 0;
  bool _sawPointerEvent = false;

  /// The clock the freshness window reads. Production uses wall time;
  /// tests inject a fixed clock so a packet stays "fresh" regardless of
  /// how long the test binding takes between injecting it and polling the
  /// pressure — otherwise a busy suite lets the real 150ms window lapse
  /// mid-stroke and the driver pressure silently reverts to the pointer's
  /// (the "dab size 4.0 vs 4.25" flake).
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _now() => debugClockOverride?.call() ?? DateTime.now();

  bool get running => _timer != null;

  /// Follows the live input settings; safe to call once from main().
  void bind() {
    if (_settingsListener != null) {
      return;
    }
    _settingsListener = () => apply(AppInput.settings.value);
    AppInput.settings.addListener(_settingsListener!);
    apply(AppInput.settings.value);
  }

  void apply(AppInputSettings settings) {
    if (settings.tabletService == TabletService.wintab) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    if (_timer != null) {
      return;
    }
    _bridge ??= QaTabletBridge.instanceOrNull;
    if (debugPollOverride == null && (_bridge == null || !_bridge!.available)) {
      return; // No driver — stay idle (the standard graceful absence).
    }
    _packetsWithoutPointer = 0;
    _sawPointerEvent = false;
    _timer = Timer.periodic(pollInterval, (_) => _pump());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_opened) {
      _bridge?.close();
      _opened = false;
    }
    latest.value = null;
  }

  /// The dead-path guard's other half: ANY pointer event arriving anywhere
  /// in the app proves the window still receives input, which is exactly
  /// what a tablet-eating context takes away.
  ///
  /// The app-wide observer calls this (see `InputInspectorHost`) rather
  /// than the service reaching for a global pointer route itself — a
  /// pressure sidecar has no business requiring a widgets binding, and
  /// the unit tests that drive it directly have none.
  void notePointerActivity() {
    _sawPointerEvent = true;
  }

  /// Puts the setting back to the standard path and persists it — the one
  /// caller is the dead-path guard in [_pump].
  void _demoteForSafety() {
    autoDemoted.value = true;
    stop();
    final demoted = AppInput.settings.value.copyWith(
      tabletService: TabletService.standard,
    );
    final persist = persistSettings;
    if (persist != null) {
      persist(demoted);
    } else {
      // No shell wired (tests, or a very early failure): at least make the
      // live setting agree with the service that just stood down.
      AppInput.settings.value = demoted;
    }
  }

  void _pump() {
    final override = debugPollOverride;
    List<QaTabletPacket> packets;
    if (override != null) {
      packets = override();
    } else {
      final bridge = _bridge;
      if (bridge == null) {
        return;
      }
      if (!_opened) {
        // The context needs the app window — retry until the runner
        // window exists (first frames of app start).
        _opened = bridge.open();
        if (!_opened) {
          return;
        }
      }
      packets = bridge.poll();
    }
    if (packets.isEmpty) {
      return;
    }
    _lastPacketAt = _now();
    latest.value = packets.last;
    // Dead-path guard: the driver is clearly talking to US, so if nothing
    // at all reaches the WINDOW the context has taken the pointer stream
    // away and the user cannot undo the choice by hand.
    if (_sawPointerEvent) {
      return;
    }
    _packetsWithoutPointer += packets.length;
    if (_packetsWithoutPointer >= deadPathPacketBudget) {
      _demoteForSafety();
    }
  }

  /// The driver's CONTACT pressure when the stream is live and fresh —
  /// null tells the caller to use the pointer event's own pressure.
  /// Contact = pressure above zero; hovering pens stream 0 and must not
  /// flatten a real 0-pressure … the caller only asks mid-stroke.
  double? freshContactPressure({DateTime? now}) =>
      _freshPacket(now)?.pressure.clamp(0.0, 1.0);

  /// The driver's BUTTON state (raw Wintab bits) while the stream is live
  /// and fresh — null tells the caller to trust the pointer event's own
  /// buttons. [PenSidecars.freshButtons] translates the bits.
  int? freshButtons({DateTime? now}) => _freshPacket(now)?.buttons;

  /// The newest packet, or null when this service is idle or its last
  /// packet has aged out of [freshWindow].
  QaTabletPacket? _freshPacket(DateTime? now) {
    if (_timer == null) {
      return null;
    }
    final packet = latest.value;
    if (packet == null) {
      return null;
    }
    final age = (now ?? _now()).difference(_lastPacketAt);
    if (age > freshWindow) {
      return null;
    }
    return packet;
  }

  /// Test hook: lands one packet as if the poll just delivered it (the
  /// widget-test fake clock never fires the real timer).
  @visibleForTesting
  void debugInjectPacket(QaTabletPacket packet) {
    _lastPacketAt = _now();
    latest.value = packet;
  }

  /// Test hygiene: back to idle + forget listeners.
  @visibleForTesting
  void debugReset() {
    stop();
    if (_settingsListener != null) {
      AppInput.settings.removeListener(_settingsListener!);
      _settingsListener = null;
    }
    debugPollOverride = null;
    debugClockOverride = null;
    persistSettings = null;
    autoDemoted.value = false;
    _bridge = null;
    _lastPacketAt = DateTime.fromMillisecondsSinceEpoch(0);
    _packetsWithoutPointer = 0;
    _sawPointerEvent = false;
  }
}
