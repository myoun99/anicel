import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart'
    show LayerRailId;
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_vertical_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// 🚨A FRAME PANEL BROUGHT FORWARD AGAIN SHOWS ITS PLAYHEAD (유저
/// 2026-10-14, panels-are-built-only-while-open-Q1: 「다시 열 때 플레이헤드를
/// 드러낸다」). A panel is built only while it shows, so one put back in
/// front is built anew from the view kept above it: where it was left while
/// the playhead is in sight there — the endless room past the cut's end
/// included — and else moved the least that shows the playhead, on the
/// first frame it is open. A panel not shown since the project opened
/// stands where the project left it (F-267).
void main() {
  Project longCut() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(cuts: [track.cuts.first.copyWith(duration: 480)]),
      ],
    );
  }

  Future<EditorSessionManager> pumpApp(
    WidgetTester tester, {
    Size window = const Size(1500, 1000),
  }) async {
    await tester.binding.setSurfaceSize(window);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: longCut()),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// The frame axis behind the scrollbar keyed [key].
  ScrollPosition axisOf(WidgetTester tester, String key) =>
      switch (tester.widget(find.byKey(ValueKey<String>(key)))) {
        TimelineHorizontalScrollbarRail(:final controller) ||
        TimelineVerticalScrollbarRail(:final controller) => controller.position,
        final other => throw StateError('$key is a ${other.runtimeType}'),
      };
  ScrollPosition timelineAxis(WidgetTester tester) =>
      axisOf(tester, 'timeline-horizontal-scrollbar');
  ScrollPosition sheetAxis(WidgetTester tester) =>
      axisOf(tester, 'xsheet-vertical-scrollbar');
  ScrollPosition storyboardAxis(WidgetTester tester) =>
      axisOf(tester, 'storyboard-horizontal-scrollbar');

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  Future<void> showStoryboard(WidgetTester tester) =>
      press(tester, 'timeline-mode-storyboard-button');
  Future<void> showTimeline(WidgetTester tester) =>
      press(tester, 'timeline-mode-timeline-button');

  /// Whether [frame]'s cell stands inside [position]'s window with a cell
  /// of room on either side — what the walk calls in sight.
  bool inSight(ScrollPosition position, int frame, double cell) =>
      frame * cell - cell >= position.pixels - 0.5 &&
      (frame + 1) * cell + cell <= position.pixels +
          position.viewportDimension + 0.5;

  /// Watches [position] for a move made once a frame was already painted.
  List<double> movesAfterPaint(ScrollPosition position) {
    final moves = <double>[];
    position.addListener(() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.postFrameCallbacks) {
        moves.add(position.pixels);
      }
    });
    return moves;
  }

  testWidgets('the playhead in sight: the timeline comes back on the frames '
      'it was left at — past the cut\'s end too — its windows cut there', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.timeline]!;
    final builtEnd = timelineAxis(tester).maxScrollExtent;
    final view = timelineAxis(tester).viewportDimension;
    final cell = tester
        .widget<LayerTimelineGrid>(find.byType(LayerTimelineGrid))
        .metrics
        .frameCellWidth;
    expect(builtEnd, greaterThan(0), reason: '⛔전제: a cut longer than the view');

    for (final (name, to) in [
      ('inside the cut', builtEnd / 2),
      ('in the endless room past its end', builtEnd + view / 4),
    ]) {
      // The playhead in the middle of where the view will stand.
      final frame = ((to + view / 2) / cell).floor();
      session.selectFrameIndex(frame);
      await tester.pumpAndSettle();
      // As a walk or the folded row turns it (F-225): the axis by value,
      // the grid following.
      kept.value = to;
      await tester.pumpAndSettle();
      expect(timelineAxis(tester).pixels, closeTo(to, 0.5),
          reason: '⛔전제: the grid stood $name');
      expect(inSight(timelineAxis(tester), frame, cell), isTrue,
          reason: '⛔전제: the playhead in sight $name');

      await showStoryboard(tester);
      await showTimeline(tester);
      final grid = timelineAxis(tester);
      expect(grid.pixels, closeTo(to, 0.5),
          reason: 'brought forward again, the grid stands $name');
      expect(kept.value, closeTo(to, 0.5),
          reason: 'and nothing else was handed back to the kept view');
      final ruler = tester.widget<TimelineRulerCursorOverlay>(
        find.descendant(
          of: find.byType(LayerTimelineGrid),
          matching: find.byType(TimelineRulerCursorOverlay),
        ),
      );
      expect(
        ruler.windowBucket.value,
        timelineFrameWindowBucketOf(offset: grid.pixels, cellExtent: cell),
        reason: '🚨the rows and the ruler were cut for the first page — '
            'nothing painted where the grid stands $name',
      );

      // Built again for nothing: the room it was brought forward in is
      // the room it keeps.
      session.notifyChanged();
      await tester.pumpAndSettle();
      expect(timelineAxis(tester).pixels, closeTo(to, 0.5),
          reason: '🚨built again, the grid gave back the room it stood in '
              '$name');
    }
  });

  testWidgets('🚨the playhead out of sight: the FIRST frame the timeline is '
      'open shows it, moved the least — nothing moves after it is painted', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.timeline]!;
    final cell = tester
        .widget<LayerTimelineGrid>(find.byType(LayerTimelineGrid))
        .metrics
        .frameCellWidth;
    session.selectFrameIndex(100);
    await tester.pumpAndSettle();
    kept.value = timelineAxis(tester).maxScrollExtent;
    await tester.pumpAndSettle();
    expect(inSight(timelineAxis(tester), 100, cell), isFalse,
        reason: '⛔전제: the playhead out of sight');

    await showStoryboard(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
    );
    // ONE frame — the first one open.
    await tester.pump();
    final grid = timelineAxis(tester);
    final moved = movesAfterPaint(grid);
    expect(
      grid.pixels,
      closeTo(100 * cell - cell, 0.5),
      reason: '🚨the first frame open stands where the playhead shows, a '
          'cell of the frame before it in sight — the least move',
    );
    await tester.pumpAndSettle();
    expect(moved, isEmpty,
        reason: '🚨the grid opened where it was left and jumped after paint');
    expect(kept.value, closeTo(100 * cell - cell, 0.5));
  });

  testWidgets('the x-sheet brought forward again shows the playhead on ITS '
      'axis', (tester) async {
    // Tall: the sheet's headers take most of a short region (🧪48px of
    // frames under a 410px one).
    final session = await pumpApp(tester, window: const Size(1500, 2000));
    await press(tester, 'timeline-orientation-toggle-button');
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.xsheet]!;
    final cell = tester
        .widget<XSheetTimelineGrid>(find.byType(XSheetTimelineGrid))
        .metrics
        .frameCellWidth;
    expect(sheetAxis(tester).viewportDimension, greaterThan(3 * cell),
        reason: '⛔전제: a window with a cell of room either side');
    session.selectFrameIndex(10);
    await tester.pumpAndSettle();
    kept.value = sheetAxis(tester).maxScrollExtent;
    await tester.pumpAndSettle();
    expect(inSight(sheetAxis(tester), 10, cell), isFalse,
        reason: '⛔전제: the playhead out of sight');

    await showStoryboard(tester);
    await showTimeline(tester);
    expect(sheetAxis(tester).pixels, closeTo(10 * cell - cell, 0.5));
    expect(kept.value, closeTo(10 * cell - cell, 0.5));
  });

  testWidgets('the storyboard not shown since the project opened stands '
      'where the project left it; shown again, it shows the playhead', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.storyboard]!;
    // Where a project saved with the conte scrolled away opens it (F-267),
    // the playhead at its first frame.
    kept.value = 600;
    await showStoryboard(tester);
    expect(storyboardAxis(tester).pixels, closeTo(600, 0.5),
        reason: 'first shown, it stands where the project left it');

    await showTimeline(tester);
    await showStoryboard(tester);
    expect(storyboardAxis(tester).pixels, closeTo(0, 0.5),
        reason: 'shown again, the playhead at frame 0 is brought in sight');
    expect(kept.value, closeTo(0, 0.5));
  });

  testWidgets('a rail group opening is a panel brought forward too — the '
      'storyboard dropped on a closed group, and the group opened again', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    final kept = session.panelViews.frameAxisOffsets[LayerRailId.storyboard]!;
    await showStoryboard(tester);
    final cell = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    session.selectFrameIndex(20);
    await tester.pumpAndSettle();
    kept.value = 2000;
    await tester.pumpAndSettle();
    expect(inSight(storyboardAxis(tester), 20, cell), isFalse,
        reason: '⛔전제: the playhead out of sight');
    await showTimeline(tester);

    // Dragged by its grip onto the closed group's button: the group takes
    // it and opens.
    const group = EditorWorkspace.rightGroupId;
    final button = find.byKey(const ValueKey<String>('rail-group-$group'));
    expect(button, findsOneWidget, reason: '⛔전제: the group has a button');
    expect(find.byType(StoryboardPanel), findsNothing,
        reason: '⛔전제: the storyboard is not built behind the timeline');
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('panel-grip-storyboard')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(button) + const Offset(0, -10));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(button));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsOneWidget,
        reason: '⛔전제: the group opened with the storyboard in front');
    expect(kept.value, closeTo(20 * cell - cell, 0.5),
        reason: '🚨the group opened on the storyboard where it was left');
    expect(storyboardAxis(tester).pixels, closeTo(20 * cell - cell, 0.5));

    // Closed, the axis turned elsewhere meanwhile, and opened again.
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsNothing,
        reason: '⛔전제: the group closed');
    kept.value = 2000;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(kept.value, closeTo(20 * cell - cell, 0.5),
        reason: '🚨the group opened again on the storyboard where it was left');
  });

  testWidgets('the storyboard brought forward lands a playhead past the end '
      'of a cut not the track\'s last on that cut\'s last frame — the '
      'timeline\'s parity', (tester) async {
    final session = await pumpApp(tester);
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final cuts = session.repository.requireProject().tracks.first.cuts;
    expect(cuts, hasLength(2), reason: '⛔전제: a cut after it');
    session.selectCut(cuts.first.id);
    session.selectFrameIndex(cuts.first.duration + 3);
    await tester.pumpAndSettle();
    expect(session.currentFrameIndex, cuts.first.duration + 3,
        reason: '⛔전제: the timeline holds it in the cut\'s endless room');

    await showStoryboard(tester);
    expect(session.currentFrameIndex, cuts.first.duration - 1);
  });
}
