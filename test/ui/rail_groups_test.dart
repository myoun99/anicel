import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_browser_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

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
      // An empty slot is not a button you can press — it appears only as a
      // drop target, and only while something is in flight.
      expect(
        groupButton(EditorWorkspace.railGroupId(right: false, slot: 2)),
        findsNothing,
      );
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
          .getRect(find.byKey(const ValueKey<String>('editor-panel-dock-right')))
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

    testWidgets('two groups open at once divide the rail, and share ONE '
        'width', (tester) async {
      await pumpApp(tester);

      // Move the media browser into a second LEFT group by dragging its tab
      // onto that rail's empty slot, then check both columns coexist.
      final mediaTab = find.byKey(const ValueKey<String>('panel-tab-media'));
      await tester.ensureVisible(mediaTab);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('panel-grip-media')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      final slot = groupButton(
        EditorWorkspace.railGroupId(right: false, slot: 2),
      );
      expect(slot, findsOneWidget, reason: 'the empty slot offers itself');
      await gesture.moveTo(tester.getCenter(slot));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Both groups are open and both are on screen.
      expect(find.byType(BrushPresetPanel), findsOneWidget);
      expect(find.byType(MediaBrowserPanel), findsOneWidget);
      final library = tester.getRect(find.byType(BrushPresetPanel));
      final media = tester.getRect(find.byType(MediaBrowserPanel));
      expect(
        media.top,
        greaterThanOrEqualTo(library.top),
        reason: 'the new group stacks below, it does not replace',
      );
      // 레일당 폭 하나: the two groups are exactly as wide as each other.
      expect(media.width, closeTo(library.width, 0.5));

      // And widening the rail widens BOTH, because there is one splitter
      // and one number behind it.
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-left')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      final grownLibrary = tester.getRect(find.byType(BrushPresetPanel));
      final grownMedia = tester.getRect(find.byType(MediaBrowserPanel));
      expect(grownLibrary.width, greaterThan(library.width));
      expect(grownMedia.width, closeTo(grownLibrary.width, 0.5));
    });

    testWidgets('reopening a panel into a CLOSED group opens the group — a '
        'panel is never placed out of sight', (tester) async {
      await pumpApp(tester);

      // Close the sheet's panel. The tab has no X any more — 패널 프레임
      // 최소화 took it — so the settings list IS the switch, in both
      // directions.
      Future<void> togglePanel() async {
        await tester.tap(
          find.byKey(const ValueKey<String>('top-strip-settings-button')),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          const ValueKey<String>('panels-menu-item-timesheet'),
        );
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
      }

      await togglePanel();
      expect(find.byType(TimesheetTabHost), findsNothing);

      // Reopen it from the Settings popover's panel list. Its home is that
      // right group, which now holds nothing and is therefore not open.
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(
        const ValueKey<String>('panels-menu-item-timesheet'),
      );
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(
        find.byType(TimesheetTabHost),
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
      expect(find.byKey(const ValueKey<String>('color-picker-panel')),
          findsNothing);

      final strip = tester.getRect(
        find.byKey(const ValueKey<String>('editor-panel-dock-tool-right')),
      );
      expect(tester.getRect(swatch).center.dx, closeTo(strip.center.dx, 6));

      await tester.tap(swatch);
      await tester.pumpAndSettle();

      final panel = find.byKey(const ValueKey<String>('color-picker-panel'));
      expect(panel, findsOneWidget);
      // SIDEWAYS: beside the strip, not hanging off it downward the way the
      // strip popup did.
      expect(tester.getRect(panel).right, lessThanOrEqualTo(strip.left + 0.5));
      expect(
        find.byKey(const ValueKey<String>('color-window-tab-wheel')),
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
