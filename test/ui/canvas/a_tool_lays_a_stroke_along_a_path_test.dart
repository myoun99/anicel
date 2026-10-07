import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// I-69 (유저 2026-10-04): 「브러시 상태를 그대로 사용해서 도형그림. 샤프
/// 브러시 그대로 사각형 그린다던가 … 그냥 진짜 브러시랑 똑같이
/// 래스터라이즈되있는 도형」.
///
/// 🚨★★★A SHAPE IS THE STROKE, NOT A STROKE LIKE IT. The drawing view lays
/// a path handed to it through the stroke's own arming, advance and landing
/// (`_BrushEditPathStroke`), so the one thing worth pinning is that it is
/// the same stroke a hand would draw through the same points — and the few
/// things a tool does not bring that a hand does.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);

  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);
  final corner = [p(10, 10), p(100, 10), p(100, 50)];

  testWidgets('a path is laid as the stroke a hand would draw through the '
      'same points with nothing to read from a pen', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    expect(host.stroker!(corner), isTrue);
    await tester.pump();
    await _byMouse(tester, const [
      Offset(10, 10),
      Offset(100, 10),
      Offset(100, 50),
    ]);

    expect(host.committed, hasLength(2), reason: 'one stroke each');
    final laid = host.committed.first;
    expect(laid.length, greaterThan(20), reason: 'a line of dabs, not a dot');
    expect(laid.first.center, p(10, 10), reason: 'it begins under its start');
    expect(_look(laid), _look(host.committed.last));
  });

  testWidgets('the host hears the stroke begin and end, inside the call', (
    tester,
  ) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    host.stroker!(corner);

    expect(host.active, [true, false]);
    expect(host.committed, hasLength(1), reason: 'landed before it answers');
  });

  testWidgets('⛔nothing steadies it: a stabilised brush lays the path where '
      'it was told, to its very end', (tester) async {
    final plain = _Host();
    await _pump(tester, plain, _brush());
    plain.stroker!(corner);

    final steadied = _Host();
    await _pump(tester, steadied, _brush(stabilizer: 40));
    steadied.stroker!(corner);

    expect(_look(steadied.committed.single), _look(plain.committed.single));
  });

  testWidgets('its first dab is turned the way the stroke sets off — a tool '
      'knows where it is going before it starts', (tester) async {
    final host = _Host();
    await _pump(
      tester,
      host,
      _brush(rotation: BrushTipRotationMode.direction),
    );

    // Straight down.
    host.stroker!([p(40, 8), p(40, 56)]);

    final down = host.committed.single;
    expect(down.length, greaterThan(4));
    // The stamp a dab lands with is its tip already turned (the tip-stamp
    // cache), so two dabs turned alike wear the very same one.
    expect(
      down.first.tipMask,
      same(down.last.tipMask),
      reason: 'one straight line, one direction from its first dab on',
    );

    // Fixture: the direction is what turns it.
    host.stroker!([p(8, 30), p(150, 30)]);
    final across = host.committed.last;
    expect(across.first.tipMask, same(across.last.tipMask));
    expect(down.first.tipMask, isNot(same(across.first.tipMask)));
  });

  group('where there is nothing to draw on', () {
    testWidgets('it asks for the cel as a press does, and draws once the cel '
        'is there', (tester) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: true);

      expect(host.stroker!(corner), isTrue, reason: 'it will be drawn');
      expect(host.askedForACel, 1);
      expect(host.committed, isEmpty, reason: 'not before the cel');

      // The frame that brings the cel.
      await _pump(tester, host, _brush(), editable: true, celAnswer: true);
      await tester.pump();

      expect(host.committed, hasLength(1));
      expect(host.committed.single.first.center, p(10, 10));
      expect(host.askedForACel, 1, reason: 'asked once');
    });

    testWidgets('⛔refused a cel, it draws nothing — then or later', (
      tester,
    ) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: false);

      expect(host.stroker!(corner), isFalse);
      expect(host.askedForACel, 1);

      await _pump(tester, host, _brush(), editable: true, celAnswer: false);
      await tester.pump();
      expect(host.committed, isEmpty);
      expect(host.active, isEmpty, reason: 'no stroke ever began');
    });

    testWidgets('⛔a cel that never came is not drawn on when another does '
        'frames later', (tester) async {
      final host = _Host();
      await _pump(tester, host, _brush(), editable: false, celAnswer: true);
      expect(host.stroker!(corner), isTrue);

      // The next frame, and still nothing to draw on.
      await tester.pump();
      await tester.pump();
      await _pump(tester, host, _brush(), editable: true, celAnswer: true);
      await tester.pump();

      expect(host.committed, isEmpty);
    });
  });

  testWidgets('⛔a row that takes no strokes shows no line', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush(), rowAcceptsStrokes: false);

    expect(host.stroker!(corner), isFalse);
    expect(host.committed, isEmpty);
    expect(host.active, isEmpty);
  });

  testWidgets('a path of one point is no stroke', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());

    expect(host.stroker!([p(10, 10)]), isFalse);
    expect(host.committed, isEmpty);
  });

  testWidgets('the stroker goes when the view does', (tester) async {
    final host = _Host();
    await _pump(tester, host, _brush());
    expect(host.stroker, isNotNull);

    await tester.pumpWidget(const SizedBox());

    expect(host.stroker, isNull);
  });
}

class _Host {
  PathStroker? stroker;
  final committed = <List<BrushDab>>[];
  final active = <bool>[];
  int askedForACel = 0;
}

final _cel = BitmapSurface(
  canvasSize: const CanvasSize(width: 160, height: 64),
  tileSize: 16,
);

BrushEditCanvasInputSettings _brush({
  double stabilizer = 0,
  BrushTipRotationMode rotation = BrushTipRotationMode.fixed,
}) => BrushToolState.defaults
    .copyWith(
      size: 6,
      roundness: 0.5,
      stabilizerStrength: stabilizer,
      rotationMode: rotation,
    )
    .toInputSettings();

Future<void> _pump(
  WidgetTester tester,
  _Host host,
  BrushEditCanvasInputSettings settings, {
  bool editable = true,
  bool rowAcceptsStrokes = true,
  bool? celAnswer,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InteractiveBrushEditCanvasView(
          // A view of its own for each host: the stroker is handed over
          // when the view is made.
          key: ObjectKey(host),
          celNow: () => _cel,
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          inputSettings: () => settings,
          editable: editable,
          rowAcceptsStrokes: rowAcceptsStrokes,
          onPressNeedsCel: celAnswer == null
              ? null
              : () {
                  host.askedForACel += 1;
                  return celAnswer;
                },
          onActiveStrokeChanged: host.active.add,
          onPathStrokerChanged: (stroker) => host.stroker = stroker,
          onSourceStrokeCommitted: (data) =>
              host.committed.add(data.sourceDabs),
        ),
      ),
    ),
  ),
);

/// The same points by a hand that reads nothing from a pen: a mouse, whose
/// pressure is full the whole way.
Future<void> _byMouse(WidgetTester tester, List<Offset> through) async {
  final gesture = await tester.startGesture(
    canvasGlobalOffset(tester, through.first),
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryButton,
  );
  await tester.pump();
  for (final at in through.skip(1)) {
    await gesture.moveTo(canvasGlobalOffset(tester, at));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// What a dab looks like on the cel — where, how big, how strong, and
/// which way it is turned. ⚠️Not its speed or its lean: those are a pen's
/// readings, and a tool has none.
List<Object?> _look(List<BrushDab> dabs) => [
  for (final dab in dabs)
    (
      dab.center.x,
      dab.center.y,
      dab.size,
      dab.opacity,
      dab.flow,
      dab.pressure,
      dab.sequence,
    ),
];
