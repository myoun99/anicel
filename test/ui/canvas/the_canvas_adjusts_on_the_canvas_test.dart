import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/canvas/canvas_adjust_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_target_pill.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';

/// 🗣️I-79 (유저 2026-10-06): 「캔버스에서 직접 변 끌면서 조정하는 기능」 —
/// the canvas's edges in the box every box on the canvas wears, the edge
/// across from the one dragged staying where it is (I-79-Q2), and under it
/// the canvas's pill with the size, 확정 and 취소 (I-79-Q1: 「아래쪽
/// 가운데」).
void main() {
  const canvas = CanvasSize(width: 400, height: 300);
  late CanvasAdjust adjust;
  late int landed;

  setUp(() {
    adjust = CanvasAdjust()..begin(const CutId('c'), canvas);
    landed = 0;
  });
  tearDown(() {
    adjust.dispose();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// The layer over a view where a canvas pixel is a screen pixel, the
  /// canvas's top left at the layer's.
  Future<Offset> pumpLayer(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 600,
              child: CanvasAdjustLayer(
                adjust: adjust,
                viewport: CanvasViewport(),
                canvasSize: canvas,
                onLand: () => landed += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getTopLeft(find.byType(CanvasAdjustLayer));
  }

  String sizeShown(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('canvas-adjust-size')))
      .data!;

  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(by / 2);
    await tester.pump();
    await gesture.moveBy(by / 2);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('the pill stands under the middle of the canvas and says its '
      'size', (tester) async {
    final origin = await pumpLayer(tester);
    final pill = tester.getRect(
      find.byKey(const ValueKey<String>('canvas-adjust-pill')),
    );
    expect(pill.center.dx - origin.dx, closeTo(200, 0.01));
    expect(pill.top - origin.dy, closeTo(300 + targetPillGap, 0.01));
    expect(sizeShown(tester), '400 × 300');
  });

  testWidgets('🚨the right edge dragged moves alone — the left edge stays, '
      'and the pill reads the new size', (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(400, 150), const Offset(100, 30));

    expect(adjust.shown, const Rect.fromLTRB(0, 0, 500, 300));
    expect(sizeShown(tester), '500 × 300');
    expect(adjust.contentOffset, (dx: 0.0, dy: 0.0), reason: 'nothing moved');
  });

  testWidgets('🚨the top left corner pulled out moves the picture by as '
      'much, the opposite corner staying', (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin, const Offset(-50, -20));

    expect(adjust.shown, const Rect.fromLTRB(-50, -20, 400, 300));
    expect(adjust.size, const CanvasSize(width: 450, height: 320));
    expect(adjust.contentOffset, (dx: 50.0, dy: 20.0));
  });

  testWidgets('an edge never comes closer to the one across from it than '
      'one pixel', (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(400, 150), const Offset(-900, 0));

    expect(adjust.size, const CanvasSize(width: 1, height: 300));
  });

  testWidgets('a press on the canvas away from the handles is not the box\'s',
      (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(200, 150), const Offset(60, 40));

    expect(adjust.shown, const Rect.fromLTRB(0, 0, 400, 300));
  });

  testWidgets('✓ lands the edges; ✕ closes the adjust for nothing',
      (tester) async {
    await pumpLayer(tester);
    expect(adjust.land, isNotNull, reason: 'the layer up binds its landing');

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-adjust-confirm')),
    );
    await tester.pump();
    expect(landed, 1);

    await tester.tap(find.byKey(const ValueKey<String>('canvas-adjust-cancel')));
    await tester.pump();
    expect(adjust.isOpen, isFalse);
    expect(landed, 1, reason: '✕ lands nothing');
  });
}
