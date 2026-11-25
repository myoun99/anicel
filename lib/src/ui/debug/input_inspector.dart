import '../widgets/app_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';

import '../../native/qa_pen_points.dart';
import '../../native/qa_tablet_bridge.dart' show QaPenRawState, QaTabletPacket;
import '../../services/input/modifier_keys.dart';
import '../../services/input/pen_sidecars.dart';
import '../../services/input/platform_pen_channel_service.dart';
import '../../services/input/raw_pen_input_service.dart';
import '../../services/input/wintab_pen_service.dart';
import '../canvas/canvas_touch_contacts.dart' show CanvasTouchContacts;
import '../theme/app_theme.dart' show AppColors;
import '../widgets/content_scrollbar.dart';
import 'key_trace.dart';
import 'debug_type.dart';
import 'measurement_mode.dart';

/// The cross-platform INPUT INSPECTOR (pen program, PEN-1).
///
/// A debug overlay that shows, live, exactly what the platform delivers
/// for every pointer contact: device kind, phase, RAW pressure (with the
/// device's min/max range), tilt/orientation, buttons and pointer id —
/// plus the session's peak pressure.
///
/// Why it exists: pen problems are almost always classification problems
/// ("the pen arrives as touch", "pressure is flat 1.0") that happen in
/// the DRIVER/OS layer, out of the app's reach. One screenshot of this
/// overlay separates "driver misreports" from "app mishandles" — on any
/// platform, for any tablet brand — so it is both our development probe
/// and the remote-diagnosis channel for user reports.
abstract final class InputInspector {
  /// Whether the inspector watches — the debug window's one switch
  /// ([MeasurementMode.debugWindow]; 유저 2026-11-24,
  /// one-debug-window-shows-everything Q2), the same notifier, so the two
  /// cannot disagree. Tests flip it and MUST tearDown-reset via [reset].
  static final ValueNotifier<bool> visible = MeasurementMode.debugWindow
    ..addListener(_watchKeys);

  /// 🗣️F-241 (유저 2026-09-29): 「컨트롤 좌우 화살표 … 됏다가 안됏다가
  /// 이상함」 — a key that sometimes does nothing, and not on the X-sheet
  /// (F-241-Q1: 「가로 타임라인에서 안먹혓음」). Nothing on screen could say
  /// where a key went, so three lines follow each one, stamped with the
  /// KEY'S OWN time so they pair up whatever order they are written in:
  ///
  /// * `key` — it ARRIVED ([HardwareKeyboard], ahead of focus dispatch),
  ///   with every key the app believes is held and where focus is;
  /// * `bind` — the editor's shortcut table answered: the action it ran,
  ///   no binding, or a focused text field keeping it. A `bind` still on an
  ///   older stamp means the key never reached the table;
  /// * `eat` — playback spent it on a stop.
  ///
  /// The table and the gate write theirs through [KeyTrace], which this
  /// plugs in while shown.
  static void _watchKeys() {
    HardwareKeyboard.instance.removeHandler(_noteKey);
    KeyTrace.sink = null;
    if (visible.value) {
      HardwareKeyboard.instance.addHandler(_noteKey);
      KeyTrace.sink = note;
    }
  }

  static bool _noteKey(KeyEvent event) {
    if (event is! KeyUpEvent) {
      final focus = FocusManager.instance.primaryFocus;
      final held = [
        for (final key in ModifierKeys.keyboard.logicalKeysPressed)
          key.debugName ?? key.keyLabel,
      ];
      note(
        'key ${KeyTrace.stamp(event)} held [${held.join(', ')}] · focus '
        '${focus?.debugLabel ?? focus?.context?.widget.runtimeType}',
      );
    }
    return false;
  }

  /// Bumped once per recorded event — the card listens to this, nothing
  /// else rebuilds.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The latest event of each kind and phase (`stylus move`, `touch
  /// down`…), ONE SLOT EACH by the law of [notes] and by its code
  /// ([_put]): the rows in the order their kind and phase first came.
  ///
  /// 🗣️유저 2026-11-24 (the-input-inspector-climbs-and-cuts-its-lines-Q1):
  /// 종류·단계마다 한 칸. ↩️A ring of the last 120, its last ten on the
  /// card: a stream of hovers pushed the one down the line was read for
  /// out of sight, and every row moved up at every event.
  static final Map<String, InputInspectorSample> events =
      <String, InputInspectorSample>{};

  /// The highest RAW pressure seen since the last [clear] — the quickest
  /// "is pressure alive at all" check.
  static double peakPressure = 0;

  /// PEN-10: TOUCH pointer-downs seen since the last [clear]. The
  /// hover-palm-rejection diagnosis on S-Pen tablets: hover the pen and
  /// tap with fingers — if this counter does not move, the OS suppressed
  /// the touches before the app ever saw them.
  static int touchDownCount = 0;

  /// 🚨★★H21 (유저 2026-08-23): 「인풋 인스펙터가 **리셋도안먹고 처음 키고
  /// 1초정도 조작하면 멈춰.** 초반1초조작만 인식하고 그 뒤 인식 안하는거같은데」
  ///
  /// ⛔A BROKEN INSTRUMENT IS WORSE THAN NO INSTRUMENT — this one was read
  /// as evidence three times in a day. And the freeze could not be
  /// diagnosed FROM the card, because every number on it came through the
  /// same [record] that had stopped: nothing on screen could tell 「the
  /// Listener is no longer called」 apart from 「the Listener is called and
  /// the recorder drops it」.
  ///
  /// ★So this counts ARRIVALS, ahead of every gate — bumped by the host's
  /// observer the instant an event reaches it, whether or not the inspector
  /// is visible and whether or not the sample is kept. One glance now
  /// separates the two failures:
  ///
  /// * `seen` climbing while the rows stand still ⇒ the RECORDER is at
  ///   fault (a gate, the ring, the phase filter);
  /// * `seen` frozen as well ⇒ DELIVERY stopped, and the fault is in the
  ///   tree above this host.
  ///
  /// ⚠️Deliberately NOT gated on [visible]: a counter that stops counting
  /// when you stop looking cannot answer the question it exists for.
  ///
  /// ⚠️ONE gate stands ahead of it: the binding keeps a pen's echo out
  /// before any listener hears it (F-400), and counts it in [echoes].
  static int arrivals = 0;

  /// F-400: the events the binding kept out as a pen's echo — a mouse's
  /// hovers and presses while a pen is in range on Windows. Counted where
  /// they are dropped, ahead of [arrivals], so a `mouse hover` row that
  /// stopped coming says whether Windows stopped sending it or the app kept
  /// it out. Not gated on [visible], for the reason [arrivals] is not.
  static int echoes = 0;

  /// PEN-10: probe lines, ONE SLOT PER EMITTER — keyed by the line's first
  /// token (`aim`·`buf`·`geom`·`cmp`·`stack`·`tl`…), the latest line per
  /// key, rows in the order the emitters first spoke. Call sites annotate
  /// where an event landed (e.g. the timeline down/IN probes). Ignored
  /// while the inspector is hidden.
  ///
  /// 🗣️유저 2026-09-13 (`inspector-ring-one-slot-per-emitter-Q1`):
  /// 「발화자마다 한 칸」. This was a five-line ring, newest last, and the
  /// loudest emitter evicted the rest — in one day the T12 line printed
  /// per rebuild, the buffer counters per compose and the `aim` line per
  /// hover move: 「aim census 때문에 글자가 갱신돼서 확인하기 힘들었다」. A
  /// cadence per emitter would have been a rule per emitter, invented
  /// again for every new one; the ring's shape was the law to change. An
  /// emitter still owns WHEN it speaks (its own dedupe); the ring owns
  /// WHERE the line lands.
  ///
  /// ⛔TWO EMITTERS, TWO TOKENS. The ring tells facts apart only by their
  /// first word: the PEN-10 pair `tl dn=` / `range IN=` diagnoses a
  /// hit-test exclusion by the second line's ABSENCE, and under one token
  /// the second would overwrite the first on every down and the absence
  /// could never be seen. A new emitter takes a word nobody else prints.
  static final Map<String, String> notes = <String, String>{};

  /// 🚨★★★H21 — **THE FREEZE, AND IT WAS THIS.** (유저 2026-08-23, 스택
  /// 트레이스 첨부): 「인스펙터 키고 **터치하거나 키보드 조작하거나 마우스
  /// 클릭하거나 하면 뜸.** 이게 멈추는 원인같기도하고」
  ///
  /// ```
  /// setState() or markNeedsBuild() called during build.
  ///   #3 _ValueListenableBuilderState._valueChanged
  ///   #5 ValueNotifier.value=
  ///   #6 InputInspector.note (input_inspector.dart:87)
  ///   #7 _EditorCanvasAreaState._buildInteractiveCanvas (…:604)
  ///   #11 _FrameRetargetScopeState.build
  /// ```
  ///
  /// ⛔A PROBE THAT NOTIFIES DURING BUILD KILLS ITS OWN DISPLAY — **once,
  /// permanently.** `State.setState` runs its callback and THEN calls
  /// `markNeedsBuild()`, so the builder's `_value` is updated and the
  /// element is never marked dirty: the card holds the frame it was
  /// showing and no later notification can wake it, because every
  /// subsequent build-time probe throws the same way.
  ///
  /// 🎯That is the whole report. The recorder was never broken — `record`
  /// kept filling `samples` and `seen` kept climbing (유저 스샷:
  /// `touch downs=2 seen=6783`); only the picture stopped. Hovering was
  /// fine because it does not take the canvas' build path, while a touch, a
  /// key or a click does — 「호버중엔 인스펙터 정상작동해」.
  ///
  /// ⚠️And this is why the frozen card was such bad evidence: it kept
  /// rendering an old frame rather than going blank, so it looked like
  /// live testimony. I read it as such three times.
  ///
  /// ★So the bump waits for the frame to end whenever one is running.
  /// Coalesced: a build that emits ten probes schedules one rebuild.
  static bool _bumpScheduled = false;

  static void _bumpRevision() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      revision.value += 1;
      return;
    }
    if (_bumpScheduled) {
      return;
    }
    _bumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _bumpScheduled = false;
      revision.value += 1;
    });
  }

  static void note(String line) {
    final split = line.indexOf(' ');
    _put(notes, split < 0 ? line : line.substring(0, split), line);
  }

  /// STATE lines, one per [key], shown above the event rows and kept until
  /// overwritten — for a fact that describes the session rather than a
  /// moment, such as where layout put the canvas on the device grid.
  ///
  /// ⛔Not [notes]: those are EVENTS, and the card's ⟲ ([clear]) wipes
  /// them; a layout fact is not an event and survives it. The map was born
  /// of the F-67 hands-on (2026-09-11): the ring was five lines then, and
  /// the paint probes pushed the layout line out within two frames — the
  /// screenshot came back without the one number it was taken for. The
  /// keyed ring closed the eviction; the lifetime is what still differs.
  static final Map<String, String> pinned = <String, String>{};

  static void pin(String key, String line) => _put(pinned, key, line);

  /// One slot per key, and a bump only when the slot's text changes — an
  /// emitter that repeats itself costs the card nothing.
  static void _put<T>(Map<String, T> slots, String key, T line) {
    if (!visible.value || slots[key] == line) {
      return;
    }
    slots[key] = line;
    _bumpRevision();
  }

  static void record(PointerEvent event) {
    final phase = _phaseOf(event);
    if (phase == null) {
      return;
    }
    final sample = InputInspectorSample.of(event, phase);
    _put(events, '${sample.kind.name} $phase', sample);
    // Peak tracks CONTACT pressure only — hovers idle at 0 by contract.
    if ((phase == 'down' || phase == 'move') && event.pressure > peakPressure) {
      peakPressure = event.pressure;
    }
    if (phase == 'down' && event.kind == PointerDeviceKind.touch) {
      touchDownCount += 1;
    }
  }

  static String? _phaseOf(PointerEvent event) => switch (event) {
    PointerDownEvent() => 'down',
    PointerMoveEvent() => 'move',
    PointerUpEvent() => 'up',
    PointerCancelEvent() => 'cancel',
    PointerHoverEvent() => 'hover',
    PointerScrollEvent() => 'scroll',
    PointerPanZoomStartEvent() => 'panzoom',
    PointerPanZoomUpdateEvent() => 'panzoom',
    _ => null,
  };

  /// Clears the events + peak + counters/notes (the card's ⟲).
  static void clear() {
    events.clear();
    peakPressure = 0;
    touchDownCount = 0;
    arrivals = 0;
    echoes = 0;
    notes.clear();
    _bumpRevision();
  }

  /// Full reset for tests (visibility and the pinned state lines included).
  static void reset() {
    clear();
    pinned.clear();
    visible.value = false;
  }
}

/// One recorded event, snapshotted at arrival (events are pooled — never
/// hold the live object).
class InputInspectorSample {
  const InputInspectorSample({
    required this.phase,
    required this.kind,
    required this.pressure,
    required this.pressureMin,
    required this.pressureMax,
    required this.tilt,
    required this.orientation,
    required this.buttons,
    required this.pointer,
    required this.position,
  });

  factory InputInspectorSample.of(PointerEvent event, String phase) =>
      InputInspectorSample(
        phase: phase,
        kind: event.kind,
        pressure: event.pressure,
        pressureMin: event.pressureMin,
        pressureMax: event.pressureMax,
        tilt: event.tilt,
        orientation: event.orientation,
        buttons: event.buttons,
        pointer: event.pointer,
        position: event.position,
      );

  final String phase;
  final PointerDeviceKind kind;
  final double pressure;
  final double pressureMin;
  final double pressureMax;
  final double tilt;
  final double orientation;
  final int buttons;
  final int pointer;
  final Offset position;

  String describe() {
    final buffer = StringBuffer()
      ..write(kind.name.padRight(7))
      ..write(phase.padRight(8))
      ..write('p=${pressure.toStringAsFixed(2)}');
    if (pressureMin != 0 || pressureMax != 1) {
      buffer.write(
        ' [${pressureMin.toStringAsFixed(1)}–${pressureMax.toStringAsFixed(1)}]',
      );
    }
    if (tilt != 0) {
      buffer.write(' tilt=${tilt.toStringAsFixed(2)}');
    }
    if (orientation != 0) {
      buffer.write(' or=${orientation.toStringAsFixed(2)}');
    }
    if (buttons != 0) {
      buffer.write(' btn=$buttons');
    }
    buffer
      ..write(' #$pointer ')
      ..write('(${position.dx.round()},${position.dy.round()})');
    return buffer.toString();
  }
}

/// Wraps the editor body: invisible until [InputInspector.visible] — then
/// a translucent listener records every pointer event passing anywhere
/// through the app, for the panel the debug window shows
/// ([InputInspectorPanel]). The listener never
/// competes in any gesture arena (raw observation only), so recording
/// changes NOTHING about input behavior.
class InputInspectorHost extends StatelessWidget {
  const InputInspectorHost({super.key, required this.child});

  final Widget child;

  static void _observePointer(PointerEvent event) {
    // Unconditional, and not the inspector's own business: this listener
    // is the app's ONE always-mounted view of every pointer event, and the
    // Wintab dead-path guard needs exactly that signal — packets arriving
    // while NOTHING reaches the window is what a tablet-eating context
    // looks like from the inside.
    WintabPenService.instance.notePointerActivity();
    // H21: counted BEFORE every gate — see [InputInspector.arrivals]. This
    // is the one number that can say whether this observer is still being
    // called at all, which is exactly what the freeze report needed and
    // exactly what the card could not show.
    InputInspector.arrivals += 1;
    // 🚨D34: the app-wide finger census rides the same always-mounted
    // observer — it is the only place that sees a touch whichever panel it
    // lands on. NOT gated on visibility: this is app state, not a probe.
    CanvasTouchContacts.noteAppWide(event);
    if (InputInspector.visible.value) {
      InputInspector.record(event);
    }
  }

  @override
  Widget build(BuildContext context) {
    // R26 #33: the tree SHAPE is constant — the listener is always
    // mounted, and visibility only decides whether its events record.
    // The old build swapped `child` between wrapped and bare, remounting the
    // ENTIRE editor under it on every toggle — that remount's relayout
    // was the visible "layout jumps, then comes back". The gate lives in
    // the HOST's handlers (not in [InputInspector.record]) so the pen
    // sidecar services keep their direct-record contract.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _observePointer,
      onPointerMove: _observePointer,
      onPointerUp: _observePointer,
      onPointerCancel: _observePointer,
      onPointerHover: _observePointer,
      onPointerSignal: _observePointer,
      onPointerPanZoomStart: _observePointer,
      onPointerPanZoomUpdate: _observePointer,
      child: child,
    );
  }
}

/// The inspector's SECOND highlight — touch rows and sidecar services, which
/// must not read as the accent because the accent means stylus here.
///
/// A literal on purpose: this is a debug screen, and the app-wide second
/// accent it used to borrow was deleted for having exactly one production
/// consumer. A debug-only distinction does not earn a palette token.
const Color _inspectorSecondInk = Color(0xFFD972A8);

/// What the inspector shows — its lines, with no card around them: what a
/// window holding it lays where it likes (card one-debug-window-shows-
/// everything, 2026-11-24).
///
/// 🚨ITS SIZE IS ITS OWN, WHATEVER IT SAYS (card the-input-inspector-climbs-
/// and-cuts-its-lines, 유저 2026-11-24 「입력인스펙터는 게다가 줄이 매번올라가서
/// 보이지도않고 오른쪽부분 잘리고」): every line has its place before it has
/// anything to say — the readouts say `-` — and what comes in numbers it
/// cannot know (the events, a slot per kind and phase; the pins; the
/// driver's start; the probes' notes) is laid in the panel's own scroll,
/// a slot kept where it first came. No line is cut: a line too long for
/// the panel wraps.
/// ↩️A column as tall as what it held, on a card laid by its bottom edge —
/// its top climbed at every note, pin and readout that came — and no wider
/// than 340, every line cut to one with an ellipsis.
class InputInspectorPanel extends StatelessWidget {
  const InputInspectorPanel({super.key});

  /// As wide as the longest line it writes (an event row with its tilt,
  /// its orientation and its buttons) — and well inside the narrowest
  /// window it is read on, a Galaxy Tab's 1579 logical pixels.
  static const double width = 560;

  /// Its height, in lines.
  static const int lines = 26;

  static TextStyle get _line => DebugType.line;

  /// The height of one line it writes.
  static double get lineHeight => _line.fontSize! * _line.height!;

  /// The HID switches currently declared down, or '-' for none.
  static String _rawPenLabel(QaPenRawState state) {
    final parts = <String>[
      if (state.tip) 'tip',
      if (state.barrel) 'barrel',
      if (state.eraser) 'eraser',
      if (state.inverted) 'inv',
      if (state.secondaryBarrel) 'barrel2',
    ];
    return parts.isEmpty ? '-' : parts.join('+');
  }

  static Color _kindColor(ColorScheme colorScheme, PointerDeviceKind kind) =>
      switch (kind) {
        PointerDeviceKind.stylus ||
        PointerDeviceKind.invertedStylus => AppColors.accent,
        PointerDeviceKind.touch => _inspectorSecondInk,
        _ => colorScheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey<String>('input-inspector-panel'),
      width: width,
      height: lines * lineHeight,
      child: ValueListenableBuilder<int>(
        valueListenable: InputInspector.revision,
        builder: (context, _, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(colorScheme),
            _readouts(),
            Expanded(
              child: ContentScrollbar(
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _strip(),
                      ..._comeAndGo(colorScheme),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _titleSaid = 'INPUT INSPECTOR';

  Widget _title(ColorScheme colorScheme) => Row(
    children: [
      Expanded(
        child: Text(
          _titleSaid,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const AppIconButton(
        keyValue: 'input-inspector-clear',
        tooltip: 'Clear',
        size: AppIconButtonSize.micro,
        onPressed: InputInspector.clear,
        icon: Icon(Icons.refresh),
      ),
      AppIconButton(
        keyValue: 'input-inspector-close',
        tooltip: 'Close',
        size: AppIconButtonSize.micro,
        // 🚨H21 (유저 2026-08-23): 「터치 다운도 **껏다켜도 리셋안되고**」 —
        // and that was not a bug in the counter. Closing only flipped
        // [InputInspector.visible]; NOTHING cleared, so re-opening showed
        // the session before last. A diagnosis surface you just re-opened
        // is a fresh one by every reasonable reading.
        onPressed: () {
          InputInspector.clear();
          InputInspector.visible.value = false;
        },
        icon: const Icon(Icons.close),
      ),
    ],
  );

  /// The pressures side by side, each in its place while it says nothing
  /// (`-`): the pointer's peak, the tablet driver's (PEN-2 — pointer vs
  /// driver pressure is the whole misreport diagnosis), the raw HID
  /// switches the PEN itself declares (on Windows the only place its tail
  /// end appears at all — Ink drops it and the pointer stream calls both
  /// ends "stylus"), and the macOS/Linux channel sidecars' (PEN-4).
  Widget _readouts() => Wrap(
    spacing: 6,
    children: [
      Text(
        _peakSaid(),
        key: const ValueKey<String>('input-inspector-peak'),
        style: _line.copyWith(color: AppColors.accent),
      ),
      ValueListenableBuilder<QaTabletPacket?>(
        valueListenable: WintabPenService.instance.latest,
        builder: (context, packet, _) => Text(
          _wintabSaid(packet),
          key: const ValueKey<String>('input-inspector-wintab'),
          style: _line.copyWith(color: _inspectorSecondInk),
        ),
      ),
      ValueListenableBuilder<QaPenRawState?>(
        valueListenable: RawPenInputService.instance.latest,
        builder: (context, state, _) => Text(
          _rawPenSaid(state),
          key: const ValueKey<String>('input-inspector-rawpen'),
          style: _line.copyWith(color: _inspectorSecondInk),
        ),
      ),
      for (final service in PenSidecars.channelServices)
        ValueListenableBuilder<PenChannelSample?>(
          valueListenable: service.latest,
          builder: (context, sample, _) => Text(
            _sidecarSaid(service.label, sample),
            key: ValueKey<String>('input-inspector-${service.label}'),
            style: _line.copyWith(color: _inspectorSecondInk),
          ),
        ),
    ],
  );

  static String _peakSaid() =>
      'peak p=${InputInspector.peakPressure.toStringAsFixed(2)}';

  static String _wintabSaid(QaTabletPacket? packet) =>
      'wt p=${packet?.pressure.toStringAsFixed(2) ?? '-'}';

  static String _rawPenSaid(QaPenRawState? state) =>
      'hid ${state == null ? '-' : _rawPenLabel(state)}';

  static String _sidecarSaid(String label, PenChannelSample? sample) =>
      '$label p=${sample?.pressure.toStringAsFixed(2) ?? '-'}';

  /// The readouts as [_readouts] writes them, each of what its source says
  /// now.
  static List<String> _readoutsSaid() => [
    _peakSaid(),
    _wintabSaid(WintabPenService.instance.latest.value),
    _rawPenSaid(RawPenInputService.instance.latest.value),
    for (final service in PenSidecars.channelServices)
      _sidecarSaid(service.label, service.latest.value),
  ];

  /// PEN-10 diagnosis strip: the touch-down counter (the pen-hover
  /// palm-rejection check) and what the pointer stream lost on its way.
  Widget _strip() => Text(
    _stripSaid(),
    key: const ValueKey<String>('input-inspector-touch-count'),
    style: _line.copyWith(color: _inspectorSecondInk),
  );

  static String _stripSaid() =>
      'touch downs=${InputInspector.touchDownCount}'
      // 🚨H21: `seen` is counted at the observer, ahead of every gate. If it
      // climbs while the rows above stand still, the recorder is dropping
      // events; if it stands still too, delivery to this host has stopped.
      // That one distinction is what the card could not make while it was
      // the thing being diagnosed.
      ' seen=${InputInspector.arrivals}'
      // F-400: and what the binding kept out ahead of it.
      ' echo=${InputInspector.echoes}'
      // H56: and the messages whose points the OS saw no datum took — each
      // a stretch of a line lost.
      ' passed=${QaPenPoints.passed}'
      // H59 법 A: and those whose points did not all reach the book, by why.
      ' lost=${_lostSaid(QaPenPoints.lost)}'
      // And while the tablet driver's stream is open, how far its newest
      // packet ran behind the mouse message and the overflows its queue
      // said: a pkTime on another clock pairs no mouse point with the driver.
      '${_wintabHeard()}';

  /// What comes in numbers the panel cannot know: the pins, how the
  /// tablet driver's stream started (h61-wintab-sometimes-not-engaged-at-
  /// launch — the service keeps it from launch, before the panel opens,
  /// and ⟲ does not clear it), the events and the probes' notes, a line
  /// each — what changes least first.
  List<Widget> _comeAndGo(ColorScheme colorScheme) => [
    for (final said in _comeAndGoSaid())
      Text(
        said.text,
        key: said.key == null ? null : ValueKey<String>(said.key!),
        style: _line.copyWith(color: said.ink(colorScheme)),
      ),
  ];

  /// [_comeAndGo]'s lines, in its order: each one's words, its key and its
  /// ink — and none of the events' while none came.
  static List<_Said> _comeAndGoSaid() => [
    for (final entry in InputInspector.pinned.entries)
      (
        text: entry.value,
        key: 'input-inspector-pin-${entry.key}',
        ink: (_) => AppColors.accent,
      ),
    for (final (i, step) in WintabPenService.instance.startRecord.indexed)
      (
        text: 'wt $step',
        key: 'input-inspector-wintab-start-$i',
        ink: (_) => _inspectorSecondInk,
      ),
    if (InputInspector.events.isEmpty)
      (
        text: 'waiting for input…',
        key: null,
        ink: (colorScheme) => colorScheme.onSurfaceVariant,
      ),
    for (final MapEntry(:key, value: sample) in InputInspector.events.entries)
      (
        text: sample.describe(),
        key: 'input-inspector-event-$key',
        ink: (colorScheme) => _kindColor(colorScheme, sample.kind),
      ),
    for (final line in InputInspector.notes.values)
      (
        text: line,
        key: null,
        ink: (colorScheme) => colorScheme.onSurfaceVariant,
      ),
  ];

  /// What the panel writes, as text, in its order — the title, the
  /// readouts, the strip, and what comes and goes: what the debug window's
  /// copy takes. Its widgets take their words from the same functions.
  static List<String> textLines() => [
    _titleSaid,
    ..._readoutsSaid(),
    _stripSaid(),
    for (final said in _comeAndGoSaid()) said.text,
  ];
}

/// One line [InputInspectorPanel] writes in what comes and goes: its words,
/// its key, and its ink on the panel's colours.
typedef _Said = ({
  String text,
  String? key,
  Color Function(ColorScheme colorScheme) ink,
});

/// What the tablet driver's queue said ([WintabPenService.heard]) — or,
/// while its context is still being opened, the tries and why the last
/// refused ([WintabPenService.opening]) — as the strip says it.
String _wintabHeard() {
  final service = WintabPenService.instance;
  final heard = service.heard();
  if (heard != null) {
    return ' wt gap=${heard.gapMs ?? '-'} over=${heard.overflowed}';
  }
  final opening = service.opening();
  return opening == null
      ? ''
      : ' wt open try=${opening.tries} ${opening.refusal?.name ?? '-'}';
}

/// What the point book lost ([QaPenPoints.lost]), by why, as the strip
/// says it.
String _lostSaid(({int full, int unread}) lost) =>
    'full ${lost.full} unread ${lost.unread}';
