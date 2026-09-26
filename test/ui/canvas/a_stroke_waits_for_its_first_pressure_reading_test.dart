import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🚨H43 (유저 2026-09-26, iPad): 「필압있는 브러시 쓸때 첫 펜다운한 부분? 만
/// 입력한 필압보다 센게나와. 최대치가 나오는거같기도하고」.
///
/// The first samples of a contact can carry a value the device has not
/// measured yet — UIKit's force estimate for Apple Pencil (exactly 1/3,
/// corrected later through a callback Flutter's engine never implements),
/// or a Wintab packet the driver took while the pen still hovered. The
/// stroke painted it. It now waits for the contact's first READING and
/// paints every sample that waited with it.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  final ipad = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'the iPad stroke that waited lands exactly as the same stroke would '
    'have if every sample had read its first reading',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        // The estimate on the down and on the first move, then the
        // Bluetooth catches up with a light touch.
        _pencil([
          (at: const Offset(4, 8), force: _estimate, time: _ms(0)),
          (at: const Offset(20, 8), force: _estimate, time: _ms(8)),
          (at: const Offset(40, 8), force: 0.25, time: _ms(16)),
          (at: const Offset(70, 8), force: 0.25, time: _ms(24)),
        ]),
        // The same hand, measured from the start.
        _pencil([
          (at: const Offset(4, 8), force: 0.25, time: _ms(0)),
          (at: const Offset(20, 8), force: 0.25, time: _ms(8)),
          (at: const Offset(40, 8), force: 0.25, time: _ms(16)),
          (at: const Offset(70, 8), force: 0.25, time: _ms(24)),
        ]),
      ]);

      expect(results, hasLength(2));
      final waited = results.first;
      expect(waited.first.center.x, 4, reason: 'the press still lands');
      expect(
        waited.map((dab) => dab.pressure).toSet(),
        {closeTo(0.25 / _pencilMax, 1e-9)},
        reason: 'no dab carries the estimate',
      );
      expect(_look(waited), _look(results.last));
    },
    variant: ipad,
  );

  testWidgets(
    'the wait holds the stabiliser to the order the pen moved in',
    (tester) async {
      final results = await _strokes(
        tester,
        _pressureBrush.copyWith(stabilizerStrength: 40),
        [
          _pencil([
            (at: const Offset(4, 8), force: _estimate, time: _ms(0)),
            (at: const Offset(30, 20), force: _estimate, time: _ms(8)),
            (at: const Offset(60, 4), force: _estimate, time: _ms(16)),
            (at: const Offset(90, 24), force: 0.5, time: _ms(24)),
            (at: const Offset(120, 8), force: 0.5, time: _ms(32)),
          ]),
          _pencil([
            (at: const Offset(4, 8), force: 0.5, time: _ms(0)),
            (at: const Offset(30, 20), force: 0.5, time: _ms(8)),
            (at: const Offset(60, 4), force: 0.5, time: _ms(16)),
            (at: const Offset(90, 24), force: 0.5, time: _ms(24)),
            (at: const Offset(120, 8), force: 0.5, time: _ms(32)),
          ]),
        ],
      );

      expect(_look(results.first), _look(results.last));
    },
    variant: ipad,
  );

  testWidgets(
    'a tap too short to be measured still leaves its dot, at what the '
    'device reported',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([(at: const Offset(10, 8), force: _estimate, time: _ms(0))]),
      ]);

      expect(results.single, hasLength(1));
      expect(results.single.single.center.x, 10);
      expect(
        results.single.single.pressure,
        closeTo(_estimate / _pencilMax, 1e-9),
      );
    },
    variant: ipad,
  );

  testWidgets(
    'a pen that never measures paints what it reports once the wait runs '
    'out — and a reading after that is used as it comes',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pencil([
          (at: const Offset(4, 8), force: _estimate, time: _ms(0)),
          (at: const Offset(20, 8), force: _estimate, time: _ms(20)),
          (at: const Offset(36, 8), force: _estimate, time: _ms(40)),
          // Past the patience, still the estimate: the stroke stops waiting.
          (at: const Offset(52, 8), force: _estimate, time: _ms(60)),
          (at: const Offset(90, 8), force: 2.0, time: _ms(80)),
        ]),
      ]);

      final dabs = results.single;
      expect(dabs.first.center.x, 4);
      expect(
        dabs.where((dab) => dab.center.x <= 52).map((dab) => dab.pressure),
        everyElement(closeTo(_estimate / _pencilMax, 1e-9)),
      );
      expect(dabs.last.pressure, closeTo(2.0 / _pencilMax, 1e-9));
    },
    variant: ipad,
  );

  testWidgets('within the patience the stroke keeps waiting', (tester) async {
    final results = await _strokes(tester, _pressureBrush, [
      _pencil([
        (at: const Offset(4, 8), force: _estimate, time: _ms(0)),
        (at: const Offset(20, 8), force: _estimate, time: _ms(25)),
        (at: const Offset(36, 8), force: _estimate, time: _ms(50)),
        (at: const Offset(60, 8), force: 1.0, time: _ms(58)),
      ]),
    ]);

    expect(
      results.single.map((dab) => dab.pressure).toSet(),
      {closeTo(1.0 / _pencilMax, 1e-9)},
    );
  }, variant: ipad);

  testWidgets(
    'a brush that does not read pressure never waits for it',
    (tester) async {
      // Observed through the pressure the dabs record: waiting would have
      // handed the pressed dab the later reading. The value draws nothing
      // for this brush — which is exactly why it must not hold the stroke.
      final results = await _strokes(
        tester,
        BrushEditCanvasInputSettings(
          size: 8,
          curves: {
            (BrushPressureTarget.size, BrushInputSource.speed):
                BrushPressureCurve.identity(),
          },
        ),
        [
          _pencil([
            (at: const Offset(4, 8), force: _estimate, time: _ms(0)),
            (at: const Offset(40, 8), force: 0.25, time: _ms(8)),
          ]),
        ],
      );

      expect(
        results.single.first.pressure,
        closeTo(_estimate / _pencilMax, 1e-9),
      );
    },
    variant: ipad,
  );

  testWidgets(
    'only UIKit hands over the estimate — elsewhere a third is a reading',
    (tester) async {
      final results = await _strokes(tester, _pressureBrush, [
        _pen(pressureMax: 1, [
          (at: const Offset(4, 8), force: 1 / 3, time: _ms(0)),
          (at: const Offset(40, 8), force: 0.9, time: _ms(8)),
        ]),
      ]);

      expect(results.single.first.pressure, closeTo(1 / 3, 1e-9));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a stroke cancelled while it waits leaves nothing behind for the next',
    (tester) async {
      final results = <List<BrushDab>>[];
      await _pump(tester, _pressureBrush, results);

      await _drive(
        tester,
        _pencil([
          (at: const Offset(4, 20), force: _estimate, time: _ms(0)),
          (at: const Offset(30, 20), force: _estimate, time: _ms(8)),
        ]),
        end: _End.cancel,
      );
      await _drive(
        tester,
        _pencil([
          (at: const Offset(50, 8), force: 0.25, time: _ms(100)),
          (at: const Offset(80, 8), force: 0.25, time: _ms(108)),
        ]),
      );

      expect(results, hasLength(1));
      expect(
        results.single.map((dab) => dab.center.y).toSet(),
        {8},
        reason: 'nothing the cancelled press held is painted',
      );
    },
    variant: ipad,
  );

  group('Wintab', () {
    late List<QaTabletPacket> queue;

    void live() {
      final service = WintabPenService.instance;
      WintabPenService.debugClockOverride = () => DateTime(2024);
      queue = <QaTabletPacket>[];
      service.debugPollOverride = () {
        final drained = queue;
        queue = [];
        return drained;
      };
      service.start();
    }

    testWidgets(
      'a packet the driver took while the pen still hovered is not the '
      'contact\'s first reading',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;
        // HID already reports the tip down — the press is a press — while
        // Wintab's queue still ends with the pen above the tablet.
        final hid = RawPenInputService.instance;
        RawPenInputService.debugClockOverride = () => DateTime(2024);
        hid.debugPollOverride = () =>
            const QaPenRawState(flags: 0x01, sequence: 1);
        hid.start();

        service.debugInjectPacket(_packet(pressure: 0, buttons: 0));
        _down(tester, const Offset(4, 8), time: _ms(0));
        await tester.pump();
        // The contact's packet reaches the queue before the first move.
        queue = [_packet(pressure: 0.6, buttons: 1)];
        _move(tester, const Offset(40, 8), time: _ms(8));
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.center.x, 4);
        expect(
          results.single.map((dab) => dab.pressure).toSet(),
          {closeTo(0.6, 1e-9)},
        );
        // The poll timers must die BEFORE the binding's pending-timer
        // invariant check (which runs ahead of tearDown callbacks).
        service.debugReset();
        hid.debugReset();
      },
    );

    testWidgets(
      'a press whose contact packet the timer had not taken yet still draws '
      '— at that packet\'s pressure',
      (tester) async {
        // The press's BUTTONS come off the same packet (PEN-7a), so the
        // timer's hovering copy did not just misweigh the first dab: it said
        // the tip was up, and the press drew nothing at all.
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;

        service.debugInjectPacket(_packet(pressure: 0, buttons: 0));
        queue = [_packet(pressure: 0.6, buttons: 1)];
        _down(tester, const Offset(4, 8), time: _ms(0));
        await tester.pump();
        _move(tester, const Offset(40, 8), time: _ms(8));
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.center.x, 4);
        expect(results.single.first.pressure, closeTo(0.6, 1e-9));
        service.debugReset();
      },
    );

    testWidgets(
      'once the contact has read, a hovering packet is the pen lifting — '
      'and 0 is its reading',
      (tester) async {
        final results = <List<BrushDab>>[];
        await _pump(tester, _pressureBrush, results);
        live();
        final service = WintabPenService.instance;

        service.debugInjectPacket(_packet(pressure: 0.6, buttons: 1));
        _down(tester, const Offset(4, 8), time: _ms(0));
        await tester.pump();
        queue = [_packet(pressure: 0, buttons: 0)];
        _move(tester, const Offset(40, 8), time: _ms(8));
        await tester.pump();
        _up(tester, const Offset(40, 8), time: _ms(16));
        await tester.pump();

        expect(results.single.first.pressure, closeTo(0.6, 1e-9));
        expect(results.single.last.pressure, 0.0);
        service.debugReset();
      },
    );
  });
}

/// Apple Pencil's `maximumPossibleForce`, which the iOS engine hands over
/// as the pointer's `pressureMax`.
const double _pencilMax = 25 / 6;

/// UIKit's stand-in force for a sample whose force has not arrived.
const double _estimate = 1 / 3;

final BrushEditCanvasInputSettings _pressureBrush =
    BrushEditCanvasInputSettings(
      size: 40,
      sizePressureCurve: BrushPressureCurve.identity(),
    );

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

typedef _Sample = ({Offset at, double force, Duration time});

typedef _Stroke = ({List<_Sample> samples, double pressureMax});

_Stroke _pencil(List<_Sample> samples) =>
    _pen(samples, pressureMax: _pencilMax);

_Stroke _pen(List<_Sample> samples, {required double pressureMax}) =>
    (samples: samples, pressureMax: pressureMax);

/// What a landed dab looks like on the cel — where, how big, how opaque —
/// in the order it was laid.
List<(double, double, double, double)> _look(List<BrushDab> dabs) => [
  for (final dab in dabs)
    (dab.center.x, dab.center.y, dab.size, dab.opacity),
];

Future<List<List<BrushDab>>> _strokes(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<_Stroke> strokes,
) async {
  final results = <List<BrushDab>>[];
  await _pump(tester, settings, results);
  for (final stroke in strokes) {
    await _drive(tester, stroke);
  }
  return results;
}

Future<void> _pump(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<List<BrushDab>> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveBrushEditCanvasView(
            sessionState: BrushEditSessionState(
              canvasState: CanvasSurfaceState(
                currentSurface: BitmapSurface(
                  canvasSize: const CanvasSize(width: 160, height: 32),
                  tileSize: 16,
                ),
              ),
              materializationHistoryState:
                  BrushBitmapMaterializationHistoryState(),
            ),
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: () => settings,
            onSourceStrokeCommitted: (data) => results.add(data.sourceDabs),
          ),
        ),
      ),
    ),
  );
}

enum _End { lift, cancel }

/// One stylus contact through raw pointer events — the only way a test can
/// set pressure — with the pointer id and clock stamps held constant between
/// runs, so two strokes of the same hand roll the same dice.
Future<void> _drive(
  WidgetTester tester,
  _Stroke stroke, {
  _End end = _End.lift,
}) async {
  final first = stroke.samples.first;
  _down(
    tester,
    first.at,
    time: first.time,
    force: first.force,
    pressureMax: stroke.pressureMax,
  );
  await tester.pump();
  for (final sample in stroke.samples.skip(1)) {
    _move(
      tester,
      sample.at,
      time: sample.time,
      force: sample.force,
      pressureMax: stroke.pressureMax,
    );
    await tester.pump();
  }
  final last = stroke.samples.last;
  tester.binding.handlePointerEvent(
    end == _End.lift
        ? PointerUpEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, last.at),
            timeStamp: last.time + _ms(4),
            pressureMax: stroke.pressureMax,
          )
        : PointerCancelEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: canvasGlobalOffset(tester, last.at),
            timeStamp: last.time + _ms(4),
          ),
  );
  await tester.pump();
}

void _down(
  WidgetTester tester,
  Offset at, {
  required Duration time,
  double force = 0,
  double pressureMax = 1,
}) => tester.binding.handlePointerEvent(
  PointerDownEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: canvasGlobalOffset(tester, at),
    timeStamp: time,
    pressure: force,
    pressureMin: 0,
    pressureMax: pressureMax,
  ),
);

void _move(
  WidgetTester tester,
  Offset at, {
  required Duration time,
  double force = 0,
  double pressureMax = 1,
}) => tester.binding.handlePointerEvent(
  PointerMoveEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: canvasGlobalOffset(tester, at),
    timeStamp: time,
    pressure: force,
    pressureMin: 0,
    pressureMax: pressureMax,
  ),
);

void _up(WidgetTester tester, Offset at, {required Duration time}) =>
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: canvasGlobalOffset(tester, at),
        timeStamp: time,
      ),
    );

QaTabletPacket _packet({required double pressure, required int buttons}) =>
    QaTabletPacket(
      pressure: pressure,
      tiltAzimuthDegrees: 0,
      altitude: 1,
      timeMs: 1,
      buttons: buttons,
    );
