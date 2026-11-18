import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ContainerLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/panel_scrollbar.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// 🚨A DRAG KEEPS THE TIMELINE DOCK'S IMAGE THE DOCK'S SIZE (10-27,
/// F-244-drag-start ③). While a drag moves the cursor, the still dock
/// around the timeline is drawn from one image cut at the moving ticks
/// (`StillRaster`). 🔬On the Surface that image was 2.9–3.6 times the dock
/// (3.0–3.7M pixels for 1.02M), taken in 11–60 ms at every drag's start:
/// the frame area's edge, the dock's tab strip, the cut's end line and the
/// out-of-cut wash were each painted after a moving tick, in a picture the
/// size of the boundary around them, and each held a part of the image that
/// size.
///
/// A new mark painted over a moving tick in a large boundary grows it
/// again, and this says so. A column over the cursor — the frame area's own
/// edge, drawn over it — is its due; a part the size of the rows is not.
///
/// 🖥️On a desktop, with the app's scroll behaviour, as the app stands
/// there: the behaviour bars every scrollable on a desktop
/// ([AppScrollBehavior]), and a bar is a mark over the moving ticks. 🔬A
/// harness without it (10-28, the Surface's re-measure) wore Flutter's own
/// `Scrollbar`, whose foreground picture is the size of its scroll view —
/// the panel's body — and the image stood at 1.93 times the dock; with the
/// app's, 1.00. ↩️This ran on the test's Android, where nothing is barred.
///
/// 🖥️With the app's engine open, as the app always has it, so the rows stand
/// over their grid's screen: what stands over a texture cannot sink under it,
/// so what of the grid the dock shows is in the image a second time. That is
/// the screen's due (`_Strata.take` says why it is not drawn live instead);
/// the rest of the law stands. ↩️No engine opened here, and the image's 1.52
/// times the dock went unseen (11-09).
void main() {
  setUpAll(openAppGpuEngine);

  bool holdsAScreen(ContainerLayer layer) {
    for (var child = layer.firstChild;
        child != null;
        child = child.nextSibling) {
      if (child is TickSceneLayer && child.alwaysLive) {
        return true;
      }
      if (child is ContainerLayer && holdsAScreen(child)) {
        return true;
      }
    }
    return false;
  }

  const frames = 240;
  const rows = 12;
  const block = 12;

  Project project() => Project(
    id: const ProjectId('drag-image'),
    name: 'Drag image',
    createdAt: DateTime.utc(2026, 10, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: frames,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var r = 0; r < rows; r += 1)
                Layer(
                  id: LayerId('r$r'),
                  name: 'R$r',
                  frames: [
                    for (var i = 0; i < frames ~/ block; i += 1)
                      Frame(
                        id: FrameId('r$r-$i'),
                        duration: 1,
                        strokes: const [],
                        name: '${i + 1}',
                      ),
                  ],
                  timeline: {
                    for (var i = 0; i < frames ~/ block; i += 1)
                      i * block: TimelineExposure.drawing(
                        FrameId('r$r-$i'),
                        length: block,
                      ),
                  },
                ),
            ],
          ),
        ],
      ),
    ],
  );

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });
  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  Future<void> frame(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  for (final verb in ['block move', 'comma']) {
    testWidgets('a $verb: the dock\'s image holds the dock once', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          scrollBehavior: const AppScrollBehavior(),
          home: HomePage(initialProject: project()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(PanelScrollbar),
        findsWidgets,
        reason: '⛔premise: the desktop bars its scrollables',
      );
      for (var i = 0; i < StillRaster.maxStillFrames; i += 1) {
        await frame(tester);
      }
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      if (verb == 'block move') {
        session.updateFrameRangeSelectionDrag(
          layerId: const LayerId('r3'),
          anchorIndex: 42,
          headIndex: 42,
        );
        expect(session.rangeMove.beginFrameRangeMoveDrag(), isTrue);
        await tester.pump();
        session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
      } else {
        expect(
          session.edgeDrag.beginExposureEdgeDrag(
            layerId: const LayerId('r3'),
            blockStartIndex: 36,
            edge: TimelineBlockEdge.end,
          ),
          isTrue,
        );
        await tester.pump();
        session.edgeDrag.updateExposureEdgeDrag(1);
      }
      await tester.pump();
      for (var i = 0; i < StillRaster.stillFrames; i += 1) {
        await frame(tester);
      }

      final region = StillRaster.census.firstWhere(
        (r) =>
            r.attached &&
            r.debugLabel == 'dock:${EditorWorkspace.bottomGroupId}',
      );
      expect(region.debugDrawnFromImage, isTrue, reason: '⛔premise');
      expect(
        holdsAScreen(region.debugLayer!),
        isTrue,
        reason: '⛔premise: the rows stand over their grid\'s screen',
      );
      expect(
        region.debugLiveTicks,
        isNotEmpty,
        reason: '⛔premise: the image is cut at the ticks the drag moves',
      );
      final ratio = tester.view.devicePixelRatio;
      int bytesOf(Size size) =>
          ((size.width * ratio).ceil() + 1) *
          ((size.height * ratio).ceil() + 1) *
          4;
      final dock = MatrixUtils.transformRect(
        region.getTransformTo(null),
        Offset.zero & region.size,
      );
      final over = tester
          .getRect(find.byType(TimelineGridScreenHost))
          .intersect(dock);
      // 🔬1.09 of the two: the corner beside the shorter part stays empty.
      final due = (bytesOf(region.size) + bytesOf(over.size)) * 1.10;
      expect(
        region.rasterBytes,
        inInclusiveRange(1, due),
        reason: '${region.rasterBytes} bytes for a dock and what of the '
            'screen it shows, ${due.round()} at most',
      );

      if (verb == 'block move') {
        session.rangeMove.cancelFrameRangeMoveDrag();
      } else {
        session.edgeDrag.cancelExposureEdgeDrag();
      }
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
