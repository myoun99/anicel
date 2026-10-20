import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🗣️F-418 (유저 2026-10-20): Clip Studio's 손떨림 보정. Q2 「과거 결정
/// 무시해도됨. 클튜는 100으로 하면 선을 떼면 바로 뗀 자리까지 선이 감」 · Q4
/// 「곧장 커서로 간다 — 꺾임을 가로지른다」.
///
/// ↩️This file pinned the opposite under H45 (2026-09-28): 「따라잡지
/// 않는다 — 선은 붓이 있던 자리에서 끝난다」, while the brush hung a rope
/// behind a pen held still.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    debugStrokeDabsLaid = null;
  });

  // Quick and straight right: a sample every 8 ms.
  const straight = [
    Offset(10, 20),
    Offset(40, 20),
    Offset(70, 20),
    Offset(100, 20),
    Offset(130, 20),
    Offset(160, 20),
  ];

  testWidgets('the line runs behind a quick pen; 0 steadies nothing', (
    tester,
  ) async {
    final steadied = await _draw(tester, straight, stabilization: 100);
    expect(_reach(steadied.beforeLift), lessThan(100));

    final plain = await _draw(tester, straight, stabilization: 0);
    expect(_reach(plain.beforeLift), closeTo(160, 1));
  });

  testWidgets('the pen lifts and the line goes to where it lifted '
      '(F-418-Q2)', (tester) async {
    final steadied = await _draw(tester, straight, stabilization: 100);
    expect(_reach(steadied.committed), closeTo(160, 1));
    expect(steadied.committed.last.center.y, closeTo(20, 1e-6));
  });

  testWidgets('it goes there straight, across the corner the pen turned '
      '(F-418-Q4)', (tester) async {
    const corner = [
      Offset(10, 8),
      Offset(50, 8),
      Offset(90, 8),
      Offset(90, 20),
      Offset(90, 32),
    ];
    bool insideTheCorner(BrushDab dab) =>
        dab.center.x < 85 && dab.center.y > 12;

    final steadied = await _draw(tester, corner, stabilization: 100);
    final end = steadied.committed.last.center;
    expect(end.x, closeTo(90, 1e-6));
    expect(end.y, closeTo(32, 1e-6));
    expect(steadied.committed.where(insideTheCorner), isNotEmpty);

    final plain = await _draw(tester, corner, stabilization: 0);
    expect(
      plain.committed.where(insideTheCorner),
      isEmpty,
      reason: 'the pen itself went round the corner',
    );
  });

  testWidgets('a resting pen is reached before it lifts — the line keeps '
      'going, on screen the frame it moves, and then asks for no more '
      'frames', (tester) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 16);
    addTearDown(overlay.dispose);
    final steadied = await _draw(
      tester,
      straight,
      stabilization: 30,
      overlay: overlay,
      rest: (laid) async {
        final reaches = <double>[];
        for (var frame = 0; frame < 60; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
          reaches.add(_reach(laid));
          expect(
            _reach(overlay.dabs),
            reaches.last,
            reason: 'frame $frame: shown the frame it was laid',
          );
        }
        expect(reaches.first, lessThan(150), reason: 'it was behind');
        expect(reaches.last, closeTo(160, 1), reason: 'it got there');
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
    expect(_reach(steadied.committed), closeTo(160, 1));
  });
}

double _reach(List<BrushDab> dabs) =>
    dabs.map((dab) => dab.center.x).reduce((a, b) => a > b ? a : b);

/// Draws [hand] with a stylus, a sample every 8 ms, on a fresh canvas at
/// 100%: the dabs laid before the lift and those the stroke committed.
/// [rest] runs between the last move and the lift with the dabs laid so far.
Future<({List<BrushDab> beforeLift, List<BrushDab> committed})> _draw(
  WidgetTester tester,
  List<Offset> hand, {
  required double stabilization,
  ActiveStrokeOverlayModel? overlay,
  Future<void> Function(List<BrushDab> laid)? rest,
}) async {
  final committed = <List<BrushDab>>[];
  final laid = debugStrokeDabsLaid = <BrushDab>[];
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: 200, height: 40),
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
            inputSettings: () => BrushEditCanvasInputSettings(
              size: 4,
              correction: BrushCorrection(stabilization: stabilization),
            ),
            overlayModel: overlay,
            onSourceStrokeCommitted: (data) => committed.add(data.sourceDabs),
          ),
        ),
      ),
    ),
  );

  var time = Duration.zero;
  PointerEvent at(Offset local, {required bool down}) {
    time += const Duration(milliseconds: 8);
    final position = canvasGlobalOffset(tester, local);
    return down
        ? PointerDownEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: position,
            timeStamp: time,
            pressure: 1,
          )
        : PointerMoveEvent(
            pointer: 1,
            kind: PointerDeviceKind.stylus,
            position: position,
            timeStamp: time,
            pressure: 1,
          );
  }

  tester.binding.handlePointerEvent(at(hand.first, down: true));
  await tester.pump();
  for (final point in hand.skip(1)) {
    tester.binding.handlePointerEvent(at(point, down: false));
    await tester.pump();
  }
  await rest?.call(laid);
  final beforeLift = List<BrushDab>.of(laid);
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: canvasGlobalOffset(tester, hand.last),
      timeStamp: time + const Duration(milliseconds: 8),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(committed, hasLength(1), reason: 'one stroke landed');
  return (beforeLift: beforeLift, committed: committed.single);
}
