import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/live_sheet.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card the-left-tool-strip-rebakes-on-every-hover (11-22): a pointer
/// passing down the left tool strip took the strip's image again at every
/// button it crossed — 🔬eleven images in 1.1 s on the real app (the
/// timeline's probe run, 144 Hz).
///
/// A hover is a pointer's, as a tool cursor is (F-428): what it lights is
/// drawn live under what the strip holds, and the strip keeps its image.
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

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
  }

  testWidgets('🎯a pointer passing down the tool column takes no image of '
      'its strip, and the strip stays drawn from the one it has', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ToolsPanel.dockWidth,
              height: 800,
              child: StillRaster(
                debugLabel: 'strip',
                child: LiveSheet(
                  child: ToolsPanel(tool: CanvasTool.brush, onPress: (_) {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await frames(tester, 12);
    final region = tester.renderObject<RenderStillRaster>(
      find.byType(StillRaster),
    );
    expect(region.debugDrawnFromImage, isTrue, reason: 'still, first');

    final buttons = tester
        .renderObjectList<RenderRailGlyphFace>(find.byType(RailGlyphButton))
        .toList();
    expect(buttons.length, greaterThan(8), reason: 'the column of tools');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 450));
    addTearDown(mouse.removePointer);
    await frames(tester, 12);
    final taken = region.debugCaptureCount;

    // As the probe run went: about fourteen frames to a button.
    for (final (index, button) in buttons.indexed) {
      await mouse.moveTo(button.localToGlobal(button.size.center(Offset.zero)));
      await tester.pump();
      expect(
        button.debugState.hovered,
        isTrue,
        reason: 'button $index is under the pointer',
      );
      expect(
        button.debugLayerInk,
        isNotNull,
        reason: 'button $index shows its hover',
      );
      for (var frame = 0; frame < 14; frame += 1) {
        await frames(tester, 1);
        expect(
          region.debugDrawnFromImage,
          isTrue,
          reason: 'button $index, frame $frame',
        );
      }
    }
    await mouse.moveTo(const Offset(300, 450));
    await frames(tester, 14);
    expect(region.debugCaptureCount - taken, 0);
  });
}
