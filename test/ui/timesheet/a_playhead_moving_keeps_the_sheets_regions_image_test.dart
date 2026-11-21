import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// 🔬Card a-playhead-move-lets-the-timesheets-dock-image-go (11-21): with
/// the timesheet open beside the timeline, every frame picked on the ruler
/// drew the sheet's dock live, and every rest took its image again — 14
/// picks, 14 images, none drawn twice (test VM, the engine open); the real
/// app the same (검증 11-21 21:26, 再描画を表示).
///
/// A dock region is drawn from one image while it stays the same
/// ([StillRaster]). The playhead's row was painted alone, on a boundary of
/// its own — and to a still region a boundary painted again is the region
/// changed. The row is a tick: drawn live between what the region holds,
/// as the tool cursors over the same sheet are (F-428,
/// `a_moving_tool_cursor_keeps_its_regions_image_test.dart`).
///
/// One painter draws the row for every way the playhead moves — a frame
/// picked, a seek committed, a gap parked on, a frame played — so the
/// frame picked here stands for the four.
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

  testWidgets('🎯the playhead moving down a sheet keeps the region drawn '
      'from its image, and takes no image again', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
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
    // The sheet's own capsules are regions too: this is the one around it.
    final region = tester
        .renderObjectList<RenderStillRaster>(find.byType(StillRaster))
        .first;
    expect(region.debugDrawnFromImage, isTrue, reason: 'still, first');

    int? rowLit() {
      final overlay = tester.widget<CustomPaint>(
        find.byKey(const ValueKey<String>('timesheet-playhead-overlay')),
      );
      return (overlay.painter! as TimesheetPlayheadPainter)
          .resolvePlayheadFrame();
    }

    Future<void> pick(int frame) async {
      session.selectFrameIndex(frame);
      await tester.pump();
    }

    // Its first move is a change of the region's; moving alone after it,
    // the row is drawn live and the rest from the region's image.
    for (var frame = 1; frame <= 3; frame += 1) {
      await pick(frame);
    }
    final taken = region.debugCaptureCount;
    final lit = <int?>{rowLit()};
    for (var frame = 4; frame <= 12; frame += 1) {
      await pick(frame);
      lit.add(rowLit());
      expect(region.debugDrawnFromImage, isTrue, reason: 'frame $frame');
    }
    expect(lit, hasLength(10), reason: 'the row lit is what moved');
    expect(region.debugCaptureCount, taken);
  });
}
