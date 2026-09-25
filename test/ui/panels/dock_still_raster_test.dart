import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Every dock is one region drawn from a still image while it stays the
/// same (유저 2026-09-25, raster-cache-when-still-Q1) — except a region
/// showing the canvas, the one surface whose pixels may never move
/// (「결과 절대 바뀌면 안되는건 캔버스뿐임」).
///
/// 🚨Pinned on the real workspace because the first version got it wrong
/// in exactly the place a unit test cannot see: the canvas is a TAB, of the
/// floor dock, so wrapping "every dock" wrapped the canvas too, and the
/// first real-app run found a 12 MB image of it.
void main() {
  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    // Where the still images run, the bakes paint through (Impeller).
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  testWidgets('the dock showing the canvas never takes an image, the others '
      'do', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    // Frames with nothing changing — what a stroke gives every region
    // beside the canvas.
    for (var i = 0; i < 12; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    final regions = <String, RenderStillRaster>{
      for (final region in StillRaster.census.where((r) => r.attached))
        region.debugLabel: region,
    };
    final floor = regions['dock:${EditorWorkspace.centerGroupId}'];
    expect(floor, isNotNull, reason: 'the floor is a dock like any other');
    expect(
      floor!.standDown,
      StillStandDown.optedOut,
      reason: 'the floor shows the canvas, and the canvas says no',
    );
    expect(floor.debugCaptureCount, 0);
    expect(
      regions.values.where((region) => region.debugDrawnFromImage),
      isNotEmpty,
      reason:
          'no other dock took its image either, so the floor standing down '
          'proves nothing',
    );
  });
}
