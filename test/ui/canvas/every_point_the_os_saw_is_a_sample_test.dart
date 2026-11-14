import 'dart:ui' as ui show PointerChange, PointerData;

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
import 'package:anicel/src/services/input/pen_path.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

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

/// The press at [point], handled then; the OS saw it at [seenAt].
_Event _press(_Point point, {Duration? seenAt}) => (
  made: (tester) => PointerDownEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: canvasGlobalOffset(tester, point.at),
    timeStamp: point.time,
    pressure: point.force,
    pressureMax: 1,
  ),
  points: seenAt == null
      ? null
      : [(at: point.at, time: seenAt, force: point.force)],
);

/// A move the OS merged [points] into — the newest is the message's own.
_Event _merged(List<_Point> points) => (
  made: (tester) => PointerMoveEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: canvasGlobalOffset(tester, points.last.at),
    timeStamp: points.last.time,
    pressure: points.last.force,
    pressureMax: 1,
  ),
  points: points.length == 1 ? null : points,
);

/// The lift at [point], with the moves the OS merged into it [before].
_Event _lift(_Point point, {List<_Point> before = const []}) => (
  made: (tester) => PointerUpEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: canvasGlobalOffset(tester, point.at),
    timeStamp: point.time,
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

/// Draws [events] on a fresh canvas — each event paired, as the door pairs
/// a datum, with the points the OS saw of its message — and returns the
/// line's dabs.
Future<List<BrushDab>> _line(
  WidgetTester tester,
  BrushEditCanvasInputSettings settings,
  List<_Event> events,
) async {
  final results = <List<BrushDab>>[];
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: 160, height: 32),
    tileSize: 16,
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
      QaPenPoints.debugTake = (_, _) => [
        for (final point in points)
          (
            x: canvasGlobalOffset(tester, point.at).dx,
            y: canvasGlobalOffset(tester, point.at).dy,
            at: point.time,
            pressure: point.force,
            tilt: null,
            orientation: null,
          ),
      ];
      PenPath.arrived(
        made,
        ui.PointerData(
          change: switch (made) {
            PointerDownEvent() => ui.PointerChange.down,
            PointerUpEvent() => ui.PointerChange.up,
            _ => ui.PointerChange.move,
          },
          physicalX: made.position.dx,
          physicalY: made.position.dy,
        ),
        1,
      );
      QaPenPoints.debugTake = null;
    }
    tester.binding.handlePointerEvent(made);
    await tester.pump();
  }
  expect(results, hasLength(1));
  return results.single;
}
