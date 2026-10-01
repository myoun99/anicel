import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🗣️H45 (유저 2026-09-28, iPad 1065): 「펜업시 마지막 진행방향에 선이 하나
/// 생겨. 정밀하게 멈추고 뗀건데도」 → H45-Q1 「따라잡지 않는다 — 선은 붓이
/// 있던 자리에서 끝난다」.
///
/// The stabiliser's brush trails the pen by the rope, and a pen held still
/// leaves it there. Pen-up used to close that gap with one straight
/// segment, which is the tail the user saw.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  // Straight right, then held still where it stopped — the hand the user
  // described.
  const hand = [
    Offset(10, 20),
    Offset(40, 20),
    Offset(70, 20),
    Offset(100, 20),
    Offset(130, 20),
    Offset(160, 20),
    Offset(160, 20),
  ];

  testWidgets('a stroke that stops and lifts ends where the brush is — a '
      'rope behind the pen, with no segment laid out to it', (tester) async {
    final dabs = await _stroke(tester, stabilizer: 30, hand);

    // A 30px rope at 100%: the brush stays 30px behind the pen, so the pen
    // at 160 has pulled it to 130 — and holding still pulls it no further.
    final reach = dabs.map((dab) => dab.center.x).reduce(_max);
    expect(reach, closeTo(130, 1), reason: 'the line reaches the brush');
    expect(
      dabs.where((dab) => dab.center.x > 131),
      isEmpty,
      reason: 'nothing is laid between the brush and the pen at the lift',
    );
  });

  testWidgets('the same hand with no stabiliser reaches the pen — the '
      'rope, not the stroke, is what stops short', (tester) async {
    final dabs = await _stroke(tester, stabilizer: 0, hand);

    expect(dabs.map((dab) => dab.center.x).reduce(_max), closeTo(160, 1));
  });
}

double _max(double a, double b) => a > b ? a : b;

/// Draws [hand] with a stylus on a fresh canvas at 100% and returns the
/// dabs the stroke committed.
Future<List<BrushDab>> _stroke(
  WidgetTester tester,
  List<Offset> hand, {
  required double stabilizer,
}) async {
  final committed = <List<BrushDab>>[];
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
            celNow: () => cel,
            layerId: const LayerId('layer-a'),
            frameId: const FrameId('frame-a'),
            inputSettings: () => BrushEditCanvasInputSettings(
              size: 4,
              stabilizerStrength: stabilizer,
            ),
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
  return committed.single;
}
