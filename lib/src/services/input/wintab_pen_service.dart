import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../native/qa_tablet_bridge.dart';
import '../../models/app_input_settings.dart';

/// The Wintab pen stream (pen program, PEN-2) — the CSP-style second
/// tablet backend, as a PRESSURE SIDECAR:
///
/// Flutter's pointer events keep driving position and every gesture; this
/// service is handed the packets the reader heard of the DRIVER's queue
/// (through [QaTabletBridge] — the reader's own thread drains it) and holds
/// the freshest contact pressure/tilt. The brush canvas reads a point's own
/// driver pressure first and [freshPacket] otherwise — so a pen the OS
/// misreports (as touch, or as mouse with Ink unchecked) still paints with
/// the driver's full pressure.
///
/// Lifecycle: [bind] once at app start — the service follows
/// [AppInput.settings] (`tabletService == wintab` starts polling, anything
/// else stops it). Absence of the DLL/driver = permanently idle, silent.
class WintabPenService {
  WintabPenService._();

  static final WintabPenService instance = WintabPenService._();

  /// How often the packets heard are taken: drivers report 133–200Hz, and
  /// the reader's own thread drains the driver's queue every 4 ms
  /// (native/pen wintab.rs) — a take asks the driver nothing.
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

  /// Test hook: the bridge the service opens, polls and asks — null = the
  /// engine's own ([QaTabletBridge.instanceOrNull]).
  @visibleForTesting
  QaTabletBridge? debugBridge;

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

  /// How the service started, step by step, for the input inspector.
  ///
  /// 🗣️h61-wintab-sometimes-not-engaged-at-launch (관제 2026-11-21, from
  /// 브러시/렌더링 11-18): some runs right after launch heard no packet at
  /// all though the setting said Wintab — switching to standard and back
  /// brought it in — and nothing kept how the service had started, so a
  /// run that failed could not be told from one that did not. So each step
  /// is kept from the first apply on, `+ms` after it: a change of the
  /// setting applied (`APPLY`), the start or why it gave up (`START`), an
  /// open refused and why — again only when the why changes — (`OPEN no`),
  /// the try it opened at (`OPEN ok`), the first packet heard after
  /// (`HEARD`), a stop (`STOP`) and a safety demotion (`DEMOTE`).
  ///
  /// ⚠️Kept whether or not the inspector is shown, as its `seen` is: the
  /// launch is over before anyone opens it. The first [startRecordRoom]
  /// steps are kept — the launch is what this record is for.
  final List<String> startRecord = [];

  static const int startRecordRoom = 16;

  DateTime? _startRecordSince;
  TabletService? _lastApplied;
  int _openTries = 0;
  QaTabletOpen? _lastRefusal;
  bool _heardSinceStart = false;

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

  /// The driver's stream opens under [TabletService.wintab] and under
  /// nothing else.
  ///
  /// 🗣️F-331-Q1 (유저 2026-10-10, 「추천대로」): with Windows Ink off the OS
  /// hands the pen over as a mouse, with no pressure — and under
  /// [TabletService.standard] it DRAWS at pressure 1, as every other tool
  /// draws. The pressure is one switch away, here. ⛔Do not open this stream
  /// under standard to read the pressure there: the switch would stop
  /// meaning what it says, and one way of opening it cut the driver's cursor
  /// once (08-06, since fixed).
  void apply(AppInputSettings settings) {
    final service = settings.tabletService;
    if (service != _lastApplied) {
      _lastApplied = service;
      _remember('APPLY ${service.name} running=$running');
    }
    if (service == TabletService.wintab) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    if (_timer != null) {
      return;
    }
    _bridge ??= debugBridge ?? QaTabletBridge.instanceOrNull;
    if (debugPollOverride == null) {
      // No driver — stay idle (the standard graceful absence).
      if (_bridge == null) {
        _remember('START no bridge');
        return;
      }
      if (!_bridge!.available) {
        _remember('START no driver');
        return;
      }
    }
    _packetsWithoutPointer = 0;
    _sawPointerEvent = false;
    _openTries = 0;
    _lastRefusal = null;
    _heardSinceStart = false;
    _remember('START timer');
    _timer = Timer.periodic(pollInterval, (_) => _pump());
  }

  void stop() {
    if (_timer != null) {
      _remember('STOP');
    }
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
    _remember('DEMOTE packets=$_packetsWithoutPointer');
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
      if (bridge == null || !_opens(bridge)) {
        return;
      }
      packets = bridge.poll();
    }
    if (packets.isEmpty) {
      return;
    }
    if (!_heardSinceStart) {
      _heardSinceStart = true;
      _remember('HEARD first packet');
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

  /// Whether the context is open — opened now if not: it needs the app
  /// window, so it is tried again until the runner's window shows (first
  /// frames of app start).
  bool _opens(QaTabletBridge bridge) {
    if (_opened) {
      return true;
    }
    _openTries += 1;
    final open = bridge.open(within: freshWindow);
    _opened = open == QaTabletOpen.opened;
    if (_opened) {
      _remember('OPEN ok try=$_openTries');
    } else if (open != _lastRefusal) {
      _lastRefusal = open;
      _remember('OPEN no try=$_openTries ${open.name}');
    }
    return _opened;
  }

  /// While the service runs and its context has not opened: how many times
  /// it was tried, and why it last refused — null otherwise. The input
  /// inspector shows it beside the start record ([startRecord]).
  ({int tries, QaTabletOpen? refusal})? opening() => running && !_opened
      ? (tries: _openTries, refusal: _lastRefusal)
      : null;

  /// One step of [startRecord], `+ms` after its first.
  void _remember(String step) {
    final now = _now();
    final since = _startRecordSince ??= now;
    if (startRecord.length < startRecordRoom) {
      startRecord.add('+${now.difference(since).inMilliseconds}ms $step');
    }
  }

  /// What the driver's queue said while the stream is open: how far its
  /// newest packet was behind the mouse message last handled, in ms (null
  /// before one met a packet), and how many packets said the queue
  /// overflowed before them — null while it is closed. The input inspector
  /// shows it beside the packet.
  ({int? gapMs, int overflowed})? heard() {
    final bridge = _bridge;
    if (!_opened || bridge == null) {
      return null;
    }
    return (gapMs: bridge.clockGap(), overflowed: bridge.overflowed());
  }

  /// The driver's BUTTON state (raw Wintab bits) while the stream is live
  /// and fresh — null tells the caller to trust the pointer event's own
  /// buttons. [PenSidecars.freshButtons] translates the bits.
  int? freshButtons({DateTime? now}) => freshPacket(now: now)?.buttons;

  /// The driver's newest packet as of THIS call — null when this service
  /// is idle or its last packet has aged out of [freshWindow], which tells
  /// the caller to use the pointer event's own reading.
  /// [PenSidecars.freshReading] reads a pressure off it.
  ///
  /// Takes what was heard first: the poll timer can be a whole
  /// [pollInterval] behind.
  ///
  /// 🚨THE CONTACT IS HEARD AT THE PRESS (H43, 2026-09-26). The canvas asks at
  /// the pen's DOWN as well as along the stroke: the packet last taken was,
  /// as often as not, the pen still HOVERING — pressure 0, tip up. The first
  /// dab was stamped with that, and a press whose buttons were read off it
  /// did not draw at all. A message that presses drains the driver's queue
  /// before Flutter hears it (native/pen points_win.rs).
  ///
  /// ↩️This asked the driver itself (09-26 – 11-18): 🔬a quarter of a
  /// millisecond a call, and a mouse's sample made six or seven of them —
  /// under Wintab alone (F-600).
  QaTabletPacket? freshPacket({DateTime? now}) {
    if (_timer == null) {
      return null;
    }
    _pump();
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
    debugBridge = null;
    debugClockOverride = null;
    persistSettings = null;
    autoDemoted.value = false;
    _bridge = null;
    _lastPacketAt = DateTime.fromMillisecondsSinceEpoch(0);
    _packetsWithoutPointer = 0;
    _sawPointerEvent = false;
    startRecord.clear();
    _startRecordSince = null;
    _lastApplied = null;
    _openTries = 0;
    _lastRefusal = null;
    _heardSinceStart = false;
  }
}
