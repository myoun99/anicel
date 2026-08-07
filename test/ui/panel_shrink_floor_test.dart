import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
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
/// the body. Each panel states its own floor now, and BOTH places a height
/// gets handed out honour it: the dock splitter and the section layout.
///
/// ⚠️ Everything here pumps `buildAppTheme()`. The first round measured the
/// command bars against a bare `MaterialApp`, where Material's 48px icon
/// button applies instead of the app theme's compact 32 — the constants
/// came out 2px and 12px too large, pinned against a panel the user never
/// sees. A layout constant measured under the wrong theme is a guess.
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
        theme: buildAppTheme(),
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

  Widget xsheet(EditorSessionManager session) =>
      timeline(session, orientation: TimelineOrientation.vertical);

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

    testWidgets('the storyboard command bar and header band are the ones '
        'StoryboardPanel.minPanelHeight reserves', (tester) async {
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

  group('at its floor a panel keeps its chrome and a usable body', () {
    testWidgets('timeline — exactly two rows', (tester) async {
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
        reason:
            'a body under the 32px thumb minimum is a bar that cannot '
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

    testWidgets('storyboard — a body of two lanes at the lane floor', (
      tester,
    ) async {
      await pumpAt(
        tester,
        storyboard,
        height: StoryboardTabHost.minPanelHeight,
      );

      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byType(StoryboardTabHost));
      final body = rectOf(tester, 'storyboard-vertical-scrollbar');
      final bottomRail = rectOf(tester, 'storyboard-horizontal-scrollbar');

      expect(body.height, 2 * StoryboardPanel.minTrackLaneHeight);
      expect(body.height, greaterThan(32));
      expect(bottomRail.bottom, host.bottom);
      expect(body.bottom, bottomRail.top);
    });

    testWidgets('the x-sheet does NOT share the timeline\'s floor — at that '
        'height its header window falls under the thumb minimum and stops '
        'being reachable', (tester) async {
      EditorSessionManager? session;

      double headerWindow(WidgetTester tester) {
        // The header block runs from under the layer-axis scrollbar strip
        // down to the rail splitter.
        final strip = rectOf(tester, 'timeline-bottom-scrollbar-rail');
        return rectOf(tester, 'xsheet-rail-splitter').top - strip.bottom;
      }

      session = await pumpAt(
        tester,
        xsheet,
        height: TimelinePanel.minPanelHeight,
        reuse: session,
      );
      expect(
        headerWindow(tester),
        lessThan(32),
        reason:
            'this is WHY the sheet needs its own floor: at the '
            'timeline\'s the rail scrollbar has nowhere to travel',
      );

      session = await pumpAt(
        tester,
        xsheet,
        height: TimelinePanel.minSheetPanelHeight,
        reuse: session,
      );
      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byType(TimelineTabHost));
      expect(
        headerWindow(tester),
        layerRailMinimumWindowExtent,
        reason:
            'the sheet\'s floor is the rail\'s own minimum window, '
            'stood on its side',
      );
      expect(
        host.bottom - rectOf(tester, 'xsheet-rail-splitter').bottom,
        layerRailFrameReserveExtent,
        reason:
            'and the frame area still keeps its reserve — two cells at '
            'the DEFAULT zoom, which is how that constant states itself',
      );
    });

    testWidgets('the conte keeps room for the action field its selected '
        'cell mounts', (tester) async {
      final session = await pumpAt(
        tester,
        (s) => ConteTabHost(session: s, thumbnailFor: null),
        height: ConteTabHost.minPanelHeight,
      );
      expect(tester.takeException(), isNull);

      // Select a cell so the non-flexible action row mounts.
      final page = rectOf(tester, 'conte-page');
      outer:
      for (var fx = 0.1; fx < 1.0; fx += 0.2) {
        for (var fy = 0.1; fy < 1.0; fy += 0.2) {
          await tester.tapAt(
            Offset(page.left + page.width * fx, page.top + page.height * fy),
          );
          await tester.pumpAndSettle();
          if (find
              .byKey(const ValueKey<String>('conte-action-field'))
              .evaluate()
              .isNotEmpty) {
            break outer;
          }
        }
      }
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the action row is a plain column child — it takes its '
            'height whether or not there is room',
      );
      expect(session.repository.requireProject(), isNotNull);
    });
  });

  group('no height from the floor up overflows or clips', () {
    const heights = [200.0, 240.0, 280.0, 350.0, 500.0];

    testWidgets('timeline', (tester) async {
      EditorSessionManager? session;
      for (final height in [TimelinePanel.minPanelHeight, ...heights]) {
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
      for (final height in [StoryboardTabHost.minPanelHeight, ...heights]) {
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
      // Its floor is higher than the timeline's, so the shared sweep list
      // starts below it — take only the heights this panel is allowed to
      // be asked for.
      for (final height in [
        TimelinePanel.minSheetPanelHeight,
        ...heights.where((h) => h >= TimelinePanel.minSheetPanelHeight),
      ]) {
        session = await pumpAt(tester, xsheet, height: height, reuse: session);
        expect(tester.takeException(), isNull, reason: 'x-sheet at $height');
        final host = tester.getRect(find.byType(TimelineTabHost));
        final splitter = rectOf(tester, 'xsheet-rail-splitter');
        expect(
          host.bottom - splitter.bottom,
          greaterThanOrEqualTo(layerRailFrameReserveExtent),
          reason: 'the frame reserve survives at $height',
        );
        expect(
          splitter.top -
              rectOf(tester, 'timeline-bottom-scrollbar-rail').bottom,
          greaterThanOrEqualTo(layerRailMinimumWindowExtent),
          reason: 'and so does a readable header window at $height',
        );
      }
    });

    testWidgets('the conte sheet, whose floor is chrome alone', (tester) async {
      EditorSessionManager? session;
      for (final height in [ConteTabHost.minPanelHeight, ...heights]) {
        session = await pumpAt(
          tester,
          (s) => ConteTabHost(session: s, thumbnailFor: null),
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'conte at $height');
      }
    });

    testWidgets('the cut envelope, which declares no floor at all', (
      tester,
    ) async {
      // It sits in the bottom dock beside the conte, so it is asked for
      // the conte's floor too — and a page that only scales has to survive
      // it without claiming a taller minimum for the whole dock.
      EditorSessionManager? session;
      for (final height in [ConteTabHost.minPanelHeight, ...heights]) {
        session = await pumpAt(
          tester,
          (s) => CutEnvelopeTabHost(session: s),
          height: height,
          reuse: session,
        );
        expect(tester.takeException(), isNull, reason: 'envelope at $height');
      }
    });
  });

  group('a dock is one group', () {
    // ⛔The water-filling that used to divide a rail between whatever was
    // open went with R2 #7: a rail panel keeps its OWN saved height and the
    // rail scrolls when they will not all fit, so there is no share to
    // compute. What that arithmetic protected — a panel never laid out
    // under its floor — is now `_railGroupHeight`'s floor, and it is
    // asserted where the user can see it (rail_groups_test).

    testWidgets('a DOCK is one group and cannot be split', (
      tester,
    ) async {
      // The stack is gone from the host, not merely unreachable: a layout
      // that still described one used to render it, splitter and all.
      EditorPanelTab tabFor(String id) => EditorPanelTab(
        id: id,
        label: id,
        icon: Icons.circle,
        minContentHeight: id == 'tall' ? 156 : null,
        builder: (context) => ColoredBox(
          key: ValueKey<String>('body-$id'),
          color: const Color(0xFF223344),
          child: const SizedBox.expand(),
        ),
      );

      final layout = EditorPanelLayoutModel(
        docks: {
          'bottom': DockGroup(tabs: ['tall', 'short']),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1200,
                height: 350,
                child: EditorDockHost(
                  layout: layout,
                  dockId: 'bottom',
                  tabResolver: tabFor,
                  draggingTab: ValueNotifier<EditorPanelTabDragData?>(null),
                  canAcceptTab: (_) => false,
                  onTabSelected: (_) {},
                  onTabMoved: (_, _) {},
                  onTabDragChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // One strip, both panels as TABS of it, and no divider anywhere.
      expect(find.byType(EditorPanelTabs), findsOneWidget);
      expect(find.byType(DockEdgeSplitter), findsNothing);

      final group = tester.getRect(find.byType(EditorPanelTabs));
      expect(group.height, closeTo(350, 0.001));
      final body = tester.getRect(
        find.byKey(const ValueKey<String>('body-tall')),
      );
      expect(body.bottom, lessThanOrEqualTo(group.bottom));
    });
  });

  group('the dock splitter stops at the floor, and the floor yields to the '
      'window', () {
    testWidgets('dragging the bottom dock splitter all the way down keeps '
        'the bottom scrollbar row and the vertical rail\'s foot — which is '
        'the report', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      );
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
      // The GROUP is the visible region. This is the assertion the bug
      // fails: laid out at a fixed height inside a scroller, the panel
      // keeps its full geometry and hangs out the bottom of the group.
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
        reason:
            'the bottom scrollbar row is inside the dock, not scrolled '
            'off the end of it',
      );
      expect(body.bottom, lessThanOrEqualTo(group.bottom));
      expect(panel.height, greaterThanOrEqualTo(TimelinePanel.minPanelHeight));
      expect(
        panel.bottom,
        // The strip is the 문턱 now — it sits on the region's bottom inner
        // edge, so "fills the dock" means "reaches the threshold", not
        // "reaches the window". The law is the same one: no vertical
        // scroller engaged, nothing overhanging.
        group.bottom - EditorPanelTabs.stripHeight,
        reason:
            'the panel FILLS the dock instead of overhanging it — no '
            'vertical scroller engaged',
      );
      expect(
        body.height,
        greaterThanOrEqualTo(2 * timelineLayerRowHeight),
        reason: 'the splitter stopped where the body stopped shrinking',
      );
    });

    testWidgets('in a window too short to pay the floor the dock yields '
        'rather than pushing the canvas out', (tester) async {
      // The floor is a promise about how a dock divides its own height,
      // not a claim on someone else's. Without this the splitter went
      // inert at a height the window could not show, and the user could
      // no longer drag their way back — worse than before the round.
      await tester.binding.setSurfaceSize(const Size(1000, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nothing overflows');

      // The floor has no tab of its own any more, so what "the canvas is
      // still there" means is the drawing surface itself.
      expect(
        find.byType(EditorCanvasArea),
        findsOneWidget,
        reason: 'the canvas is still on screen',
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the dock splitter model', () {
    test('minExtent raises the floor above _minDockExtent but never past '
        'the maximum', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'bottom': DockGroup(tabs: ['a']),
        },
      );
      model.resizeDock('bottom', -1000, fallback: 350, minExtent: 186);
      expect(model.dockExtent('bottom', fallback: 350), 186);

      // Without one, the model's own 160 still applies.
      model.resizeDock('bottom', -1000, fallback: 350);
      expect(model.dockExtent('bottom', fallback: 350), 160);

      // A floor past the maximum cannot invert the clamp.
      model.resizeDock('bottom', 0, fallback: 350, minExtent: 5000);
      expect(model.dockExtent('bottom', fallback: 350), 640);
    });

    test('a stored extent under the floor is lifted before the delta lands, '
        'so the first drag frame does not jump', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'bottom': DockGroup(tabs: ['a']),
        },
        dockExtents: {'bottom': 160},
      );
      model.resizeDock('bottom', 10, fallback: 350, minExtent: 186);
      expect(model.dockExtent('bottom', fallback: 350), 196);
    });
  });
}
