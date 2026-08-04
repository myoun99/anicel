import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// The shrink-floor round (user, 2026-08-02).
///
/// > 타임라인패널의 세로스플리터를 줄여서 패널을 작게 하면 (…) 패널 자체가
/// > 줄어버려서 내부영역 세로스크롤바의 밑부분이 사라지고, 맨 밑의
/// > 가로스크롤바마저 사라진다.
///
/// The panels used to lay out at a flat 280px whatever the dock gave them
/// and scroll, so shrinking the dock CUT the bottom off instead of shrinking
/// the body. Each panel states its own floor now — chrome plus two rows —
/// and the dock splitter stops there.
///
/// These tests measure the REAL widgets, never the constants against
/// themselves: the command-bar heights are claims about how the rows lay
/// out, and a claim nobody measures is how the 280 got there.
void main() {
  Future<EditorSessionManager> pumpAt(
    WidgetTester tester,
    Widget Function(EditorSessionManager session) build, {
    required double height,
    EditorSessionManager? reuse,
    double width = 1200,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager =
        reuse ?? EditorSessionManager(initialProject: createDefaultProject());
    if (reuse == null) {
      addTearDown(manager.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  manager,
                  manager.frameSeekCommitted,
                ]),
                builder: (context, _) => build(manager),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  Widget timeline(
    EditorSessionManager session, {
    TimelineOrientation orientation = TimelineOrientation.horizontal,
  }) => TimelineTabHost(
    session: session,
    orientation: orientation,
    onOrientationChanged: (_) {},
    pixelsPerFrame: 24,
    onPixelsPerFrameChanged: (_) {},
    showSeconds: false,
    onShowSecondsChanged: (_) {},
  );

  Widget storyboard(EditorSessionManager session) => StoryboardTabHost(
    session: session,
    pixelsPerFrame: 12,
    onPixelsPerFrameChanged: (_) {},
    showSeconds: false,
    onShowSecondsChanged: (_) {},
    thumbnailFor: null,
  );

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey<String>(key)).first);

  group('the chrome each floor is built from is what the panels draw', () {
    testWidgets('the timeline command bar is TimelinePanel.commandBarHeight', (
      tester,
    ) async {
      await pumpAt(tester, timeline, height: 600);

      final host = tester.getRect(find.byType(TimelineTabHost));
      final grid = rectOf(tester, 'timeline-scrollbar-area');
      expect(
        grid.top - host.top,
        TimelinePanel.commandBarHeight,
        reason: 'the floor reserves this much for the command bar',
      );
      expect(
        rectOf(tester, 'timeline-frame-ruler').height,
        timelineFrameRulerExtent,
      );
      expect(
        rectOf(tester, 'timeline-bottom-scrollbar-rail').height,
        timelineBottomScrollbarRailHeight,
      );
    });

    testWidgets('the storyboard command bar is '
        'StoryboardTabHost.commandBarHeight, and its header band is the '
        'height StoryboardPanel.minPanelHeight reserves', (tester) async {
      await pumpAt(tester, storyboard, height: 600);

      final host = tester.getRect(find.byType(StoryboardTabHost));
      final panel = rectOf(tester, 'storyboard-panel');
      expect(
        panel.top - host.top,
        StoryboardTabHost.commandBarHeight,
        reason: 'the floor reserves this much for the command bar',
      );
      // The band above the body: panel top to where the scrollbar rail
      // (which spans exactly the body) begins.
      final body = rectOf(tester, 'storyboard-vertical-scrollbar');
      expect(
        body.top - panel.top,
        StoryboardPanel.minPanelHeight -
            2 * StoryboardPanel.minTrackLaneHeight -
            rectOf(tester, 'storyboard-horizontal-scrollbar').height,
        reason: 'the header band the floor reserves is the one drawn',
      );
    });
  });

  group('at its floor a panel shows exactly two rows and loses no chrome', () {
    testWidgets('timeline', (tester) async {
      await pumpAt(tester, timeline, height: TimelinePanel.minPanelHeight);

      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byType(TimelineTabHost));
      final body = rectOf(tester, 'timeline-vertical-scrollbar');
      final bottomRail = rectOf(tester, 'timeline-bottom-scrollbar-rail');

      expect(
        body.height,
        2 * timelineLayerRowHeight,
        reason: 'the body stops at two rows — the user\'s rule',
      );
      expect(
        body.height,
        greaterThan(32),
        reason: 'a body under the 32px thumb minimum is a bar that cannot '
            'be dragged',
      );
      expect(
        bottomRail.bottom,
        host.bottom,
        reason: 'the row the user watched vanish sits ON the bottom edge',
      );
      expect(
        body.bottom,
        bottomRail.top,
        reason: 'the vertical rail runs down to the bottom row, foot intact',
      );
    });

    testWidgets('storyboard', (tester) async {
      await pumpAt(tester, storyboard, height: StoryboardTabHost.minPanelHeight);

      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byType(StoryboardTabHost));
      final body = rectOf(tester, 'storyboard-vertical-scrollbar');
      final bottomRail = rectOf(tester, 'storyboard-horizontal-scrollbar');

      expect(
        body.height,
        2 * StoryboardPanel.minTrackLaneHeight,
        reason: 'two track lanes at their floor — the timeline\'s 28 twice',
      );
      expect(body.height, greaterThan(32));
      expect(bottomRail.bottom, host.bottom);
      expect(body.bottom, bottomRail.top);
    });

    testWidgets('the x-sheet shares the timeline\'s floor and lands on its '
        'own two cells there', (tester) async {
      await pumpAt(
        tester,
        (session) =>
            timeline(session, orientation: TimelineOrientation.vertical),
        height: TimelinePanel.minPanelHeight,
      );

      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byType(TimelineTabHost));
      final splitter = rectOf(tester, 'xsheet-rail-splitter');
      expect(
        host.bottom - splitter.bottom,
        layerRailFrameReserveExtent,
        reason: 'stood on its side the frame axis is vertical, so the floor '
            'has to leave the frame area its two-cell reserve',
      );
    });
  });

  group('no height from the floor up overflows or clips', () {
    const heights = [
      156.0,
      160.0,
      170.0,
      186.0,
      200.0,
      240.0,
      280.0,
      350.0,
      500.0,
    ];

    testWidgets('timeline', (tester) async {
      EditorSessionManager? session;
      for (final height in heights) {
        session = await pumpAt(
          tester,
          timeline,
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'timeline at $height');
        final host = tester.getRect(find.byType(TimelineTabHost));
        expect(
          rectOf(tester, 'timeline-bottom-scrollbar-rail').bottom,
          host.bottom,
          reason: 'bottom row pinned at $height',
        );
        expect(
          rectOf(tester, 'timeline-vertical-scrollbar').height,
          greaterThanOrEqualTo(2 * timelineLayerRowHeight),
          reason: 'two rows or more at $height',
        );
      }
    });

    testWidgets('storyboard', (tester) async {
      EditorSessionManager? session;
      for (final height in heights) {
        session = await pumpAt(
          tester,
          storyboard,
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'storyboard at $height');
        final host = tester.getRect(find.byType(StoryboardTabHost));
        expect(
          rectOf(tester, 'storyboard-horizontal-scrollbar').bottom,
          host.bottom,
          reason: 'bottom row pinned at $height',
        );
        expect(
          rectOf(tester, 'storyboard-vertical-scrollbar').height,
          greaterThanOrEqualTo(2 * StoryboardPanel.minTrackLaneHeight),
          reason: 'two lanes or more at $height',
        );
      }
    });

    testWidgets('x-sheet', (tester) async {
      EditorSessionManager? session;
      for (final height in heights) {
        session = await pumpAt(
          tester,
          (s) => timeline(s, orientation: TimelineOrientation.vertical),
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'x-sheet at $height');
        final host = tester.getRect(find.byType(TimelineTabHost));
        expect(
          host.bottom - rectOf(tester, 'xsheet-rail-splitter').bottom,
          greaterThanOrEqualTo(layerRailFrameReserveExtent),
          reason: 'two frame cells or more at $height',
        );
      }
    });

    testWidgets('the conte sheet, which is why it gets no floor at all', (
      tester,
    ) async {
      EditorSessionManager? session;
      for (final height in [...heights, 120.0, 80.0, 40.0]) {
        session = await pumpAt(
          tester,
          (s) => ConteTabHost(session: s, thumbnailFor: null),
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'conte at $height');
      }
    });
  });

  testWidgets('dragging the bottom dock splitter all the way down stops at '
      'the floor — the bottom scrollbar row and the vertical rail\'s foot '
      'are still there, which is the report', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final panel = tester.getRect(find.byType(TimelineTabHost));
    final bottomRail = rectOf(tester, 'timeline-bottom-scrollbar-rail');
    final body = rectOf(tester, 'timeline-vertical-scrollbar');
    // The GROUP is the visible region — the tab strip plus whatever the
    // dock left for content. This is the assertion the bug fails: laid out
    // at a fixed height inside a scroller, the panel keeps its full
    // geometry and hangs out the bottom of the group, which is exactly the
    // rows the user watched disappear.
    final group = tester.getRect(
      find
          .ancestor(
            of: find.byType(TimelineTabHost),
            matching: find.byType(EditorPanelTabs),
          )
          .first,
    );

    expect(
      bottomRail.bottom,
      lessThanOrEqualTo(group.bottom),
      reason: 'the bottom scrollbar row is inside the dock, not scrolled off '
          'the end of it',
    );
    expect(
      body.bottom,
      lessThanOrEqualTo(group.bottom),
      reason: 'the vertical rail\'s foot is inside the dock',
    );
    expect(
      panel.height,
      greaterThanOrEqualTo(TimelinePanel.minPanelHeight),
      reason: 'the splitter stopped at the floor instead of dragging past it',
    );
    expect(
      panel.bottom,
      group.bottom,
      reason: 'the panel FILLS the dock instead of overhanging it — no '
          'vertical scroller engaged',
    );
    expect(
      body.height,
      greaterThanOrEqualTo(2 * timelineLayerRowHeight),
      reason: 'the splitter stopped where the body stopped shrinking',
    );
    expect(
      body.bottom,
      bottomRail.top,
      reason: 'the vertical rail still reaches the bottom row',
    );
    expect(
      bottomRail.bottom,
      panel.bottom,
      reason: 'the row the user watched vanish is still on the bottom edge',
    );
    expect(
      bottomRail.bottom,
      lessThanOrEqualTo(1000.0),
      reason: 'nothing was pushed off the window',
    );
  });

  testWidgets('the floor a dock reserves counts the tab STRIP too, so the '
      'panel keeps its rows once the strip is subtracted', (tester) async {
    // Guards the arithmetic in _verticalDockMinimumExtent without reaching
    // into it: a section costs its strip plus the tallest tab floor in it,
    // and the bottom dock ships timeline + storyboard + conte in one.
    expect(
      EditorPanelTabs.stripHeight + TimelinePanel.minPanelHeight,
      greaterThan(StoryboardTabHost.minPanelHeight),
      reason: 'the timeline is the tallest floor in the bottom dock',
    );
  });
}
