import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/superellipse_clip.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/color/color_slot_pair.dart';
import 'package:anicel/src/ui/color/color_status_bar.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../helpers/panel_finders.dart';

/// A rail button is a GROUP of panels, and the rail is a column of them.
///
/// The docks were a fixed left one and a fixed right one; now each side has
/// a POOL of group slots, a button per occupied slot, and a column showing
/// whichever groups are open. Three things carry the design: several groups
/// can be open at once and divide the rail's height, the rail has ONE width
/// that all of them share, and a panel dragged onto a button joins that
/// group.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Finder groupButton(String railId) =>
      find.byKey(ValueKey<String>('rail-group-$railId'));

  group('the strips', () {
    testWidgets('BOTH exist — the sub-strip is no longer a 0px dock', (
      tester,
    ) async {
      await pumpApp(tester);

      final left = find.byKey(
        const ValueKey<String>('editor-panel-dock-tool-left'),
      );
      final right = find.byKey(
        const ValueKey<String>('editor-panel-dock-tool-right'),
      );
      expect(left, findsOneWidget);
      expect(right, findsOneWidget);
      expect(tester.getRect(left).width, ToolsPanel.dockWidth);
      expect(tester.getRect(right).width, ToolsPanel.dockWidth);

      // The tool column is on ONE of them; the other carries only its
      // side's group buttons.
      expect(
        find.descendant(of: left, matching: find.byType(ToolsPanel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: right, matching: find.byType(ToolsPanel)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: right,
          matching: groupButton(EditorWorkspace.rightGroupId),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a button exists for each OCCUPIED slot and no others', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(groupButton(EditorWorkspace.leftGroupId), findsOneWidget);
      expect(groupButton(EditorWorkspace.rightGroupId), findsOneWidget);
      // The tool settings hold the left rail's second slot (유저, R3 #10),
      // so that one is a button too — and it is a button whether or not its
      // group is open.
      expect(
        groupButton(EditorWorkspace.railGroupId(right: false, slot: 2)),
        findsOneWidget,
      );
      // An empty slot is not a button you can press — it appears only as a
      // drop target, and only while something is in flight.
      expect(
        groupButton(EditorWorkspace.railGroupId(right: false, slot: 3)),
        findsNothing,
      );
    });

    testWidgets('both strips fill from the TOP — the tool column does not '
        'push its group buttons to the far end', (tester) async {
      await pumpApp(tester);

      final leftStrip = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-left')),
      );
      final tools = tester.getRect(
        find.byKey(const ValueKey<String>('tools-panel')),
      );
      final leftButton = tester.getRect(
        groupButton(EditorWorkspace.leftGroupId),
      );
      final rightButton = tester.getRect(
        groupButton(EditorWorkspace.rightGroupId),
      );

      // The sub-strip has always started at the top; the tool strip's
      // buttons used to sit ~460px lower, because the tool column was
      // handed the strip's whole spare height and the buttons took what
      // was left at the bottom.
      expect(rightButton.top - leftStrip.top, lessThan(16));
      expect(
        leftButton.top - tools.bottom,
        // The rule between the tools and the panel buttons costs 17 of this
        // (유저, R3 #15) — 8 above, the hairline, 8 below — and the button
        // column's own top padding the rest. "Immediately" means one seam,
        // not no gap.
        lessThan(32),
        reason: 'the group buttons follow the tools immediately',
      );
      expect(leftButton.bottom, lessThan(leftStrip.bottom - 100));
    });

    testWidgets('a strip button has NO grip — the panel it opens carries the '
        'only one', (tester) async {
      // R1 gave every strip button an 8px lift zone. Nothing was wired to
      // it: it painted, it took the grab cursor, and dragging it moved
      // nothing. 유저 정정 — the button is a switch, the tab is the handle.
      await pumpApp(tester);

      expect(
        find.byKey(
          ValueKey<String>(
            'rail-grip-rail-group-${EditorWorkspace.leftGroupId}',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-grip-tool-brush-button')),
        findsNothing,
      );
    });
  });

  group('the colour group', () {
    Color swatchColor(WidgetTester tester, String key) {
      final container = tester.widget<Container>(
        find.byKey(ValueKey<String>(key)),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    testWidgets('its BUTTON is the dual swatch — the two colours you paint '
        'with are readable without opening anything', (tester) async {
      await pumpApp(tester);

      expect(
        find.byKey(const ValueKey<String>('tool-color-button')),
        findsOneWidget,
      );
      expect(swatchColor(tester, 'tool-color-foreground-swatch'), isNotNull);
      // …and it is exactly the rail's button cell.
      expect(ColorSlotPair.extent, ToolsPanel.buttonExtent);
    });

    testWidgets('there is NO swap glyph — the back slot already is one', (
      tester,
    ) async {
      // 유저 확정, 두 번: a separate swap button says the same verb the pair
      // already says by being a pair. This guards the glyph from growing
      // back where the swatch now lives.
      await pumpApp(tester);

      expect(
        find.byKey(const ValueKey<String>('tool-color-swap-button')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tool-color-button')),
          matching: find.byIcon(Icons.swap_horiz),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping the background slot swaps', (tester) async {
      await pumpApp(tester);

      final before = swatchColor(tester, 'tool-color-foreground-swatch');
      final behind = swatchColor(tester, 'tool-color-background-swatch');
      expect(before, isNot(behind));

      await tester.tap(
        find.byKey(const ValueKey<String>('tool-color-background-swatch')),
      );
      await tester.pumpAndSettle();

      expect(swatchColor(tester, 'tool-color-foreground-swatch'), behind);
      expect(swatchColor(tester, 'tool-color-background-swatch'), before);
    });

    testWidgets('the wheel, the RGB bars and the palette are three PANELS '
        'of the group, not tabs inside one', (tester) async {
      // A strip inside a strip asked "which panel" and "how am I picking"
      // in the same place twice (유저, R2 #8).
      await pumpApp(tester);
      await tester.tap(groupButton(EditorWorkspace.rightGroupId));
      await tester.pumpAndSettle();

      for (final id in ['color-wheel', 'color-rgb', 'color-palette']) {
        expect(
          find.byKey(ValueKey<String>('panel-tab-$id')),
          findsOneWidget,
          reason: '$id is a tab of the rail group',
        );
      }
      // The group's strip is the ONLY strip in it: no second row of icons
      // belonging to the thing inside.
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.byKey(const ValueKey<String>('panel-tab-color-wheel')),
                matching: find.byType(EditorPanelTabs),
              )
              .first,
          matching: find.byType(EditorPanelTabs),
        ),
        findsNothing,
      );
      // Every colour panel carries the same reading underneath.
      expect(find.byType(ColorStatusBar), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('panel-tab-color-rgb')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ColorStatusBar), findsOneWidget);
    });
  });

  group('open and closed', () {
    testWidgets('the button closes its group and opens it again', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.byType(TimesheetTabHost), findsOneWidget);
      final sheetGroup = EditorWorkspace.railGroupId(right: true, slot: 2);
      final railWidth = tester
          .getRect(
            find.byKey(const ValueKey<String>('editor-panel-dock-right')),
          )
          .width;
      expect(railWidth, greaterThan(0));

      await tester.tap(groupButton(sheetGroup));
      await tester.pumpAndSettle();
      expect(find.byType(TimesheetTabHost), findsNothing);
      // The rail's column is gone, so the drawing gets the width back.
      expect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
        findsNothing,
      );
      // …and the BUTTON is still there. Closing a group is not closing the
      // panels: the grouping survives, which is the whole point of a fixed
      // slot pool.
      expect(groupButton(sheetGroup), findsOneWidget);

      await tester.tap(groupButton(sheetGroup));
      await tester.pumpAndSettle();
      expect(find.byType(TimesheetTabHost), findsOneWidget);
    });

    testWidgets('a second group FLOATS below the first — it does not resize '
        'it — and they share ONE width', (tester) async {
      await pumpApp(tester);

      final beforeLibrary = tester.getRect(find.byType(BrushPresetPanel));

      // The tool SETTINGS are the left rail's second group now (유저, R3
      // #10) — one button under the library's, closed until pressed.
      await tester.tap(
        groupButton(EditorWorkspace.railGroupId(right: false, slot: 2)),
      );
      await tester.pumpAndSettle();

      // Both groups are open and both are on screen.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(BrushSettingsPanel), findsOneWidget);
      final library = tester.getRect(find.byType(BrushPresetPanel));
      final media = tester.getRect(find.byType(BrushSettingsPanel));
      expect(
        media.top,
        greaterThan(library.bottom),
        reason: 'the new group floats below, with pasteboard between them',
      );
      // ★A group KEEPS ITS HEIGHT (유저 확정). The rail used to divide its
      // height between whatever was open, so opening a second panel
      // resized the first — a column's behaviour, not a floating panel's.
      expect(
        library.height,
        closeTo(beforeLibrary.height, 0.5),
        reason: 'opening a neighbour must not resize this panel',
      );
      // 레일당 폭 하나: the two groups are exactly as wide as each other.
      expect(media.width, closeTo(library.width, 0.5));

      // And widening the rail widens BOTH, because there is one splitter
      // and one number behind it.
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-L1')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      final grownLibrary = tester.getRect(find.byType(BrushPresetPanel));
      final grownMedia = tester.getRect(find.byType(BrushSettingsPanel));
      expect(grownLibrary.width, greaterThan(library.width));
      expect(grownMedia.width, closeTo(grownLibrary.width, 0.5));
    });

    testWidgets('the height grip banks nothing: dragging back moves the edge '
        'by exactly what the cursor moved', (tester) async {
      // The same defect this round fixed for the floating region, missed on
      // the grip it added: with no ceiling the stored height climbed past
      // what the rail could ever show, and the drag back spent that surplus
      // before the edge moved at all. Measured before: 60px of return
      // travel moved the edge 9px.
      await pumpApp(tester);
      final grip = find.byKey(
        const ValueKey<String>('dock-resize-rail-L1-height'),
      );

      await tester.drag(grip, const Offset(0, 600));
      await tester.pumpAndSettle();
      final atCeiling = tester.getRect(grip).top;

      await tester.drag(grip, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(atCeiling - tester.getRect(grip).top, closeTo(60, 0.5));
    });

    testWidgets('where the pill and the vertical scrollbar overlap, the PILL '
        'takes the pointer', (tester) async {
      // The bar centres on the panel's whole height, so on a SHORT panel its
      // middle reaches the pill's row. It used to be stacked AFTER the
      // controls and took the pointer aimed at the pill's last control. One
      // of them has to lose it there, and it is the bar: 28px out of a long
      // target, against a whole button. (Reserving the lane instead was
      // measured and rejected — 22px is enough to make the timesheet shed
      // its own page cluster at the default rail width.)
      await pumpApp(tester);
      // NARROW as well as short. The pill is CENTRED and the bar rides the
      // right edge, so the two meet only where the pill nearly fills the
      // panel — and 유저 확정 2026-08-13 took the zoom steps, 1:1, rotate,
      // flip and the swatches out of the pill, so it no longer does at the
      // default rail width (measured: they miss by 18px there).
      //
      // ⚠️MEASURED and thin: at 220px the two overlap by 2px, and the pill
      // sheds its host controls below 218px, so the band this fixture lives
      // in is a handful of pixels wide. That is a property of the geometry
      // — a centred capsule and an edge-riding bar only meet at the edge of
      // shedding — not of this drag. If a constant moves, the liveness
      // check below fails LOUDLY with "must actually reach the overlapping
      // case" rather than passing on a case it never reached; re-measure
      // and move the number.
      // ⚠️MEASURED at runtime rather than a fixed delta. It used to be +40
      // from a 260 default; D37 opens the rail at a fraction of the window,
      // so that delta landed on 248 and the case stopped reaching the
      // overlap it is named for. Subtracting from the measured width is the
      // same instruction the note above gives — "re-measure and move the
      // number" — carried out by the test, so the next default change
      // cannot quietly empty this case.
      //
      // ⛔The sign: a RIGHT rail grows as the pointer moves LEFT, so a
      // positive dx shrinks it.
      const overlappingWidth = 220.0;
      final railWidth = tester
          .getRect(
            find.byKey(const ValueKey<String>('editor-panel-dock-right')),
          )
          .width;
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-R2')),
        Offset(railWidth - overlappingWidth, 0),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-R2-height')),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      final rail = find.byKey(
        const ValueKey<String>('editor-panel-dock-right'),
      );
      final pill = find.descendant(
        of: rail,
        matching: find.byKey(const ValueKey<String>('canvas-view-pill')),
      );
      final bar = find.descendant(
        of: rail,
        matching: find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
      );
      expect(
        tester.getRect(pill).overlaps(tester.getRect(bar)),
        isTrue,
        reason: 'the fixture must actually reach the overlapping case',
      );

      // A hit at the pill's right end lands in the PILL, not the bar.
      final probe = Offset(
        tester.getRect(pill).right - 3,
        tester.getRect(pill).center.dy,
      );
      final hit = tester.hitTestOnBinding(probe);
      final pillBox = tester.renderObject(pill);
      final barBox = tester.renderObject(bar);
      final order = hit.path.map((e) => e.target).toList();
      expect(
        order.indexWhere((t) => identical(t, pillBox)),
        isNonNegative,
        reason: 'the pointer reaches the pill where the two overlap',
      );
      final pillAt = order.indexWhere((t) => identical(t, pillBox));
      final barAt = order.indexWhere((t) => identical(t, barBox));
      expect(
        barAt < 0 || pillAt < barAt,
        isTrue,
        reason: 'and reaches it FIRST — the bar is the one that yields',
      );
    });

    testWidgets('the rail scrolls only when the saved heights overflow it', (
      tester,
    ) async {
      // 유저 확정: the heights are FIXED and the rail scrolls when they will
      // not all fit — and not a moment sooner, because a scrolling rail
      // hands vertical drags to the scroll arena before the panel tabs see
      // them (the reason 띠는 스크롤하지 않는다 in the first place).
      //
      // 🚨R6-⑤ (2026-08-12) moved WHERE this is asked. The scroller is always
      // MOUNTED now and only sometimes LIVE — two different trees either side
      // of the overflow boundary used to swap under a live drag and dispose
      // the splitter the hand was holding. So "does it scroll" is read from
      // the scroll POSITION and from the bar, not from whether the widget
      // exists: a `SingleChildScrollView` whose content fits has no extent to
      // move and Flutter drops its drag recognizer by itself.
      await pumpApp(tester);
      Finder railScroll() =>
          find.byKey(const ValueKey<String>('rail-scroll-left'));
      Finder railThumb() =>
          find.byKey(const ValueKey<String>('rail-scroll-thumb-left'));
      // The rail's OWN controller — the panels inside carry scrollables of
      // their own, so a descendant search finds several.
      double railExtent() => tester
          .widget<SingleChildScrollView>(railScroll())
          .controller!
          .position
          .maxScrollExtent;

      expect(railExtent(), 0, reason: 'one group fits — nothing to scroll');
      expect(railThumb(), findsNothing, reason: 'and no bar says otherwise');

      // Open the left rail's second group (the tool settings).
      await tester.tap(
        groupButton(EditorWorkspace.railGroupId(right: false, slot: 2)),
      );
      await tester.pumpAndSettle();

      // Two 320px panels and a gap need 648; the rail has ~589.
      expect(railScroll(), findsOneWidget);
      expect(
        railExtent(),
        greaterThan(0),
        reason: 'now it overflows, so the same scroller has somewhere to go',
      );
      expect(railThumb(), findsOneWidget);
      // …and both panels are still there to be scrolled to.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(BrushSettingsPanel), findsOneWidget);
      // The bar rides the gap between the strip and the panels (유저, R3
      // #12), not the panels' far edge.
      final thumb = tester.getRect(
        find.byKey(const ValueKey<String>('rail-scroll-thumb-left')),
      );
      final panel = tester.getRect(
        find
            .ancestor(
              of: find.byType(BrushPresetPanel),
              matching: find.byType(SuperellipseClip),
            )
            .first,
      );
      expect(thumb.right, lessThanOrEqualTo(panel.left));
    });

    testWidgets('a rail panel FLOATS on the canvas: a gap from the strip, a '
        'gap above it, and it ends where its own height ends', (tester) async {
      await pumpApp(tester);

      final strip = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-left')),
      );
      final rail = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-left')),
      );

      // The rail's BOX starts at the strip now — the gap between them is
      // inside it, because that gap is where the rail's own scrollbar rides
      // (유저, R3 #12). What has to float is the PANEL.
      final panel = tester.getRect(
        find
            .ancestor(
              of: find.byType(BrushPresetPanel),
              matching: find.byType(SuperellipseClip),
            )
            .first,
      );
      expect(
        panel.left,
        greaterThan(strip.right),
        reason: 'pasteboard between the strip and the panel beside it',
      );
      expect(rail.top, greaterThan(strip.top));
      // It is a panel, not a column: it stops at its own saved height, well
      // short of the rail's own box. The width grip spans exactly the panel
      // it belongs to, so it measures the panel.
      final group = tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-rail-L1')),
      );
      expect(group.height, closeTo(EditorWorkspace.railGroupHeight, 0.5));
      expect(
        group.bottom,
        lessThan(rail.bottom - 100),
        reason: 'the panel does not swell to fill the rail',
      );
    });

    testWidgets('a panel\'s grips lie ON its own edges, inside its clip — '
        'so the lit edge follows the silhouette', (tester) async {
      // A 5px band cannot carry a 14px corner by itself; being inside the
      // panel's clip is what makes the hover read as the panel's edge
      // lighting up rather than as a bar parked beside it (유저, R2 #11).
      await pumpApp(tester);

      final panel = tester.getRect(
        find
            .ancestor(
              of: find.byType(BrushPresetPanel),
              matching: find.byType(SuperellipseClip),
            )
            .first,
      );
      final width = tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-rail-L1')),
      );
      final height = tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-rail-L1-height')),
      );

      // The width grip is the panel's inner edge; the height grip is its
      // bottom edge. Both inside, neither beside.
      expect(width.right, closeTo(panel.right, 0.5));
      expect(width.left, greaterThanOrEqualTo(panel.left));
      expect(height.bottom, closeTo(panel.bottom, 0.5));
      expect(height.top, greaterThanOrEqualTo(panel.top));
    });

    testWidgets('the canvas scrollbar keeps its place along the edge and '
        'steps IN when a rail opens', (tester) async {
      // Both halves matter. The bar used to ride the cover inset, so
      // raising the timeline walked it halfway up the panel (유저: furniture
      // does not move because a drawer opened). Then it sat on the raw
      // panel — and an open side panel covered it outright.
      await pumpApp(tester);

      // The FLOOR's bar. Every canvas panel wears one now (R2 #13), so an
      // app-wide finder matches the timesheet's too.
      Rect panbar() => tester.getRect(
        find.descendant(
          of: inMainCanvas(find.byType(BrushCanvasPanel)),
          matching: find.byKey(
            const ValueKey<String>('canvas-panbar-vertical'),
          ),
        ),
      );
      final rail = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
      );
      final opened = panbar();
      expect(
        opened.right,
        lessThanOrEqualTo(rail.left),
        reason: 'the bar is beside the panel, not under it',
      );

      // Close the rail: the bar takes the width back, and its centre along
      // the edge has not moved.
      await tester.tap(
        groupButton(EditorWorkspace.railGroupId(right: true, slot: 2)),
      );
      await tester.pumpAndSettle();
      final closed = panbar();
      expect(closed.right, greaterThan(opened.right));
      expect(closed.center.dy, closeTo(opened.center.dy, 0.5));
    });

    testWidgets('reopening a panel into a CLOSED group opens the group — a '
        'panel is never placed out of sight', (tester) async {
      await pumpApp(tester);

      // The tool SETTINGS are the case: their group is the left rail's
      // second slot, holds only them, and ships CLOSED (유저, R3 #10) — so
      // "reopen a panel whose group is not open" is the default state
      // rather than something the test has to build.
      expect(find.byType(BrushSettingsPanel), findsNothing);

      // The tab has no X any more — 패널 프레임 최소화 took it — so the
      // settings list IS the switch, in both directions.
      Future<void> togglePanel() async {
        await tester.tap(
          find.byKey(const ValueKey<String>('top-strip-settings-button')),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          const ValueKey<String>('panels-menu-item-brush-settings'),
        );
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
      }

      // Hide it, then ask for it back. Its home group is still closed.
      await togglePanel();
      expect(find.byType(BrushSettingsPanel), findsNothing);
      await togglePanel();

      expect(
        find.byType(BrushSettingsPanel),
        findsOneWidget,
        reason: 'reopening put it somewhere the user can see',
      );
    });

    testWidgets('the region narrows SYMMETRICALLY, and the columns run past '
        'it once it has pulled in far enough', (tester) async {
      await pumpApp(tester);

      Rect region() => tester.getRect(
        find.byKey(const ValueKey<String>('floating-bottom-region')),
      );
      Rect leftColumn() => tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-right')),
      );

      final host = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-left')),
      );
      final wide = region();
      // Flush: the columns stop at the region's top edge.
      expect(leftColumn().bottom, closeTo(wide.top, 6));

      // Pull the LEFT grip in. The RIGHT edge follows by the same amount —
      // one number, mirrored — so the region stays centred on the window.
      await tester.drag(
        find.byKey(const ValueKey<String>('bottom-inset-left')),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();

      final narrow = region();
      expect(narrow.left - wide.left, closeTo(wide.right - narrow.right, 1.0));
      expect(narrow.width, lessThan(wide.width));
      // Centred on the WINDOW, not on the visible canvas: opening a column
      // must not slide the region sideways.
      expect(
        narrow.center.dx,
        closeTo(wide.center.dx, 1.0),
        reason: 'the centre did not move',
      );
      expect(narrow.left, greaterThan(host.right));

      // 300px is past a 260px rail, so the columns now go all the way down.
      expect(
        leftColumn().bottom,
        greaterThan(narrow.top),
        reason: 'the column runs past the region to the window bottom',
      );
    });

    testWidgets('the colour group wears the SWATCH as its button, and opens '
        'sideways', (tester) async {
      await pumpApp(tester);

      // The picker is the top group of the sub-strip (유저 확정), closed
      // until you reach for it — but its colours are readable the whole
      // time, because the button that opens it IS the pair.
      final swatch = find.byKey(const ValueKey<String>('tool-color-button'));
      expect(swatch, findsOneWidget);
      expect(find.byType(ColorWheelPanel), findsNothing);

      final strip = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-right')),
      );
      expect(tester.getRect(swatch).center.dx, closeTo(strip.center.dx, 6));

      await tester.tap(swatch);
      await tester.pumpAndSettle();

      final panel = find.byType(ColorWheelPanel);
      expect(panel, findsOneWidget);
      // SIDEWAYS: beside the strip, not hanging off it downward the way the
      // strip popup did.
      expect(tester.getRect(panel).right, lessThanOrEqualTo(strip.left + 0.5));
      expect(
        find.byKey(const ValueKey<String>('panel-tab-color-wheel')),
        findsOneWidget,
      );
    });

    testWidgets('a group is ONE section however many panels it holds', (
      tester,
    ) async {
      await pumpApp(tester);

      // A group is a rail BUTTON's set of panels, switched by one icon
      // strip. It cannot be a stack: the drop that split a dock into
      // sections is gone, and reopening a panel joins the strip instead of
      // minting a second one.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(BrushSettingsPanel), findsNothing);
    });
  });
}
