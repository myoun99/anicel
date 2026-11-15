import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/transform_tool_on_canvas.dart';

/// 🗣️F-591 (유저 2026-11-15): 「변형중에 선택도구 개미행렬 형태가 벡터로
/// 돌아감. 비트맵이니까 픽셀 따라서 격자여야하는데」 — the ants of a selection
/// a session moves walk its pixels, as a settled one's do
/// (the_ants_are_black_and_on_the_grid_test.dart pins where the line lands).
/// The walk is done once a region, so the layer hands its ants the SAME
/// region for as long as nothing moves the selection: a build that moves
/// nothing — the wheel's zoom here — would walk it again for a region made
/// anew.
void main() {
  testWidgets('a moved selection is one region till it moves again', (
    tester,
  ) async {
    await pumpTransformTool(tester);
    await dragOnTransformLayer(
      tester,
      const Offset(330, 230),
      const Offset(347, 241),
    );
    final painter = antsOnScreen(tester);
    final moved = painter.committedRegion;
    expect(moved, isNotNull, reason: 'the premise: a selection');
    expect(
      moved,
      isNot(same(transformToolSquare)),
      reason: 'the premise: a session moved it',
    );

    final mouse = TestPointer(77, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byKey(transformToolLayerKey))),
    );
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pump();

    expect(
      antsOnScreen(tester),
      isNot(same(painter)),
      reason: 'the premise: the layer built again',
    );
    expect(antsOnScreen(tester).committedRegion, same(moved));
  });
}
