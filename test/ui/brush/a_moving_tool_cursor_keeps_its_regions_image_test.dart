import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../brush_canvas_test_helpers.dart';

/// 🗣️F-428 (유저 2026-10-21): 「타임시트 용지패널의 헤더부분. 화수나 타이틀쪽
/// 부분, 펜으로 호버해서 움직이면 그쪽 칸 라인만 진해졌다 연해졌다 반복함」.
///
/// A dock region is drawn from one image while it stays the same
/// ([StillRaster]), and an image is not the paint it was taken of — the
/// sheet's head lines came out darker one way and lighter the other. A
/// cursor moving was a change of the region's, so every move drew the sheet
/// live and every pause took its image again. A cursor is a tick: drawn live
/// between the region's strata, the rest of the region kept in its image.
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

  testWidgets('🎯a tool cursor moving over a sheet keeps the region drawn '
      'from its image, and takes no image again', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final ink = TimesheetInkController(store: BrushFrameStore());
    addTearDown(ink.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StillRaster(
            debugLabel: 'test',
            child: TimesheetTabHost(
              session: session,
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              inkController: ink,
              brushToolState: brush,
              brushAllowed: true,
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    final region = tester.renderObject<RenderStillRaster>(
      find.byType(StillRaster),
    );
    expect(region.debugDrawnFromImage, isTrue, reason: 'still, first');

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final at = tester.getCenter(find.byType(TimesheetTabHost));
    await pen.addPointer(location: at);
    var step = 0.0;
    Future<void> move() async {
      step += 1;
      await pen.moveTo(at + Offset(step, 0));
      await tester.pump();
    }

    // Its first look is a change of the region's; moving alone after it,
    // the cursor is drawn live and the rest from the region's image.
    for (var i = 0; i < 12; i += 1) {
      await move();
    }
    expect(
      toolCursorShownAt(
        tester,
        find.byKey(const ValueKey<String>('brush-cursor-overlay')),
      ),
      isNotNull,
      reason: 'a cursor is what moves',
    );
    final taken = region.debugCaptureCount;
    for (var i = 0; i < 24; i += 1) {
      await move();
      expect(region.debugDrawnFromImage, isTrue, reason: 'move $i');
    }
    expect(region.debugCaptureCount, taken);
    await pen.removePointer();
  });
}
