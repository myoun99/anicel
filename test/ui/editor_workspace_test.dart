import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
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
    find.byKey(const ValueKey<String>('dock-resize-rail-L1')),
    const Offset(370, 0),
  );
  await tester.pumpAndSettle();
}

/// The MEDIA browser has its own sub-strip button now and ships CLOSED
/// (유저, R3 #10) — it used to be a tab of the left rail's one group. Tests
/// about tab mechanics still want its tab, so they open its group first.
Future<void> _openMedia(WidgetTester tester) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 3)}',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Empties the RIGHT rail. Four groups live there now (colour, the paper
/// sheets, media, onion) and only the SHEETS ship open — so closing that
/// one button empties the column, and a collapsed-rail behaviour needs the
/// whole column rather than one panel hidden.
Future<void> _closeRightRail(WidgetTester tester) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 2)}',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Flips one panel's visibility through the Panels list.
///
/// The tab's X went with the rest of the panel frame (패널 프레임 최소화),
/// so this list is the switch — in both directions, and for the floor's
/// panels it is the ONLY switch (the floor draws no tab strip at all).
Future<void> _togglePanel(WidgetTester tester, String tabId) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('top-strip-settings-button')),
  );
  await tester.pumpAndSettle();
  final entry = find.byKey(ValueKey<String>('panels-menu-item-$tabId'));
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// R26 #31: the right dock ships OCCUPIED by the timesheet, so the
/// collapsed-dock behaviours (its drop rail) need it emptied first —
/// closing the sheet's tab is the shortest honest way there.
Future<void> _closeTimesheet(WidgetTester tester) =>
    _togglePanel(tester, 'timesheet');

/// Drags a tab to a target by its GRIP handle (R10-⑩: only the grip
/// lifts a tab; the rest of the button is a plain tap target). The target
/// is a CLOSURE evaluated after the lift, because lifting reveals the
/// section split zones and shifts the strips down.
/// The lift zone — an 8px strip of the tab's leading edge, found by KEY
/// now that it is not a glyph.
Finder _tabGrip(Finder tab) => find.descendant(
  of: tab,
  matching: find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('panel-grip-');
  }),
);

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
  // SIDEWAYS, not down: the 문턱 sits on the region's bottom inner edge, so
  // a downward nudge from a tab there leaves the window entirely and the
  // lift never happens. A strip is horizontal wherever it is docked.
  await gesture.moveBy(const Offset(30, 0));
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
      // decision, not a workspace-wide teardown. What a tab carries is one
      // glyph and its lift zone now — 패널 프레임 최소화 took the name, the
      // lock and the X, and the settings list is the way to close.
      expect(find.byKey(_brushesTabKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('panel-grip-brushes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('panel-close-brushes')),
        findsNothing,
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
      await _closeRightRail(tester);

      // Lift a palette tab by its grip: the TOOL edge rail stays hidden,
      // because a 48px strip of buttons cannot hold a panel and saying so
      // with a band would be an offer that fails on release.
      await tester.ensureVisible(find.byKey(_brushesTabKey));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(_tabGrip(find.byKey(_brushesTabKey))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      expect(find.byKey(_toolRightRailKey), findsNothing);
      // ⛔And neither does the closed panel rail beside it (유저, R4 #7) —
      // eligible or not, no side rail draws a band any more. Where the panel
      // CAN go is covered by the strip-button test above.
      expect(find.byKey(_rightDropRailKey), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('EditorWorkspace tool library', () {
    // TS3: 유저 — "라소 컷 골랐는데도 ui는 사각형컷을 가리키고있음. 동작
    // 자체는 라소컷으로 잘 작동하는데. 이거는 채우기툴쪽도 똑같은거 보니
    // 공통로직 손봐야할듯."
    //
    // The tap always worked (the callback reads the live state), so this
    // has to assert on what the TILE says, not on what the tool does. The
    // library lives inside a per-tool keep-alive stack whose cache key was
    // the active PRESET alone — null for every drag-out verb, for ever — so
    // the state changed, the builder ran, the cache answered and the panel
    // that came back was the one built with the rectangle.
    Future<bool> tileSelected(WidgetTester tester, String key) async {
      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(ListTile),
          matchRoot: true,
        ),
      );
      return tile.selected;
    }

    testWidgets('the highlighted shape tile follows the shape that was picked', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      await tester.pumpAndSettle();

      expect(await tileSelected(tester, 'sub-tool-cut-rect'), isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-lasso')));
      await tester.pumpAndSettle();

      expect(
        await tileSelected(tester, 'sub-tool-cut-lasso'),
        isTrue,
        reason: 'the picked outline is the one highlighted',
      );
      expect(
        await tileSelected(tester, 'sub-tool-cut-rect'),
        isFalse,
        reason: 'and the old one lets go',
      );
    });

    testWidgets('the fill tiles follow too — it was one cache, not one tool', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      await tester.pumpAndSettle();

      // Enter the shape verb FIRST. Coming from the bucket is a different
      // keep-alive key, so that hop builds cold and would pass either way —
      // the staleness only shows when the shape changes with the verb
      // already active, which is exactly how a person uses it.
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-fill-rect')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-fill-polygon')),
      );
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-fill-polygon'), isTrue);
      expect(await tileSelected(tester, 'sub-tool-fill-rect'), isFalse);

      // Away to another tool and back: the Fill button re-enters on the
      // TILE it was left on (유저 2026-08-15 — "필 툴은 아직도 다른 툴
      // 이동하면 모드 선택한게 초기화됨"). It used to land on the bucket,
      // which threw the choice away every time a hand reached for the
      // brush.
      await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-fill-polygon'), isTrue);
      expect(await tileSelected(tester, 'sub-tool-fill-bucket'), isFalse);

      // …and the cached panel still tells the truth when the tile changes
      // with the fill already active, which is the staleness this test was
      // written for. Picking the bucket by hand moves the highlight.
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-fill-bucket')),
      );
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-fill-bucket'), isTrue);
      expect(await tileSelected(tester, 'sub-tool-fill-polygon'), isFalse);

      // The memory is the LAST tile either way, not a preference for the
      // shapes: leaving on the bucket comes back on the bucket.
      await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-fill-bucket'), isTrue);

      // …and the outline itself was remembered all along: re-entering the
      // shape verb lands back on the polygon, not on the rectangle.
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-fill-polygon')),
      );
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-fill-polygon'), isTrue);
    });

    testWidgets('the cut button comes back to the GRAB, never to the stamp', (
      tester,
    ) async {
      // 유저 확정 2026-08-15: "찍기는 아예 성질이 다른거니까 그 외만
      // 기억하도록." The fill's two tiles are two ways of choosing an area,
      // so picking one is a setting worth keeping; the stamp is not a way
      // of cutting at all, and it arms itself on a fresh cut.
      await _pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-lasso')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-stamp')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-cut-stamp'), isTrue);

      // Pressing the button while the stamp is armed leaves it alone — the
      // older half of the rule, and the reason the two halves are apart.
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-cut-stamp'), isTrue);

      // Away and back: the tile from BEFORE the stamp is what waited, still
      // wearing the lasso.
      await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-cut-stamp'), isFalse);
      expect(await tileSelected(tester, 'sub-tool-cut-lasso'), isTrue);
    });

    // TS2: 유저 — "잘라내고 나면 찍기로 모드전환".
    //
    // Driven through the SLOT rather than through a cut drag, because the
    // slot is where the workspace listens and it is the honest boundary:
    // the rule is "something is being held now", and the cut gesture is
    // covered where it lives (cut_tool_drag_test).
    testWidgets('a fresh cut arms the stamp; posing what is held does not', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey<String>('tool-cut-button')));
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-cut-stamp'), isFalse);

      // The canvas panel is always mounted and carries the workspace's own
      // slot, so this is the real object the cut gesture would fill.
      final slot = tester
          .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel).first)
          .cutPieceSlot!;
      slot.hold(
        CutPiece(
          image: BrushStampImage(
            id: 'cut-1',
            width: 4,
            height: 4,
            rgba: Uint8List(4 * 4 * 4),
          ),
          originLeft: 0,
          originTop: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        await tileSelected(tester, 'sub-tool-cut-stamp'),
        isTrue,
        reason: 'holding something arms the tool that puts it down',
      );

      // Back to the grab tile, then nudge the POSE: the slot notifies for
      // that too, and taking it for a fresh cut would yank the tool out from
      // under the hand.
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-rect')));
      await tester.pumpAndSettle();
      slot.updatePose(scalePercent: 150);
      await tester.pumpAndSettle();
      expect(await tileSelected(tester, 'sub-tool-cut-stamp'), isFalse);
      expect(await tileSelected(tester, 'sub-tool-cut-rect'), isTrue);
    });
  });

  group('EditorWorkspace left dock tabs', () {
    testWidgets('one panel per BUTTON — the library and the settings are two '
        'of them, not two tabs of one', (tester) async {
      // 유저, R3 #10. They were the same button until this round, which
      // meant reaching the settings mid-stroke cost a tab switch that also
      // put the library away.
      await _pumpHome(tester);

      expect(find.byKey(_brushesTabKey), findsOneWidget);
      expect(find.byType(BrushPresetPanel), findsOneWidget);

      // The settings have their own slot under it, and it ships closed.
      final settingsGroup = EditorWorkspace.railGroupId(right: false, slot: 2);
      expect(
        find.byKey(ValueKey<String>('rail-group-$settingsGroup')),
        findsOneWidget,
      );
      expect(find.byType(BrushSettingsPanel), findsNothing);
      // …and the media browser is not on this rail at all any more.
      expect(find.byKey(_mediaTabKey), findsNothing);

      await tester.tap(
        find.byKey(ValueKey<String>('rail-group-$settingsGroup')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BrushSettingsPanel), findsOneWidget);
      expect(
        find.byType(BrushPresetPanel),
        findsOneWidget,
        reason: 'opening one does not put the other away',
      );
    });

    testWidgets('switching tabs swaps the visible panel', (tester) async {
      await _pumpHome(tester);
      await _openMedia(tester);

      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowserPanel), findsOneWidget);

      // Drag the library's tab into the media group and the strip switches
      // between them the way one group's strip always has.
      await _dragTab(
        tester,
        find.byKey(_brushesTabKey),
        () => tester.getCenter(find.byKey(_mediaTabKey)) + const Offset(60, 0),
      );
      expect(find.byType(BrushPresetPanel), findsOneWidget);

      await tester.ensureVisible(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_mediaTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(BrushPresetPanel), findsNothing);
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
      expect(
        find.byKey(const ValueKey<String>('panel-lock-canvas')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('panel-close-canvas')),
        findsNothing,
      );

      // Which is the protection, not a hole in it — there is no grip to
      // slip on, so the drawing surface cannot be dragged out from under
      // the app by accident. The lock glyph existed to say this.
      expect(find.byType(TimelinePanel), findsOneWidget);
    });

    testWidgets('the stage is a place entrance, covering all of it', (
      tester,
    ) async {
      await _pumpHome(tester);

      // §7: a pool row can be dropped on the stage. The entrance is a
      // permanent slot over the canvas rather than something mounted while
      // a drag runs — the canvas is a GlobalKey subtree, and re-parenting
      // it mid-drag would tear it down. That it takes no pointer while it
      // sits there is [MediaAssetDropTarget]'s own suite.
      final entrance = find.byKey(const ValueKey<String>('canvas-asset-drop'));
      expect(entrance, findsOneWidget);
      expect(
        tester.getRect(entrance),
        tester.getRect(find.byType(EditorCanvasArea)),
        reason: 'the whole drawing surface, not a corner of it',
      );
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

    testWidgets('a panel that ends up on the floor keeps a way back', (
      tester,
    ) async {
      // The floor is the one dock with NO tab strip, so a panel down there
      // has no button on itself — and the Panels list reports it as OPEN,
      // which means the only thing that list offers is closing it. The
      // switch listing whatever is actually on the floor is the way back.
      await _pumpHome(tester);

      // Emptying the floor is what makes its drop zone appear; the Panels
      // list is the only way to do it (no X on a chromeless dock).
      await _togglePanel(tester, 'canvas');
      await _togglePanel(tester, 'media-viewer');
      expect(find.byType(EditorCanvasArea), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('top-strip-floor-timesheet')),
        findsNothing,
        reason: 'nothing is on the floor yet',
      );

      await _dragTab(
        tester,
        find.byKey(_timesheetTabKey),
        () => tester.getCenter(
          find.byKey(const ValueKey<String>('editor-dock-drop-rail-center')),
        ),
      );
      expect(find.byType(TimesheetTabHost), findsOneWidget);

      // It is on the floor, so the switch offers it — after the two homes,
      // which stay listed whatever is down there.
      final timesheetFloorButton = find.byKey(
        const ValueKey<String>('top-strip-floor-timesheet'),
      );
      expect(timesheetFloorButton, findsOneWidget);

      // Fetch a home back: the sheet is now BEHIND the canvas with nothing
      // of its own on screen. This is the state that used to be a dead end.
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-floor-canvas')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditorCanvasArea), findsOneWidget);
      expect(find.byType(TimesheetTabHost), findsNothing);

      // And back again — the button is still there, and it works.
      expect(timesheetFloorButton, findsOneWidget);
      await tester.tap(timesheetFloorButton);
      await tester.pumpAndSettle();
      expect(find.byType(TimesheetTabHost), findsOneWidget);
      expect(find.byType(EditorCanvasArea), findsNothing);
    });
  });

  group('EditorWorkspace tab drag-docking', () {
    testWidgets('media tab re-docks into the bottom strip and back', (
      tester,
    ) async {
      await _pumpHome(tester);
      await _openMedia(tester);

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

      // Drag the media tab back to the left strip (tail after the library).
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () =>
            tester.getCenter(find.byKey(_brushesTabKey)) + const Offset(60, 0),
      );

      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(TimelinePanel), findsOneWidget);
    });

    testWidgets('the dock edge splitter resizes the left dock', (tester) async {
      await _pumpHome(tester);

      final splitter = find.byKey(
        const ValueKey<String>('dock-resize-rail-L1'),
      );
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
      // The strip's TAIL — tabs are one glyph wide now, so a fixed offset
      // from a neighbour's centre no longer lands anywhere in particular.
      await _dragTab(tester, find.byKey(_timelineTabKey), () {
        final strip = tester.getRect(
          find.byKey(const ValueKey<String>('editor-panel-dock-left')),
        );
        return Offset(strip.right - 40, strip.top + 15);
      });
      // Timeline renders in the side dock while the bottom region falls
      // back to the storyboard.
      expect(find.byType(TimelinePanel), findsOneWidget);
      expect(find.byType(StoryboardPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a CLOSED side rail raises NO band — the strip button is the '
        'door, and it is the only one', (tester) async {
      // 유저, R4 #7. A tall drop band used to appear beside a closed rail
      // whenever a tab lifted, and it did exactly what the rail's own strip
      // button already does. Two doors onto one room, one of them a third of
      // the window tall.
      //
      // ⛔This is a CONTRACT CHANGE, not a regression: the old shape of this
      // test (lift → band appears → drop on band) asserted the door that was
      // removed. What has to stay true is that the panel can still get
      // there, which is what the second half checks.
      await _pumpHome(tester);
      await _closeRightRail(tester);
      expect(find.byKey(_rightDropRailKey), findsNothing);

      await tester.ensureVisible(find.byKey(_brushesTabKey));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(_tabGrip(find.byKey(_brushesTabKey))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(
        find.byKey(_rightDropRailKey),
        findsNothing,
        reason: 'lifting a tab must not open a band beside the closed rail',
      );

      // The button is still a target, and dropping on it both docks the
      // panel AND opens the group — 「두는 것은 여는 것」.
      final railButton = find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 2)}',
        ),
      );
      await gesture.moveTo(tester.getCenter(railButton));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
        findsOneWidget,
      );
    });

    testWidgets('left strip tabs can be drag-reordered', (tester) async {
      await _pumpHome(tester);
      await _openMedia(tester);
      // Put them in one group first — reordering is a thing a strip does,
      // and one panel per button means a strip has to be built to have one.
      await _dragTab(
        tester,
        find.byKey(_mediaTabKey),
        () =>
            tester.getCenter(find.byKey(_brushesTabKey)) + const Offset(60, 0),
      );

      // Drop Brushes on the right half of the Media tab: the order flips.
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
      // Selection is untouched by reordering — the media browser was the
      // group's open panel before the drag and still is.
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      expect(find.byType(BrushPresetPanel), findsNothing);
    });
  });

  group('EditorWorkspace panel close + Panels menu', () {
    testWidgets('the tab carries ONE glyph and its lift zone — closing is '
        'the settings list, in both directions', (tester) async {
      await _pumpHome(tester);

      // 패널 프레임 최소화 (유저 확정): no name, no lock, no X. The label is
      // the tooltip, which was always the tab's only accessibility name.
      for (final id in ['brushes', 'timesheet', 'conte']) {
        expect(find.byKey(ValueKey<String>('panel-close-$id')), findsNothing);
        expect(find.byKey(ValueKey<String>('panel-lock-$id')), findsNothing);
        expect(
          find.byKey(ValueKey<String>('panel-grip-$id')),
          findsOneWidget,
          reason: 'the lift zone survives — S4 drags panels by it',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(_brushesTabKey),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'no name on the button',
      );

      // The settings list closes AND reopens — one switch, both ways.
      await _closeTimesheet(tester);
      expect(find.byKey(_timesheetTabKey), findsNothing);
      await _closeTimesheet(tester);
      expect(find.byKey(_timesheetTabKey), findsOneWidget);
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
      // R2 #13: it has a pill of its own now, Fit and all — a page you
      // read is a page you zoom.
      expect(
        find.descendant(
          of: find.byType(TimesheetTabHost),
          matching: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        ),
        findsOneWidget,
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
      CanvasViewportVerticalScrollbar panbar() => tester
          .widgetList<CanvasViewportVerticalScrollbar>(
            find.descendant(
              of: find.byType(TimesheetTabHost),
              matching: find.byType(CanvasViewportVerticalScrollbar),
            ),
          )
          .first;

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

  testWidgets('the OS memory-pressure signal reaches the session through '
      'the workspace observer — driven as the REAL system channel message, '
      'not a direct method call', (tester) async {
    await _pumpHome(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.brushFrameStore.hotCelByteBudget = 1024 * 1024 * 1024;

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.system.name,
          SystemChannels.system.codec.encodeMessage(
            const <String, dynamic>{'type': 'memoryPressure'},
          ),
          (_) {},
        );

    expect(
      session.brushFrameStore.hotCelByteBudget,
      512 * 1024 * 1024,
      reason: 'addObserver + didHaveMemoryPressure + the session forward '
          'must all hold for the halving to land',
    );
  });
}
