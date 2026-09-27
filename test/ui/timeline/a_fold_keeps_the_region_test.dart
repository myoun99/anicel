import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨A FOLD KEEPS THE REGION: folding the bottom region and opening it again
/// is a flag, not a rebuild of everything in it.
///
/// Measured 09-27: every fold and every unfold made a NEW state for the
/// timeline's grid and host and for the storyboard kept beside them. The
/// row the region folds into was laid into the workspace's stack before the
/// region with no key, so the region's own slot was matched to the row's by
/// position and everything under it was built afresh — while the panels'
/// own notes said the grid went offstage precisely to keep its scroll
/// positions, its caches and its subtree through a fold. F-143 kept the
/// frame axis above the grid for that reason; this keeps the grid.
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

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: longCut()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
  }

  final fold = find.byKey(const ValueKey<String>('floating-bottom-collapse'));

  State stateOf(WidgetTester tester, Type type) =>
      tester.state(find.byType(type, skipOffstage: false));

  testWidgets('🚨fold and unfold keep the grid, its host and the storyboard '
      'beside them', (tester) async {
    await pumpApp(tester);
    // The storyboard once, so its kept-alive tab is built beside the
    // timeline's.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
    );
    await tester.pumpAndSettle();
    final kept = [
      for (final type in [LayerTimelineGrid, TimelineTabHost, StoryboardPanel])
        stateOf(tester, type),
    ];

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.byType(CollapsedRowOverlay), findsOneWidget, reason: '⛔전제');
    for (final (i, type) in [
      LayerTimelineGrid,
      TimelineTabHost,
      StoryboardPanel,
    ].indexed) {
      expect(
        identical(stateOf(tester, type), kept[i]),
        isTrue,
        reason: '🚨folding built a new $type',
      );
    }

    await tester.tap(fold);
    await tester.pumpAndSettle();
    for (final (i, type) in [
      LayerTimelineGrid,
      TimelineTabHost,
      StoryboardPanel,
    ].indexed) {
      expect(
        identical(stateOf(tester, type), kept[i]),
        isTrue,
        reason: '🚨unfolding built a new $type',
      );
    }
  });

  /// The grid's frame axis — folded away or not.
  ScrollPosition gridAxis(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
                skipOffstage: false,
              ),
              matching: find.byType(Scrollable, skipOffstage: false),
              skipOffstage: false,
            )
            .first,
      )
      .position;

  ValueNotifier<double> foldedAxis(WidgetTester tester) => tester
      .widget<CollapsedRowOverlay>(find.byType(CollapsedRowOverlay))
      .frameAxisOffset!;

  testWidgets('🚨a walk revealed while folded is where the grid stands on the '
      'FIRST frame it is open again', (tester) async {
    // ⚠️The grid now stays mounted, folded away, while the folded row turns
    // the shared axis — so it must follow the axis while hidden. A grid
    // that caught up only after its first open layout would show the page
    // it was folded on for one frame (「한 프레임 보이는 건 걸린다」).
    //
    // ⛔A WALK, not playback: a press while playing only stops it (the
    // actuation gate), so nobody opens the region mid-play — and the stop
    // rebuilds the grid, which pulled it along by the layout's own sync
    // and hid the case. A walk's reveal lands after its frame, with nothing
    // left to rebuild the grid before it opens.
    await pumpApp(tester);
    await tester.tap(fold);
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final axis = foldedAxis(tester);
    session.selectFrameIndex(400);
    session.revealSelection();
    await tester.pumpAndSettle();
    expect(axis.value, greaterThan(0), reason: '⛔전제: the walk turned it');
    final turned = axis.value;

    // ⛔NOT the position after the frame: the layout's own sync pulls the
    // grid to the axis AFTER the frame is painted, so reading the position
    // once the pump is over reads the pull, not the picture. What is
    // measured is whether the grid had to move once the first open frame
    // was already on screen.
    final grid = gridAxis(tester);
    final movedAfterPaint = <double>[];
    void afterPaint() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.postFrameCallbacks) {
        movedAfterPaint.add(grid.pixels);
      }
    }

    grid.addListener(afterPaint);
    await tester.tap(fold);
    // ONE frame — the first one open.
    await tester.pump();
    grid.removeListener(afterPaint);
    expect(
      find.byType(CollapsedRowOverlay),
      findsNothing,
      reason: '⛔전제: the region opened',
    );
    // And the windows are cut for where it stands: the ruler paints the
    // slice its bucket names.
    final ruler = tester.widget<TimelineRulerCursorOverlay>(
      find.descendant(
        of: find.byType(LayerTimelineGrid),
        matching: find.byType(TimelineRulerCursorOverlay),
      ),
    );
    final bucket = ruler.windowBucket.value;
    final standsIn = timelineFrameWindowBucketOf(
      offset: grid.pixels,
      cellExtent: ruler.cellWidth,
    );
    expect(
      movedAfterPaint,
      isEmpty,
      reason: '🚨the first frame open showed the page the grid was folded on, '
          'and the grid jumped to the axis only after it',
    );
    expect(grid.pixels, closeTo(turned, 0.5));
    expect(standsIn, greaterThan(0), reason: '⛔전제: a page past bucket 0');
    expect(
      bucket,
      standsIn,
      reason: '🚨the grid stood on the page, but its windows were still cut '
          'for the one it was folded on',
    );
  });

  testWidgets('🚨folded, the grid follows the axis and never turns it back', (
    tester,
  ) async {
    // ⛔The row on screen owns the axis while the region is folded, and a
    // kept axis has no end of its own (pageKeptAxis): the row can stand
    // where the grid's own range does not reach. The grid goes as far as it
    // can; it does not hand its own end back to the row.
    await pumpApp(tester);
    await tester.tap(fold);
    await tester.pumpAndSettle();
    final axis = foldedAxis(tester);
    final grid = gridAxis(tester);
    // Where the folded row's page law would put it — written as the row
    // writes it; the pins above turn it by real playback.
    final past = grid.maxScrollExtent + 500;
    axis.value = past;
    await tester.pumpAndSettle();

    expect(grid.pixels, greaterThan(0), reason: 'the grid followed the axis');
    expect(
      axis.value,
      past,
      reason: '🚨the grid folded away wrote its own end over the row\'s page',
    );
  });
}
