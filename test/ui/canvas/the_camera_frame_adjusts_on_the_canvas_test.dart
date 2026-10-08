import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/camera_adjust_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_target_pill.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🗣️I-80 (유저 2026-10-06): 「캔버스에서 카메라 사이즈 보면서 변경」 — the
/// camera's frame in the box a layer's transform wears, scaled about its
/// middle (I-80-Q1: 「가운데가 그대로 — 크기만 바뀐다」; 「카메라 사이즈
/// 변경은 변형도구 규칙 그대로」), and under it the canvas's pill with the
/// size, the ratio it keeps (I-80-Q2), 확정 and 취소.
void main() {
  const canvas = CanvasSize(width: 800, height: 600);
  const frame = CanvasSize(width: 400, height: 200);
  late CanvasAdjust adjust;
  late int landed;

  setUp(() {
    adjust = CanvasAdjust()..begin(const CameraSizeDraft(size: frame));
    landed = 0;
  });
  tearDown(() {
    adjust.dispose();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// The layer over a view where a canvas pixel is a screen pixel, the
  /// canvas's top left at the layer's, the camera standing at the canvas's
  /// middle — its frame from (200, 200) to (600, 400) unturned.
  Future<Offset> pumpLayer(
    WidgetTester tester, {
    double rotationDegrees = 0,
  }) async {
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
              child: CameraAdjustLayer(
                adjust: adjust,
                pose: CameraPose(
                  center: CanvasPoint(x: 400, y: 300),
                  rotationDegrees: rotationDegrees,
                ),
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
    return tester.getTopLeft(find.byType(CameraAdjustLayer));
  }

  String sizeShown(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('camera-adjust-size')))
      .data!;

  String ratioShown(WidgetTester tester) => tester
      .widget<PanelFlyoutButton>(
        find.byKey(const ValueKey<String>('camera-adjust-ratio')),
      )
      .label;

  CanvasSize kept() => (adjust.draft! as CameraSizeDraft).size;

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

  Future<void> lock(WidgetTester tester, CameraRatioLock to) async {
    await tester.tap(find.byKey(const ValueKey<String>('camera-adjust-ratio')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('camera-adjust-ratio-${to.name}')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the pill stands under the middle of the frame and says its '
      'size and the ratio it keeps', (tester) async {
    final origin = await pumpLayer(tester);
    final pill = tester.getRect(
      find.byKey(const ValueKey<String>('camera-adjust-pill')),
    );
    expect(pill.center.dx - origin.dx, closeTo(400, 0.01));
    expect(pill.top - origin.dy, closeTo(400 + targetPillGap, 0.01));
    expect(sizeShown(tester), '400 × 200');
    expect(ratioShown(tester), CameraAdjustLayer.labelOf(CameraRatioLock.free));
  });

  testWidgets('🚨the right edge dragged moves the left one as far the other '
      'way — the middle stays, the size alone changes', (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(600, 300), const Offset(50, 30));

    expect(kept(), const CanvasSize(width: 500, height: 200));
    expect(sizeShown(tester), '500 × 200');
    final pill = tester.getRect(
      find.byKey(const ValueKey<String>('camera-adjust-pill')),
    );
    expect(
      pill.center.dx - origin.dx,
      closeTo(400, 0.01),
      reason: 'the frame grew about its middle',
    );
  });

  testWidgets('a corner pulled out scales both sides by one factor', (
    tester,
  ) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(200, 200), const Offset(-40, -20));

    expect(kept(), const CanvasSize(width: 480, height: 240));
  });

  testWidgets('🚨mid-drag the frame and its pill stand where the hand has '
      'them, and what the grab began from is kept until it lets go', (
    tester,
  ) async {
    final origin = await pumpLayer(tester);
    final gesture = await tester.startGesture(origin + const Offset(200, 200));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, -10));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, -10));
    await tester.pump();

    expect(sizeShown(tester), '480 × 240');
    expect(kept(), frame, reason: 'not let go yet');
    final pill = tester.getRect(
      find.byKey(const ValueKey<String>('camera-adjust-pill')),
    );
    expect(
      pill.top - origin.dy,
      closeTo(420 + targetPillGap, 0.01),
      reason: 'under the frame the hand has: 240 tall about 300',
    );

    await gesture.up();
    await tester.pump();
    expect(kept(), const CanvasSize(width: 480, height: 240));
  });

  testWidgets('🚨a turned camera\'s edges are its own: the edge that is its '
      'right, wherever the canvas shows it, moves its width', (tester) async {
    // Turned a quarter clockwise, the camera's right edge lies under the
    // middle on the canvas: (400, 500).
    final origin = await pumpLayer(tester, rotationDegrees: 90);
    await drag(tester, origin + const Offset(400, 500), const Offset(0, 50));

    expect(kept(), const CanvasSize(width: 500, height: 200));
  });

  // 🗣️I-80-Q2 (유저 2026-10-08): 「알약에 비율 버튼 — 리스트 팝오버(자유 ·
  // 지금 비율 · 16:9 · 21:9 · 4:3 · 1:1)」.
  testWidgets('🚨a ratio picked from the pill brings the frame to it, and an '
      'edge dragged then carries the other side along', (tester) async {
    final origin = await pumpLayer(tester);
    await lock(tester, CameraRatioLock.wide);

    expect(kept(), const CanvasSize(width: 400, height: 225));
    expect(ratioShown(tester), '16:9');

    // The right edge's middle stands where it stood: the width was kept.
    await drag(tester, origin + const Offset(600, 300), const Offset(50, 0));
    expect(kept(), const CanvasSize(width: 500, height: 281));
  });

  testWidgets('the list offers every ratio, the one kept marked', (
    tester,
  ) async {
    await pumpLayer(tester);
    final rows = tester
        .widget<PanelFlyoutButton>(
          find.byKey(const ValueKey<String>('camera-adjust-ratio')),
        )
        .entriesBuilder()
        .whereType<PanelFlyoutItem>();

    expect(
      [for (final row in rows) row.label],
      [
        for (final lock in CameraRatioLock.values)
          CameraAdjustLayer.labelOf(lock),
      ],
    );
    expect(
      [
        for (final row in rows)
          if (row.selected) row.keyValue,
      ],
      ['camera-adjust-ratio-free'],
    );
  });

  testWidgets('a press inside the frame away from the handles is not the '
      'box\'s', (tester) async {
    final origin = await pumpLayer(tester);
    await drag(tester, origin + const Offset(400, 300), const Offset(60, 40));

    expect(kept(), frame);
    expect(sizeShown(tester), '400 × 200');
  });

  testWidgets('✓ lands the size; ✕ closes the adjust for nothing', (
    tester,
  ) async {
    await pumpLayer(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('camera-adjust-confirm')),
    );
    await tester.pump();
    expect(landed, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('camera-adjust-cancel')),
    );
    await tester.pump();
    expect(adjust.isOpen, isFalse);
    expect(landed, 1, reason: '✕ lands nothing');
  });
}
