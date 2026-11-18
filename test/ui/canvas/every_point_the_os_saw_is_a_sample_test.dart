import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/pen_path.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

import '../../helpers/the_points_the_os_saw.dart';
import '../brush_canvas_test_helpers.dart';

/// 🗣️H56 (유저 2026-11-14): 「선 빠르게그으면 곡선이아니라 각져져서
/// 포인트끼리 이어지는거 살짝 남아있는데 … 점이 들어오는 길이 이상하지
/// 않냐는거야」 → 「플랫폼 구분없이 통합해결」.
///
/// A message the OS merged points into is ONE pointer event; the points
/// ride it ([PenPath]). The line those points make is the line the same
/// points make as an event each — the press, every move and the lift —
/// down to every input a dab carries: where, how big, the pressure, the
/// speed read off each point's own time.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    QaPenPoints.debugTake = null;
  });

  testWidgets(
    'a move the OS merged three points into lays the line the three would',
    (tester) async {
      final merged = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 0, 0.5)),
        _merged([_p(20, 10, 8, 0.6), _p(36, 16, 13, 0.7), _p(60, 12, 30, 0.4)]),
        _lift(_p(60, 12, 34, 0)),
      ]);
      final apart = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 0, 0.5)),
        _merged([_p(20, 10, 8, 0.6)]),
        _merged([_p(36, 16, 13, 0.7)]),
        _merged([_p(60, 12, 30, 0.4)]),
        _lift(_p(60, 12, 34, 0)),
      ]);

      expect(merged.where((dab) => dab.center.y > 13), isNotEmpty);
      expect(_look(merged), _look(apart));
    },
  );

  testWidgets(
    'a pen lays each point at the pressure the driver gave it — handed over '
    'as a mouse or read by the OS — as a stylus lays its own: not the newest '
    "packet's",
    (tester) async {
      final stylus = await _line(
        tester,
        _pressureAndSpeed,
        _stroke(PointerDeviceKind.stylus),
      );
      final wintab = WintabPenService.instance;
      WintabPenService.debugClockOverride = () => DateTime(2024);
      wintab.debugPollOverride = () => const [];
      wintab.start();
      wintab.debugInjectPacket(
        const QaTabletPacket(pressure: 0.9, timeMs: 0, buttons: 1),
      );
      final mouse = await _line(
        tester,
        _pressureAndSpeed,
        _stroke(PointerDeviceKind.mouse),
        driven: true,
      );
      final inked = await _line(
        tester,
        _pressureAndSpeed,
        _stroke(PointerDeviceKind.stylus),
        driven: true,
      );
      // The poll timer must die before the binding's pending-timer check.
      wintab.debugReset();

      expect(
        stylus.map((dab) => dab.pressure).toSet(),
        hasLength(greaterThan(2)),
        reason: 'a line of the points\' own pressures',
      );
      expect(_look(mouse), _look(stylus), reason: 'Windows Ink off');
      expect(_look(inked), _look(stylus), reason: 'Windows Ink on (H61)');
    },
  );

  testWidgets('the steadied line takes each point at its own time', (
    tester,
  ) async {
    final steadied = _pressureAndSpeed.copyWith(
      correction: const BrushCorrection(stabilization: 40),
    );
    final merged = await _line(tester, steadied, [
      _press(_p(4, 8, 0, 0.5)),
      _merged([_p(30, 20, 6, 0.5), _p(60, 4, 9, 0.5), _p(90, 24, 30, 0.5)]),
      _lift(_p(90, 24, 34, 0)),
    ]);
    final apart = await _line(tester, steadied, [
      _press(_p(4, 8, 0, 0.5)),
      _merged([_p(30, 20, 6, 0.5)]),
      _merged([_p(60, 4, 9, 0.5)]),
      _merged([_p(90, 24, 30, 0.5)]),
      _lift(_p(90, 24, 34, 0)),
    ]);

    expect(_look(merged), _look(apart));
  });

  testWidgets(
    'the points the OS merged into the lift are the line\'s last stretch',
    (tester) async {
      final merged = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 0, 0.5)),
        _merged([_p(30, 8, 8, 0.5)]),
        _lift(_p(90, 20, 20, 0), before: [_p(60, 14, 12, 0.6)]),
      ]);
      final apart = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 0, 0.5)),
        _merged([_p(30, 8, 8, 0.5)]),
        _merged([_p(60, 14, 12, 0.6)]),
        _lift(_p(90, 20, 20, 0)),
      ]);

      expect(merged.last.center.x, greaterThan(50));
      expect(_look(merged), _look(apart));
    },
  );

  testWidgets(
    'the press is taken at the time the OS saw it, which the first move\'s '
    'speed is read from',
    (tester) async {
      // The press handled 6 ms after the OS saw it — the clock its moves
      // are on: the first move is 40 ms of travel, not 34. Slow enough
      // that neither reaches the speed's ceiling, where both read 1.
      final seen = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 6, 0.5), seenAt: _ms(0)),
        _merged([_p(12, 8, 40, 0.5)]),
        _lift(_p(12, 8, 48, 0)),
      ]);
      final handled = await _line(tester, _pressureAndSpeed, [
        _press(_p(4, 8, 0, 0.5)),
        _merged([_p(12, 8, 40, 0.5)]),
        _lift(_p(12, 8, 48, 0)),
      ]);

      expect(handled, isNotEmpty);
      expect(_look(seen), _look(handled));
    },
  );

  testWidgets(
    "the inspector's press line says where each sample took its pressure, "
    "and how far the driver's stood from the pen's own (H61)",
    (tester) async {
      InputInspector.visible.value = true;
      addTearDown(InputInspector.reset);
      final wintab = WintabPenService.instance;
      WintabPenService.debugClockOverride = () => DateTime(2024);
      addTearDown(() => WintabPenService.debugClockOverride = null);
      wintab.debugPollOverride = () => const [];
      wintab.start();
      wintab.debugInjectPacket(
        const QaTabletPacket(pressure: 0.9, timeMs: 0, buttons: 1),
      );
      // Windows Ink on: each point the OS saw carries the pen's own 0.15
      // and the driver's pressure beside it ([_line]'s `driven`) — the
      // press and a merged move's two. A move the OS merged nothing into
      // is its own point, the driver's newest packet (0.9) beside the
      // pen's 0.6.
      final lines = <String?>[];
      await _line(
        tester,
        _pressureAndSpeed,
        [
          _press(_p(4, 8, 0, 0.5), seenAt: _ms(0), pressureMin: 0),
          _merged([_p(20, 10, 8, 0.3), _p(36, 16, 13, 0.3)], pressureMin: 0),
          _merged([_p(48, 14, 20, 0.6)], pressureMin: 0),
          _lift(_p(60, 12, 34, 0), pressureMin: 0),
          // The next stroke on the same canvas is counted alone: two
          // samples, the driver's newest beside the pen's 0.45.
          _press(_p(4, 24, 50, 0.45), pressureMin: 0),
          _merged([_p(30, 24, 60, 0.45)], pressureMin: 0),
          _lift(_p(30, 24, 70, 0), pressureMin: 0),
        ],
        driven: true,
        strokes: 2,
        afterEach: () => lines.add(InputInspector.notes['press']),
      );
      // The poll timer must die before the binding's pending-timer check.
      wintab.debugReset();

      expect(lines.where((line) => line != null).toSet().toList(), [
        'press ldg=0 own=3 new=1 os=0 one=0 sw=1 drv/os ×2.00 (1.50–3.33)',
        'press ldg=0 own=0 new=2 os=0 one=0 sw=0 drv/os ×2.00 (2.00–2.00)',
      ]);
    },
  );

  // 🗣️F-611 (유저 2026-11-18, iPhone, a finger): the opening of every line
  // straight — what the phone handed in, said on the phone.
  testWidgets(
    "the inspector's path line says how many points a line took, how soon "
    'the first move came and the longest wait between two — in its opening '
    'and in all of it',
    (tester) async {
      InputInspector.visible.value = true;
      addTearDown(InputInspector.reset);
      final lines = <String?>[];
      await _line(
        tester,
        _pressureAndSpeed,
        [
          _press(_p(4, 8, 0, 0.5), seenAt: _ms(0)),
          _merged([_p(20, 10, 8, 0.6), _p(36, 16, 110, 0.7)]),
          _merged([_p(48, 14, 300, 0.6)]),
          _lift(_p(60, 12, 310, 0)),
          // The next line on the same canvas is counted alone.
          _press(_p(4, 24, 400, 0.5), seenAt: _ms(400)),
          _merged([_p(30, 24, 408, 0.5)]),
          _lift(_p(30, 24, 416, 0)),
        ],
        strokes: 2,
        afterEach: () => lines.add(InputInspector.notes['path']),
      );

      expect(lines.where((line) => line != null).toSet().toList(), [
        'path pts=4 1st=8ms open=102ms max=190ms',
        'path pts=2 1st=8ms open=8ms max=8ms',
      ]);
    },
  );
}

final BrushEditCanvasInputSettings _pressureAndSpeed =
    BrushEditCanvasInputSettings(
      correction: BrushCorrection.none,
      size: 40,
      curves: {
        (BrushPressureTarget.size, BrushInputSource.pressure):
            BrushPressureCurve.identity(),
        (BrushPressureTarget.size, BrushInputSource.speed):
            BrushPressureCurve.identity(),
      },
    );

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// A point on the canvas, when, and its pressure (0..1).
typedef _Point = ({Offset at, Duration time, double force});

_Point _p(double x, double y, int ms, double force) =>
    (at: Offset(x, y), time: _ms(ms), force: force);

/// One pointer event of a contact, and the points the OS saw of its
/// message — none where the event is its own one point.
typedef _Event = ({
  PointerEvent Function(WidgetTester tester) made,
  List<_Point>? points,
});

/// A press, a move the OS merged three points into and the lift, each
/// point the OS saw at a pressure of its own, handed over as [kind]: a
/// stylus measuring 0..1 on its events, a mouse measuring none.
List<_Event> _stroke(PointerDeviceKind kind) {
  final least = kind == PointerDeviceKind.mouse ? 1.0 : 0.0;
  return [
    _press(_p(4, 8, 0, 0.5), seenAt: _ms(0), kind: kind, pressureMin: least),
    _merged(
      [_p(20, 10, 8, 0.2), _p(36, 16, 13, 0.3), _p(60, 12, 30, 0.8)],
      kind: kind,
      pressureMin: least,
    ),
    _lift(_p(60, 12, 34, 0), kind: kind, pressureMin: least),
  ];
}

/// The press at [point], handled then; the OS saw it at [seenAt]. A
/// stylus's own pressure reads from [pressureMin] to 1 — Flutter's minimum,
/// 1, is a range of nothing.
_Event _press(
  _Point point, {
  Duration? seenAt,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  double pressureMin = 1,
}) => (
  made: (tester) => PointerDownEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, point.at),
    timeStamp: point.time,
    pressure: point.force,
    pressureMin: pressureMin,
    pressureMax: 1,
  ),
  points: seenAt == null
      ? null
      : [(at: point.at, time: seenAt, force: point.force)],
);

/// A move the OS merged [points] into — the newest is the message's own.
_Event _merged(
  List<_Point> points, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  double pressureMin = 1,
}) => (
  made: (tester) => PointerMoveEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, points.last.at),
    timeStamp: points.last.time,
    pressure: points.last.force,
    pressureMin: pressureMin,
    pressureMax: 1,
  ),
  points: points.length == 1 ? null : points,
);

/// The lift at [point], with the moves the OS merged into it [before].
_Event _lift(
  _Point point, {
  List<_Point> before = const [],
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  double pressureMin = 1,
}) => (
  made: (tester) => PointerUpEvent(
    pointer: 1,
    kind: kind,
    position: canvasGlobalOffset(tester, point.at),
    timeStamp: point.time,
    pressureMin: pressureMin,
    pressureMax: 1,
  ),
  points: before.isEmpty ? null : [...before, point],
);

/// What a landed dab is — where, how big, how opaque, and every input it
/// was drawn with — in the order it was laid.
List<Object?> _look(List<BrushDab> dabs) => [
  for (final dab in dabs)
    (dab.center.x, dab.center.y, dab.size, dab.opacity, dab.pressure, dab.speed),
];

/// What the OS reads of a pen whose driver says another pressure.
const double _osAside = 0.15;

/// Draws [events] on a fresh canvas — each event paired, as the door pairs
/// a datum, with the points the OS saw of its message — and returns the
/// line's dabs. Each point's pressure is the OS's own, or, [driven], the
/// tablet driver's, the OS reading a pen at [_osAside] and a mouse at none.
/// [events] may be [strokes] contacts on the one canvas — the last one's
/// dabs are returned —, and [afterEach] is told after each event is in.
Future<List<BrushDab>> _line(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<_Event> events, {
  bool driven = false,
  int strokes = 1,
  void Function()? afterEach,
}) async {
  final results = <List<BrushDab>>[];
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: 160, height: 32),
    tileSize: 128,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveBrushEditCanvasView(
            key: UniqueKey(),
            celNow: () => cel,
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: () => settings,
            onSourceStrokeCommitted: (data) => results.add(data.sourceDabs),
          ),
        ),
      ),
    ),
  );
  for (final event in events) {
    final made = event.made(tester);
    final points = event.points;
    if (points != null) {
      pairWithThePointsTheOsSaw(made, [
        for (final point in points)
          seenAt(
            canvasGlobalOffset(tester, point.at),
            time: point.time,
            pressure: !driven
                ? point.force
                : made.kind == PointerDeviceKind.mouse
                ? null
                : _osAside,
            driven: driven
                ? (pressure: point.force, lean: null, twist: null)
                : null,
          ),
      ]);
    }
    tester.binding.handlePointerEvent(made);
    await tester.pump();
    afterEach?.call();
  }
  expect(results, hasLength(strokes));
  return results.last;
}
