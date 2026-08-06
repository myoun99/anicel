import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

const _toolsTabKey = ValueKey<String>('panel-tab-tools');
const _canvasTabKey = ValueKey<String>('panel-tab-canvas');
const _brushesTabKey = ValueKey<String>('panel-tab-brushes');
const _brushSettingsTabKey = ValueKey<String>('panel-tab-brush-settings');
const _mediaTabKey = ValueKey<String>('panel-tab-media');
const _timelineTabKey = ValueKey<String>('timeline-mode-timeline-button');
const _storyboardTabKey = ValueKey<String>('timeline-mode-storyboard-button');
const _timesheetTabKey = ValueKey<String>('panel-tab-timesheet');
const _rightDropRailKey = ValueKey<String>('editor-dock-drop-rail-right');
const _toolRightRailKey = ValueKey<String>('editor-dock-drop-rail-tool-right');

Future<void> _pumpHome(WidgetTester tester) async {
  // R26 #31: the left dock ships with TWO stacked sections and the right
  // dock with the timesheet, so the 800×600 default test surface leaves
  // each section too short to lay out its panel (the media browser's
  // header + list overflowed by a few pixels). Use a window size a person
  // would actually work in.
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
  // Tabs always show [X][lock][name] now, and the test (Ahem) font draws
  // every glyph 12px wide — the three palette tabs need ~480px, far past
  // the default 260px dock. Widen the dock so every tab (and its drop
  // target) is hittable.
  // The R10-⑩ drag grips widen every tab a little further still (but
  // stay below the dock's max-width clamp — the splitter test measures
  // relative shrink from here).
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-left')),
    const Offset(370, 0),
  );
  await tester.pumpAndSettle();
}

/// R26 #31: the right dock ships OCCUPIED by the timesheet, so the
/// collapsed-dock behaviours (its drop rail) need it emptied first —
/// closing the sheet's tab is the shortest honest way there.
Future<void> _closeTimesheet(WidgetTester tester) async {
  final close = find.byKey(const ValueKey<String>('panel-close-timesheet'));
  await tester.ensureVisible(close);
  await tester.pumpAndSettle();
  await tester.tap(close);
  await tester.pumpAndSettle();
}

/// Drags a tab to a target by its GRIP handle (R10-⑩: only the grip
/// lifts a tab; the rest of the button is a plain tap target). The target
/// is a CLOSURE evaluated after the lift, because lifting reveals the
/// section split zones and shifts the strips down.
Finder _tabGrip(Finder tab) =>
    find.descendant(of: tab, matching: find.byIcon(Icons.drag_indicator));

Future<void> _dragTab(
  WidgetTester tester,
  Finder tab,
  Offset Function() target,
) async {
  // Tail tabs (media, onion) can sit past the strip's scroll edge.
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(tester.getCenter(_tabGrip(tab)));
  await tester.pump(const Duration(milliseconds: 20));
  // Clear the touch slop so the immediate drag wins the gesture arena.
  await gesture.moveBy(const Offset(0, 30));
  await tester.pump();
  final destination = target();
  await gesture.moveTo(destination + const Offset(0, -5));
  await tester.pump();
  await gesture.moveTo(destination);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('EditorWorkspace tool bar', () {
    testWidgets('a single tool bar homes in the left edge dock', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byType(ToolsPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-left')),
        findsOneWidget,
      );

      // 고정 도킹 (유저 확정): the tool strip has NO panel frame — no tab
      // name, no lock, no X, no grip. It holds one thing forever.
      expect(
        find.byKey(_toolsTabKey),
        findsNothing,
        reason: 'the tool strip carries no tab at all',
      );
      expect(
        find.byKey(const ValueKey<String>('panel-close-tools')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('panel-grip-tools')),
        findsNothing,
      );

      // …while an ordinary dock keeps its tabs: this is a strip-by-strip
      // decision, not a workspace-wide teardown.
      expect(find.byKey(_brushesTabKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('panel-close-brushes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('tool-brush-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('tool-eraser-button')),
        findsOneWidget,
      );
    });

    testWidgets('Settings moves the tool strip to the right edge', (
      tester,
    ) async {
      await _pumpHome(tester);

      // The strip has no grip to drag any more (고정 도킹), so the
      // left-handed choice is a switch in the Settings popover.
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey<String>('menu-window-tool-rail-right'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(ToolsPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-right')),
        findsOneWidget,
      );
      // The other strip does NOT vanish any more — it is the SUB-STRIP,
      // and it carries that side's panel-group buttons whether or not the
      // tools are on it. What the switch moves is the tool column.
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-left')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('editor-panel-dock-tool-right'),
          ),
          matching: find.byType(ToolsPanel),
        ),
        findsOneWidget,
      );
      // Tools stay usable on the right edge.
      await tester.tap(
        find.byKey(const ValueKey<String>('tool-eraser-button')),
      );
      await tester.pumpAndSettle();
      final toolsPanel = tester.widget<ToolsPanel>(find.byType(ToolsPanel));
      expect(toolsPanel.tool.name, 'eraser');
    });

    testWidgets('wide panels may not dock into the slim edge docks', (
      tester,
    ) async {
      await _pumpHome(tester);
      await _closeTimesheet(tester);

      // Lift a palette tab by its grip: the tool edge rails stay hidden
      // (ineligible), while the normal right dock's rail IS revealed.
      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(_tabGrip(find.byKey(_mediaTabKey))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      expect(find.byKey(_toolRightRailKey), findsNothing);
      expect(find.byKey(_rightDropRailKey), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('EditorWorkspace left dock tabs', () {
    testWidgets('shows the palette tabs with Brushes active, Tool Settings '
        'stacked underneath (R26 #31)', (tester) async {
      await _pumpHome(tester);

      expect(find.byKey(_brushesTabKey), findsOneWidget);
      expect(find.byKey(_brushSettingsTabKey), findsOneWidget);
      expect(find.byKey(_mediaTabKey), findsOneWidget);

      // Only the active tab of each SECTION is built — and Tool Settings
      // now owns its own section below the library, so both are open at
      // once (the pair a stroke alternates between).
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(BrushSettingsPanel), findsOneWidget);
      expect(find.byType(MediaBrowserPanel), findsNothing);
    });

    testWidgets('switching tabs swaps the visible panel', (tester) async {
      await _pumpHome(tester);

      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(BrushPresetPanel), findsNothing);
      // The section BELOW is untouched by its neighbour's tab switch.
      expect(find.byType(BrushSettingsPanel), findsOneWidget);

      await tester.ensureVisible(find.byKey(_brushesTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_brushesTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(MediaBrowserPanel), findsNothing);
    });
  });

  group('EditorWorkspace canvas panel', () {
    testWidgets('the canvas is the FLOOR: no tab strip, and nothing can '
        'drag it off', (tester) async {
      await _pumpHome(tester);

      expect(find.byType(EditorCanvasArea), findsOneWidget);
      // The floor has no tab of its own. It cannot: the panels lie ON it,
      // so a strip at its top-left corner would be under the left column.
      expect(find.byKey(_canvasTabKey), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel-lock-canvas')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('panel-close-canvas')),
          findsNothing);

      // Which is the protection, not a hole in it — there is no grip to
      // slip on, so the drawing surface cannot be dragged out from under
      // the app by accident. The lock glyph existed to say this.
      expect(find.byType(TimelinePanel), findsOneWidget);
    });

    testWidgets('the top strip switches what the app is lying on', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byType(EditorCanvasArea), findsOneWidget);
      expect(find.byType(MediaViewerTabHost), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-floor-media-viewer')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerTabHost), findsOneWidget);
      expect(find.byType(EditorCanvasArea), findsNothing);

      // The timeline never moved — it is floating on the floor, not
      // sharing a region with it.
      expect(find.byType(TimelinePanel), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-floor-canvas')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditorCanvasArea), findsOneWidget);
      expect(find.byType(MediaViewerTabHost), findsNothing);
    });
  });

  group('EditorWorkspace tab drag-docking', () {
    testWidgets('media tab re-docks into the bottom strip and back', (
      tester,
    ) async {
      await _pumpHome(tester);

      // Drop on the bottom strip's tail (right of the storyboard tab).
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () =>
            tester.getCenter(find.byKey(_storyboardTabKey)) +
            const Offset(150, 0),
      );

      // The media panel now renders in the bottom region as its active
      // tab; the left dock keeps Brushes active.
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(TimelinePanel), findsNothing);
      expect(find.byType(BrushPresetPanel), findsOneWidget);

      // Timeline is still reachable in the bottom group.
      await tester.tap(find.byKey(_timelineTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(TimelinePanel), findsOneWidget);
      expect(find.byType(MediaBrowserPanel), findsNothing);

      // Drag the media tab back to the left strip (tail after Settings).
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () =>
            tester.getCenter(find.byKey(_brushSettingsTabKey)) +
            const Offset(60, 0),
      );

      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(TimelinePanel), findsOneWidget);
    });

    testWidgets('dropping on the BELOW zone stacks a second panel', (
      tester,
    ) async {
      await _pumpHome(tester);

      // Lift the media tab; the overlay drop zones appear while it is in
      // flight. Drop on the left section's lower band.
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () => tester.getCenter(
          find.byKey(const ValueKey<String>('dock-drop-below-rail-L1-0')),
        ),
      );

      // Panel below panel: Brushes AND Camera visible at once, separated
      // by a draggable section splitter.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('dock-splitter-rail-L1-1')),
        findsOneWidget,
      );
    });

    testWidgets('the section splitter resizes stacked panels', (tester) async {
      await _pumpHome(tester);
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () => tester.getCenter(
          find.byKey(const ValueKey<String>('dock-drop-below-rail-L1-0')),
        ),
      );

      final splitter = find.byKey(
        const ValueKey<String>('dock-splitter-rail-L1-1'),
      );
      final beforeY = tester.getCenter(splitter).dy;

      await tester.drag(splitter, const Offset(0, -40));
      await tester.pumpAndSettle();

      expect(tester.getCenter(splitter).dy, lessThan(beforeY - 20));
    });

    testWidgets('the dock edge splitter resizes the left dock', (tester) async {
      await _pumpHome(tester);

      final splitter = find.byKey(const ValueKey<String>('dock-resize-left'));
      final dock = find.byKey(const ValueKey<String>('editor-panel-dock-left'));
      final beforeWidth = tester.getSize(dock).width;

      // A comfortable margin over the drag recognizer's touch slop: the
      // assertion is "the splitter shrinks the dock", not an exact delta.
      await tester.drag(splitter, const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(tester.getSize(dock).width, lessThan(beforeWidth - 40));
    });

    testWidgets('frame-axis tabs may dock into the side dock', (tester) async {
      await _pumpHome(tester);

      // Timeline into the left strip: allowed — the shell hosts it at its
      // minimum content size inside scrollers.
      await _dragTab(
        tester,
        find.byKey(_timelineTabKey),
        () => tester.getCenter(find.byKey(_mediaTabKey)) + const Offset(60, 0),
      );

      // Timeline renders in the side dock while the bottom region falls
      // back to the storyboard.
      expect(find.byType(TimelinePanel), findsOneWidget);
      expect(find.byType(StoryboardPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty right dock reveals a drop rail during a drag', (
      tester,
    ) async {
      await _pumpHome(tester);
      await _closeTimesheet(tester);
      expect(find.byKey(_rightDropRailKey), findsNothing);

      // Lift the media tab by its grip: the collapsed right dock shows
      // its rail.
      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(_tabGrip(find.byKey(_mediaTabKey))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.byKey(_rightDropRailKey), findsOneWidget);

      // Dropping there docks the media panel on the right.
      await gesture.moveTo(tester.getCenter(find.byKey(_rightDropRailKey)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(_rightDropRailKey), findsNothing);
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
        findsOneWidget,
      );
    });

    testWidgets('left strip tabs can be drag-reordered', (tester) async {
      await _pumpHome(tester);

      // Drop Brushes on the right half of the Media tab: order becomes
      // Settings, Media, Brushes.
      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      await _dragTab(
        tester,
        find.byKey(_brushesTabKey),
        () => Offset(
          tester.getTopRight(find.byKey(_mediaTabKey)).dx - 3,
          tester.getCenter(find.byKey(_mediaTabKey)).dy,
        ),
      );

      expect(
        tester.getCenter(find.byKey(_brushesTabKey)).dx,
        greaterThan(tester.getCenter(find.byKey(_mediaTabKey)).dx),
      );
      // Selection is untouched by reordering.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
    });
  });

  group('EditorWorkspace panel close + Panels menu', () {
    testWidgets('the X on a tab closes the panel; the menu reopens it', (
      tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byType(BrushPresetPanel), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('panel-close-brushes')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_brushesTabKey), findsNothing);
      expect(find.byType(BrushPresetPanel), findsNothing);
      // The neighbouring tab takes over the section.
      expect(find.byType(BrushSettingsPanel), findsOneWidget);

      // Reopen from the Settings popover, which absorbed the Window menu
      // (and kept the retired Panels menu's item keys).
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('panels-menu-item-brushes')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_brushesTabKey), findsOneWidget);
    });

    testWidgets('locked tabs keep the X visible but INERT — locking never '
        'reshapes the tab (R12-⑨)', (tester) async {
      await _pumpHome(tester);

      // The canvas used to be this test's subject, and it cannot be any
      // more — the floor has no strip at all now, which is a stronger
      // statement than "locked" and is pinned by its own test. So the law
      // is checked where a strip still exists: any tab, locked by hand.
      final lockSheet = find.byKey(
        const ValueKey<String>('panel-lock-timesheet'),
      );
      final closeSheet = find.byKey(
        const ValueKey<String>('panel-close-timesheet'),
      );

      await tester.ensureVisible(lockSheet);
      await tester.pumpAndSettle();
      await tester.tap(lockSheet);
      await tester.pumpAndSettle();

      // Locked: the X is still there…
      expect(closeSheet, findsOneWidget);
      // …and the grip too (visible, inert).
      expect(
        find.byKey(const ValueKey<String>('panel-grip-timesheet')),
        findsOneWidget,
      );

      // Ahem-wide labels push the X past the strip's scroll clip in
      // tests — bring it into view before tapping.
      await tester.ensureVisible(closeSheet);
      await tester.pumpAndSettle();

      // Tapping the dead X does nothing (and doesn't select-toggle).
      await tester.tap(closeSheet);
      await tester.pumpAndSettle();
      expect(find.byKey(_timesheetTabKey), findsOneWidget);

      // Unlocking arms it: now the X closes the panel.
      await tester.ensureVisible(lockSheet);
      await tester.pumpAndSettle();
      await tester.tap(lockSheet);
      await tester.pumpAndSettle();
      await tester.ensureVisible(closeSheet);
      await tester.pumpAndSettle();
      await tester.tap(closeSheet);
      await tester.pumpAndSettle();
      expect(find.byKey(_timesheetTabKey), findsNothing);
    });
  });

  group('EditorWorkspace bottom tabs', () {
    testWidgets('keeps the legacy timeline/storyboard toggle keys working', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byType(TimelinePanel), findsOneWidget);
      expect(find.byType(StoryboardPanel), findsNothing);

      await tester.tap(find.byKey(_storyboardTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(StoryboardPanel), findsOneWidget);
      expect(find.byType(TimelinePanel), findsNothing);

      await tester.tap(find.byKey(_timelineTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(TimelinePanel), findsOneWidget);
    });
  });

  group('EditorWorkspace timesheet tab', () {
    // R26 #31: the sheet ships open in the right dock — 'opening' it is
    // just pumping the workspace now.
    Future<void> openTimesheet(WidgetTester tester) async {
      await _pumpHome(tester);
    }

    testWidgets('ships docked on the right, alongside the timeline rather '
        'than instead of it (R26 #31)', (tester) async {
      await openTimesheet(tester);

      expect(
        find.byKey(const ValueKey<String>('timesheet-document-paint')),
        findsOneWidget,
      );
      expect(find.byKey(_timesheetTabKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
        findsOneWidget,
      );
      // Both frame views are up at once now — the sheet no longer takes
      // the bottom strip's turn.
      expect(find.byType(TimelinePanel), findsOneWidget);
      // 법: 뷰 컨트롤은 바닥에만 (유저 확정). A canvas host that is NOT the
      // app's floor carries its two panbars and nothing else — Fit and the
      // zoom cluster belong to the surface the app is lying on, and the
      // sheet is a page you read beside the drawing.
      expect(
        find.descendant(
          of: find.byType(TimesheetTabHost),
          matching: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(TimesheetTabHost),
          matching: find.byType(CanvasViewportHorizontalScrollbar),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(TimesheetTabHost),
          matching: find.byType(CanvasViewportVerticalScrollbar),
        ),
        findsWidgets,
      );
    });

    testWidgets('page mode toggle flips paged and continuous views', (
      tester,
    ) async {
      await openTimesheet(tester);

      // Paged by default — the toggle offers the continuous view.
      expect(find.byTooltip('Continuous View'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-page-mode-toggle-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Page View'), findsOneWidget);
    });

    testWidgets('sheet info dialog edits the project timesheet info', (
      tester,
    ) async {
      late ProjectRepository repository;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(onRepositoryCreated: (repo) => repository = repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_timesheetTabKey));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-info-button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('timesheet-info-title-field')),
        'YOASOBI',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('timesheet-info-episode-field')),
        'MV',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('timesheet-info-artist-field')),
        'MYOUN',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('timesheet-info-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        repository.requireProject().timesheetInfo,
        const TimesheetInfo(title: 'YOASOBI', episode: 'MV', artist: 'MYOUN'),
      );
    });

    testWidgets('sheet viewport zoom survives workspace rebuilds (the sheet '
        'owns the right dock now, so the neighbours switch instead)', (
      tester,
    ) async {
      await openTimesheet(tester);

      // The zoom BUTTONS are gone from a non-floor host (뷰 컨트롤은 바닥에만),
      // so the viewport is read and driven through the panbar the host does
      // still carry — which is the thing whose survival this test is about.
      CanvasViewportVerticalScrollbar panbar() =>
          tester.widgetList<CanvasViewportVerticalScrollbar>(
            find.descendant(
              of: find.byType(TimesheetTabHost),
              matching: find.byType(CanvasViewportVerticalScrollbar),
            ),
          ).first;

      expect(panbar().viewport.zoom, 1.0);
      panbar().onViewportChanged(panbar().viewport.copyWith(zoom: 1.75));
      await tester.pumpAndSettle();
      expect(panbar().viewport.zoom, 1.75);

      await tester.tap(find.byKey(_timelineTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_storyboardTabKey));
      await tester.pumpAndSettle();

      expect(panbar().viewport.zoom, 1.75);
    });
  });
}
