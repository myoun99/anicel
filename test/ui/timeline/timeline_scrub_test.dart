import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'timeline_cell_probe.dart';

/// The ruler-scrub performance invariant (R4): drag moves ride the cursor
/// path — per-move frames go to the scrub callback WITHOUT a session
/// notify, and the pointer's release commits the selection exactly once.
void main() {
  final layers = [
    Layer(id: const LayerId('layer-1'), name: 'A', frames: const []),
  ];

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  testWidgets('timeline ruler drag routes moves to onScrubFrame and the '
      'release to onScrubEnd', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final scrubbed = <int>[];
    final selected = <int>[];
    var scrubEnds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
            frameCursor: cursor,
            playbackFrameCount: 20,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: selected.add,
            onScrubFrame: scrubbed.add,
            onScrubEnd: () => scrubEnds += 1,
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
        ),
      ),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    // 24px slim cells (R-toolbar round): one cell in from the ruler start,
    // then a four-cell drag.
    final start = tester.getTopLeft(scrubArea) + const Offset(24 + 4, 20);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(24 * 4, 0));

    expect(scrubbed, containsAllInOrder(<int>[1, 5]));
    expect(selected, isEmpty, reason: 'moves must not commit');
    expect(scrubEnds, 0, reason: 'no commit before the release');

    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrubEnds, 1, reason: 'the release commits exactly once');
    expect(selected, isEmpty, reason: 'commits go through onScrubEnd');
  });

  testWidgets('X-sheet frame rail drag routes moves to onScrubFrame and '
      'the release to onScrubEnd (Axis policy)', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final scrubbed = <int>[];
    final selected = <int>[];
    var scrubEnds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
            frameCursor: cursor,
            frameCount: 20,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: selected.add,
            onScrubFrame: scrubbed.add,
            onScrubEnd: () => scrubEnds += 1,
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
        ),
      ),
    );

    final rail = find.byKey(
      const ValueKey<String>('xsheet-frame-rail-scrub-area'),
    );
    final cellExtent = tester
        .widget<XSheetTimelineGrid>(find.byType(XSheetTimelineGrid))
        .metrics
        .frameCellWidth;
    final start = tester.getTopLeft(rail) + Offset(10, cellExtent + 4);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(Offset(0, cellExtent * 4));

    expect(scrubbed, isNotEmpty);
    expect(selected, isEmpty, reason: 'moves must not commit');
    expect(scrubEnds, 0);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrubEnds, 1);
    expect(selected, isEmpty);
  });

  group('session scrub path', () {
    EditorSessionManager session() {
      return EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('scrub-project'),
          name: 'Scrub Project',
          createdAt: DateTime.utc(2026, 7, 10),
          tracks: [
            Track(
              id: const TrackId('scrub-track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('scrub-cut'),
                  name: 'Scrub Cut',
                  duration: 24,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('cel-a'),
                      name: 'A',
                      frames: const [],
                      timeline: const {},
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('scrub moves never notify; the commit fires the committed-seek '
        'signal once and never a session notify', () {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);
      final commitsBefore = manager.frameSeekCommitted.value;

      manager.scrubFrameIndex(5);
      manager.scrubFrameIndex(9);
      expect(notifies, 0, reason: 'scrub moves ride the cursor path');
      expect(manager.currentFrameIndex, 9);
      expect(manager.editingFrameCursor.value, 9);
      expect(manager.frameScrubActive.value, isTrue);
      expect(manager.frameSeekCommitted.value, commitsBefore);

      manager.commitFrameScrub();
      expect(
        manager.frameSeekCommitted.value,
        commitsBefore + 1,
        reason: 'the release commits exactly once',
      );
      expect(
        notifies,
        0,
        reason: 'a seek is never a session notify — nothing else rebuilds',
      );
      expect(manager.frameScrubActive.value, isFalse);
      expect(manager.currentFrameIndex, 9);
    });

    test('a same-frame scrub never engages the preview', () {
      final manager = session();
      addTearDown(manager.dispose);

      manager.scrubFrameIndex(manager.currentFrameIndex);
      expect(
        manager.frameScrubActive.value,
        isFalse,
        reason: 'a plain tap must not flash the canvas preview',
      );

      manager.commitFrameScrub();
      expect(manager.frameScrubActive.value, isFalse);
    });

    test('selectFrameIndex keeps the editing cursor in sync and fires the '
        'committed-seek signal instead of a session notify', () {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);
      final commitsBefore = manager.frameSeekCommitted.value;

      manager.selectFrameIndex(7);
      expect(manager.editingFrameCursor.value, 7);
      expect(manager.frameSeekCommitted.value, commitsBefore + 1);
      expect(notifies, 0);
    });

    testWidgets('tab host: a ruler drag moves the playhead without a '
        'session notify and commits once on release', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // The HomePage-style wrapper: a session notify rebuilds the
            // host — exactly what scrub moves must avoid.
            body: ListenableBuilder(
              listenable: manager,
              builder: (context, _) => TimelineTabHost(
                session: manager,
                orientation: TimelineOrientation.horizontal,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 48,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      notifies = 0;

      final rowFinder = find.byKey(
        const ValueKey<String>('timeline-row-cells-cel-a'),
      );
      final rowBefore = tester.widget(rowFinder);

      final scrubArea = find.byKey(
        const ValueKey<String>('timeline-frame-ruler-scrub-area'),
      );
      final start = tester.getTopLeft(scrubArea) + const Offset(48 + 8, 20);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(48 * 4, 0));
      await tester.pump();

      expect(notifies, 0, reason: 'scrub moves must not notify the session');
      expect(manager.currentFrameIndex, 5);
      expect(
        identical(tester.widget(rowFinder), rowBefore),
        isTrue,
        reason: 'scrub moves must never rebuild cells',
      );
      // The playhead followed the pointer mid-gesture (cursor path).
      final ring = find.byKey(const ValueKey<String>('timeline-selected-cell'));
      expect(
        tester.getTopLeft(ring),
        timelineCellGlobalRect(tester, 'cel-a', 5).topLeft,
      );

      final commitsBefore = manager.frameSeekCommitted.value;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        manager.frameSeekCommitted.value,
        commitsBefore + 1,
        reason: 'the release commits exactly once',
      );
      expect(notifies, 0, reason: 'seeks are never session notifies');
      expect(manager.currentFrameIndex, 5);
      expect(manager.frameScrubActive.value, isFalse);
    });

    testWidgets('canvas swaps to the scrub preview while scrubbing and '
        'back on commit', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      final cameraView = ValueNotifier<bool>(false);
      final cameraDim = ValueNotifier<double>(0.5);
      addTearDown(brushTool.dispose);
      addTearDown(cameraView.dispose);
      addTearDown(cameraDim.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorCanvasArea(
              session: manager,
              brushToolState: brushTool,
              cameraViewEnabled: cameraView,
              cameraDimOpacity: cameraDim,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const previewKey = ValueKey<String>('canvas-scrub-preview');
      expect(find.byKey(previewKey), findsNothing);

      manager.scrubFrameIndex(4);
      await tester.pump();
      expect(
        find.byKey(previewKey),
        findsOneWidget,
        reason: 'scrubbing shows the composite-cache preview',
      );

      manager.commitFrameScrub();
      await tester.pumpAndSettle();
      expect(
        find.byKey(previewKey),
        findsNothing,
        reason: 'the commit swaps back to the editing canvas',
      );
    });

    testWidgets('storyboard: a ruler drag scrubs the active cut on the '
        'cursor path and commits once on release', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // The workspace-style wrapper: session notifies AND cursor
            // moves rebuild the host (the playhead follows scrubs live).
            body: ListenableBuilder(
              listenable: Listenable.merge([
                manager,
                manager.editingFrameCursor,
              ]),
              builder: (context, _) => StoryboardTabHost(
                session: manager,
                pixelsPerFrame: 12,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
                thumbnailFor: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      notifies = 0;

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final start = tester.getTopLeft(ruler) + const Offset(12 * 2 + 4, 10);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(12 * 6, 0));
      await tester.pump();

      expect(
        notifies,
        0,
        reason: 'storyboard scrub moves ride the cursor path',
      );
      expect(manager.currentFrameIndex, greaterThan(2));
      expect(manager.frameScrubActive.value, isTrue);

      final commitsBefore = manager.frameSeekCommitted.value;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(manager.frameSeekCommitted.value, commitsBefore + 1);
      expect(notifies, 0, reason: 'seeks are never session notifies');
      expect(manager.frameScrubActive.value, isFalse);
    });
  });
}
