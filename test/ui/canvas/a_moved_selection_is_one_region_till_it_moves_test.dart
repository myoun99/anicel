import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

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
    final first = antsOnScreen(tester).committedRegion;
    expect(first, isNotNull, reason: 'the premise: a selection');
    expect(
      first,
      isNot(same(transformToolSquare)),
      reason: 'the premise: a session moved it',
    );
    // Moved again, by the box alone: a region anew.
    await dragOnTransformLayer(
      tester,
      const Offset(347, 241),
      const Offset(355, 249),
    );
    final painter = antsOnScreen(tester);
    final moved = painter.committedRegion;
    expect(moved, isNot(same(first)));

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

  // The same of the 퍼스 quad and the mesh, whose points move the selection
  // with no move of the box: each step of theirs is a region anew.
  for (final (mode, from, to, further) in [
    (
      TransformMode.perspective,
      const Offset(360, 260),
      const Offset(366, 262),
      const Offset(372, 266),
    ),
    (
      TransformMode.mesh,
      const Offset(320, 220),
      const Offset(332, 215),
      const Offset(340, 210),
    ),
  ]) {
    testWidgets('${mode.name}: each step of a point is a region anew', (
      tester,
    ) async {
      await pumpTransformTool(
        tester,
        options: TransformToolOptions(mode: mode),
      );
      await dragOnTransformLayer(tester, from, to);
      final stepped = antsOnScreen(tester).committedRegion;
      expect(
        stepped,
        isNot(same(transformToolSquare)),
        reason: 'the premise: a session moved it',
      );

      await dragOnTransformLayer(tester, to, further);

      expect(antsOnScreen(tester).committedRegion, isNot(same(stepped)));
    });
  }
}
