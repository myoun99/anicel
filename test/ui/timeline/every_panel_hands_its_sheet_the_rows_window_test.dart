import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import '../../helpers/storyboard_host.dart';

/// 🔬Card the-grid-sheet-draws-the-whole-axis-outside-the-shared-window:
/// EVERY PANEL HANDS ITS GRID SHEET THE WINDOW ITS ROWS ARE LAID IN — the
/// rows' own handle ([TimelineGridSheet.geometry]), live: scrolled two
/// spans on, the sheet stands in the window there. The timeline, the
/// x-sheet and the storyboard, each through its own scroll.
///
/// The handle itself, not one made alike (card conte-sideways-scroll-
/// build-spikes, 11-16): a sheet laid by a window of its own could stand
/// a window apart from the rows it lies under.
void main() {
  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );
  final layers = <Layer>[drawing('draw-0'), drawing('draw-1')];

  TimelineGridHooks hooks(ValueNotifier<int> cursor, int frames) =>
      TimelineGridHooks(
        activeLayer: ValueNotifier(const LayerId('draw-0')),
        frameCursor: cursor,
        playbackFrameCount: frames,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
      );

  /// The sheet [key] names, as it paints now.
  TimelineGridSheetPainter sheetIn(WidgetTester tester, String key) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byKey(ValueKey<String>(key)),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is TimelineGridSheetPainter,
                  ),
                ),
              )
              .painter!
          as TimelineGridSheetPainter;

  /// Scrolls [position] two spans and a cell on and asks [sheet] for the
  /// window its painter draws there.
  Future<void> expectTheRowsWindow(
    WidgetTester tester, {
    required String sheet,
    required ScrollPosition Function() position,
    required double cell,
  }) async {
    final span = timelineFrameWindowSpanFor(cell) * cell;
    position().jumpTo(span * 2 + cell);
    await tester.pumpAndSettle();
    final window = sheetIn(tester, sheet).geometry;
    expect(window, isNotNull, reason: 'the sheet drew the whole axis');
    final ownBoxes = tester
        .widgetList<TimelineFrameAxisBox>(
          find.descendant(
            of: find.byKey(ValueKey<String>(sheet)),
            matching: find.byType(TimelineFrameAxisBox),
          ),
        )
        .toSet();
    final rowsWindows = [
      for (final box in tester.widgetList<TimelineFrameAxisBox>(
        find.byType(TimelineFrameAxisBox),
      ))
        if (!ownBoxes.contains(box)) box.geometry,
    ];
    expect(rowsWindows, isNotEmpty, reason: '⛔premise: rows in windows');
    expect(
      rowsWindows.any((rows) => identical(rows, window)),
      isTrue,
      reason: 'the sheet stands in a window of its own, not its rows\'',
    );
    expect(
      timelineFrameWindowBucketOf(
        offset: position().pixels,
        cellExtent: cell,
      ),
      2,
      reason: '⛔premise: scrolled two spans',
    );
    final frames = window!.value;
    expect(frames.isWindowed, isTrue, reason: 'the sheet drew the whole axis');
    expect(
      frames.windowOriginPx,
      math.max(0.0, span * 2 - timelineFrameWindowMarginPx),
      reason: 'the window the view stands in',
    );
    expect(
      frames.viewExtentPx,
      position().viewportDimension,
      reason: 'how far the view reaches',
    );
  }

  testWidgets('the timeline', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: hooks(cursor, 2000),
            layers: layers,
            metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectTheRowsWindow(
      tester,
      sheet: 'timeline-grid-sheet',
      cell: 12,
      position: () => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position,
    );
  });

  testWidgets('the x-sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayer: ValueNotifier(const LayerId('draw-0')),
            frameCursor: cursor,
            playbackFrameCount: 2000,
            pixelsPerFrame: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('xsheet-frame-vertical-viewport'),
    );
    await expectTheRowsWindow(
      tester,
      sheet: 'xsheet-grid-sheet',
      cell: 12,
      position: () =>
          tester.widget<SingleChildScrollView>(viewport).controller!.position,
    );
  });

  testWidgets('the storyboard', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.repository.updateCutDuration(
      cutId: session.repository.requireProject().tracks.first.cuts.first.id,
      duration: 2000,
    );
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(900, 600),
      pixelsPerFrame: 8,
    );
    final viewport = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    await expectTheRowsWindow(
      tester,
      sheet: 'storyboard-grid-sheet',
      cell: 8,
      position: () =>
          tester.widget<SingleChildScrollView>(viewport).controller!.position,
    );
  });
}
