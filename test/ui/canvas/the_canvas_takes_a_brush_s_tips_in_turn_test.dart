import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';

import '../brush_canvas_test_helpers.dart';

/// F-176-Q3 on the canvas itself: a stroke's dabs take the brush's tips in
/// turn from the press on — by hand, and along a tool's path, which is the
/// same stroke (I-69) — and every stroke starts the turns over.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);

  BrushTipMask tip(String id, int shade) => BrushTipMask(
    id: id,
    size: 4,
    alpha: Uint8List.fromList(List<int>.filled(16, shade)),
  );

  final abc = [tip('a', 255), tip('b', 200), tip('c', 150)];

  BrushEditCanvasInputSettings brushOf(BrushTipOrder order) =>
      BrushToolState.defaults
          .copyWith(size: 6, tips: abc, tipOrder: order)
          .toInputSettings();

  String tipsOf(List<BrushDab> laid) =>
      [for (final dab in laid) dab.tipMask?.id ?? '?'].join();

  /// What [count] dabs taking a, b and c in turn read as.
  String inTurn(int count) => [
    for (var index = 0; index < count; index += 1) 'abc'[index % 3],
  ].join();

  testWidgets('a hand\'s strokes take the tips in turn, each from the first', (
    tester,
  ) async {
    final landed = <BrushStrokeCommitData>[];
    await _pump(tester, landed, brushOf(BrushTipOrder.repeat));

    for (var stroke = 0; stroke < 2; stroke += 1) {
      await _byMouse(tester, const [Offset(10, 20), Offset(120, 20)]);
    }

    expect(landed, hasLength(2));
    for (final stroke in landed) {
      final laid = tipsOf(stroke.sourceDabs);
      expect(laid.length, greaterThan(6), reason: 'a line, not a dot');
      expect(laid, inTurn(laid.length));
    }
  });

  testWidgets('a tool\'s path takes them the same way, and a lap that ran '
      'out lays nothing more', (tester) async {
    final landed = <BrushStrokeCommitData>[];
    final shapes = ViewHand<ShapeShow>();
    await _pump(
      tester,
      landed,
      brushOf(BrushTipOrder.oneLap),
      shapes: shapes,
    );

    shapes.now!.landStroke([
      CanvasPoint(x: 10, y: 20),
      CanvasPoint(x: 120, y: 20),
    ]);

    expect(tipsOf(landed.single.sourceDabs), 'abc');
  });

  testWidgets("ランダム throws the stroke's own dice: one path laid twice "
      'takes the same tips', (tester) async {
    final landed = <BrushStrokeCommitData>[];
    final shapes = ViewHand<ShapeShow>();
    await _pump(
      tester,
      landed,
      brushOf(BrushTipOrder.random),
      shapes: shapes,
    );

    for (var stroke = 0; stroke < 2; stroke += 1) {
      shapes.now!.landStroke([
        CanvasPoint(x: 10, y: 20),
        CanvasPoint(x: 120, y: 20),
      ]);
      await tester.pump();
    }

    final [first, second] = [
      for (final stroke in landed) tipsOf(stroke.sourceDabs),
    ];
    expect(first.length, greaterThan(6), reason: 'a line, not a dot');
    expect(first, isNot(inTurn(first.length)), reason: 'thrown, not in turn');
    expect(second, first);
  });
}

final _cel = BitmapSurface(
  canvasSize: const CanvasSize(width: 160, height: 64),
  tileSize: 16,
);

Future<void> _pump(
  WidgetTester tester,
  List<BrushStrokeCommitData> landed,
  BrushEditCanvasInputSettings settings, {
  ViewHand<ShapeShow>? shapes,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: InteractiveBrushEditCanvasView(
          celNow: () => _cel,
          layerId: const LayerId('layer-a'),
          frameId: const FrameId('frame-a'),
          inputSettings: () => settings,
          editable: true,
          rowAcceptsStrokes: true,
          shapeShow: shapes,
          onSourceStrokeCommitted: landed.add,
        ),
      ),
    ),
  ),
);

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
