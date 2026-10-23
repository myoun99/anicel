import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
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

/// 🚨A FOLD BUILDS THE COMMAND BAR AND NO BODY (유저 2026-10-14: 「열려있을때만
/// 지어지는게 맞는구조」 · 「이건 모든 패널 공통적인 사항이야」 — card
/// `a-folded-panel-builds-its-body`), and the body built again when the
/// region opens stands where the axis was left, or turned by the folded row
/// meanwhile, from its first frame.
///
/// What a fold still KEEPS is the host: measured 09-27, every fold and
/// unfold made a new state for the timeline's host too — the row the region
/// folds into was laid into the workspace's stack before the region with no
/// key, so the region's own slot was matched to the row's by position. The
/// workspace keys the region since (09-28). ↩️From then to 10-23 the bodies
/// were kept too, OFFSTAGE — laid out, never painted.
///
/// ⛔Both frame panels, by one set of questions: the timeline's grid goes
/// with the fold, while the storyboard's panel stays for the rows it hands
/// the folded row and the walk, and builds no body.
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

  /// The two frame panels: the widget that is the panel, and the key of the
  /// scroller its frame axis runs in.
  const panels = [
    (
      name: 'timeline',
      button: 'timeline-mode-timeline-button',
      panel: LayerTimelineGrid,
      frames: 'timeline-frame-scroll-viewport',
    ),
    (
      name: 'storyboard',
      button: 'timeline-mode-storyboard-button',
      panel: StoryboardPanel,
      frames: 'storyboard-timeline-horizontal-viewport',
    ),
  ];

  Future<void> bringForward(WidgetTester tester, String button) async {
    await tester.tap(find.byKey(ValueKey<String>(button)));
    await tester.pumpAndSettle();
  }

  /// The panel's frame axis, as its scrollable stands — null where none is
  /// built, folded away or not.
  ScrollPosition? framesOf(WidgetTester tester, String key) {
    final scrollables = find.descendant(
      of: find.byKey(ValueKey<String>(key), skipOffstage: false),
      matching: find.byType(Scrollable, skipOffstage: false),
      skipOffstage: false,
    );
    return scrollables.evaluate().isEmpty
        ? null
        : tester.state<ScrollableState>(scrollables.first).position;
  }

  ValueNotifier<double> foldedAxis(WidgetTester tester) => tester
      .widget<CollapsedRowOverlay>(find.byType(CollapsedRowOverlay))
      .frameAxisOffset!;

  testWidgets('🚨folded, the timeline builds its command bar and no grid — '
      'and its host is the one it had, folded and opened', (tester) async {
    await pumpApp(tester);
    final host = tester.state(find.byType(TimelineTabHost));

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.byType(CollapsedRowOverlay), findsOneWidget, reason: '⛔전제');
    expect(
      find.byType(LayerTimelineGrid, skipOffstage: false),
      findsNothing,
      reason: '🚨the grid was built folded away',
    );
    expect(
      identical(tester.state(find.byType(TimelineTabHost)), host),
      isTrue,
      reason: '🚨folding built a new host',
    );

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.byType(LayerTimelineGrid), findsOneWidget);
    expect(
      identical(tester.state(find.byType(TimelineTabHost)), host),
      isTrue,
      reason: '🚨unfolding built a new host',
    );
  });

  testWidgets('🚨folded, the storyboard builds no body — and its panel is the '
      'one it had, folded and opened', (tester) async {
    await pumpApp(tester);
    await bringForward(tester, 'timeline-mode-storyboard-button');
    final panel = tester.state(find.byType(StoryboardPanel));
    expect(framesOf(tester, panels.last.frames), isNotNull, reason: '⛔전제');

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.byType(CollapsedRowOverlay), findsOneWidget, reason: '⛔전제');
    expect(
      find.descendant(
        of: find.byType(StoryboardPanel, skipOffstage: false),
        matching: find.byType(Scrollable, skipOffstage: false),
        skipOffstage: false,
      ),
      findsNothing,
      reason: '🚨the body was built folded away',
    );
    expect(
      identical(
        tester.state(find.byType(StoryboardPanel, skipOffstage: false)),
        panel,
      ),
      isTrue,
      reason: '🚨folding built a new panel — the rows the folded row reads '
          'went with it',
    );

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(framesOf(tester, panels.last.frames), isNotNull);
    expect(
      identical(tester.state(find.byType(StoryboardPanel)), panel),
      isTrue,
      reason: '🚨unfolding built a new panel',
    );
  });

  testWidgets('🚨storyboard: folded, the rows it hands the walk are the '
      'rows as they stand — lanes twirled open folded are walked into', (
    tester,
  ) async {
    // ⛔What the panel stays for while it builds no body: the folded row and
    // the walk read its rows, and a body that is not laid must not leave
    // them where the last open layout did.
    await pumpApp(tester);
    await bringForward(tester, 'timeline-mode-storyboard-button');
    await tester.tap(fold);
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final channel = tester
        .widget<StoryboardPanel>(
          find.byType(StoryboardPanel, skipOffstage: false),
        )
        .rowsChannel!;
    final folded = channel.rows.length;
    final camera = session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .singleWhere((layer) => layer.kind == LayerKind.camera);

    session.layerSwitches.toggleLayerLanes(camera.id);
    await tester.pumpAndSettle();
    expect(find.byType(CollapsedRowOverlay), findsOneWidget, reason: '⛔전제');
    expect(
      channel.rows.length,
      greaterThan(folded),
      reason: '🚨the camera\'s lanes, twirled open folded, are not rows',
    );
  });

  for (final panel in panels) {
    testWidgets('🚨${panel.name}: a walk revealed while folded is where the '
        'body stands on the FIRST frame it is open again', (tester) async {
      // ⛔A WALK, not playback: a press while playing only stops it (the
      // actuation gate), so nobody opens the region mid-play. A walk's
      // reveal lands after its frame, turning the folded row's axis.
      await pumpApp(tester);
      await bringForward(tester, panel.button);
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

      // ⛔NOT the position after the pump: a body that caught up only after
      // its first open frame was painted reads right once the pump is over.
      // Read AS PAINTED — in a callback after that frame's paint, asked
      // before the frame, so it runs ahead of any the body asks for while
      // it is built.
      ({double offset, int bucket, double cell})? painted;
      await tester.tap(fold);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final ruler = tester.widget<TimelineRulerCursorOverlay>(
          find.descendant(
            of: find.byType(panel.panel),
            matching: find.byType(TimelineRulerCursorOverlay),
          ),
        );
        painted = (
          offset: framesOf(tester, panel.frames)!.pixels,
          bucket: ruler.windowBucket.value,
          cell: ruler.cellWidth,
        );
      });
      // ONE frame — the first one open.
      await tester.pump();
      expect(
        find.byType(CollapsedRowOverlay),
        findsNothing,
        reason: '⛔전제: the region opened',
      );
      final (:offset, :bucket, :cell) = painted!;
      expect(
        offset,
        closeTo(turned, 0.5),
        reason: '🚨the first frame open showed the page it was folded on',
      );
      // And the windows are cut for where it stands: the ruler paints the
      // slice its bucket names.
      final standsIn = timelineFrameWindowBucketOf(
        offset: offset,
        cellExtent: cell,
      );
      expect(standsIn, greaterThan(0), reason: '⛔전제: a page past bucket 0');
      expect(
        bucket,
        standsIn,
        reason: '🚨the body stood on the page, but its windows were still '
            'cut for the one it was folded on',
      );
    });

    testWidgets('🚨${panel.name}: opened, the body stands where the folded '
        'row turned the axis — past its own range too — and hands none of '
        'it back', (tester) async {
      // ⛔The row on screen owns the axis while the region is folded, and a
      // kept axis has no end of its own (pageKeptAxis): the row can stand
      // where the body's own range does not reach. Opened, the body grows
      // the room under it (F-225, 「펼치면 스크롤 동기화」) rather than
      // pulling the axis back to its end.
      await pumpApp(tester);
      await bringForward(tester, panel.button);
      final past = framesOf(tester, panel.frames)!.maxScrollExtent + 500;
      await tester.tap(fold);
      await tester.pumpAndSettle();
      final axis = foldedAxis(tester);
      // Where the folded row's page law would put it — written as the row
      // writes it.
      axis.value = past;
      await tester.pumpAndSettle();

      await tester.tap(fold);
      await tester.pumpAndSettle();
      expect(framesOf(tester, panel.frames)!.pixels, closeTo(past, 0.5));
      expect(
        axis.value,
        past,
        reason: '🚨the body opened wrote its own end over the row\'s page',
      );
    });
  }
}
