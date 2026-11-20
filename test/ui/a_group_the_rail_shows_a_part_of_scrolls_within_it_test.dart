import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/rail_group_button.dart';

/// 🗣️tool-settings-rows-cut-off-under-the-variants-panel-Q1 (유저
/// 2026-11-19): 「가려진 패널의 안쪽 칸을 레일이 보여 주는 부분만큼만
/// 쓴다」 — a group the rail's window shows a part of scrolls within that
/// part: its bar is all in view, and the wheel alone reaches its last row.
/// The rail's height, the saved heights and the rail's scroll stay.
///
/// The card's fixture: the Surface's window (2880×1814 at 2 — 1440×907),
/// the fill tool, and the tool library over the tool settings on the left
/// rail — 320 + 8 + 320 against a window of about 417.
void main() {
  final leftRail = railScroll(right: false);
  ScrollPosition rail(WidgetTester tester) =>
      railPosition(tester, right: false);
  Finder groupBody(String railId) =>
      find.byKey(ValueKey<String>('rail-group-body-$railId'));
  Finder settings() =>
      find.byKey(const ValueKey<String>('tool-settings-fill'));
  ScrollPosition inner(WidgetTester tester) =>
      tester.widget<ListView>(settings()).controller!.position;
  Finder library() =>
      find.byKey(const ValueKey<String>('tool-library-fill'));

  Future<void> jumpRail(WidgetTester tester, double pixels) async {
    rail(tester).jumpTo(pixels);
    await tester.pump();
  }

  Future<void> pumpTheCardsFixture(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 907));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tool-fill-button')));
    await tester.pumpAndSettle();
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ToolSettingsPanel), findsOneWidget);
    expect(rail(tester).pixels, 0);
    expect(
      tester.getRect(groupBody(toolSettingsGroupId)).bottom,
      greaterThan(tester.getRect(leftRail).bottom + 100),
      reason: 'premise: the window shows only a part of the settings',
    );
  }

  /// How far [list] ends above its group's bottom when the window shows
  /// all of it — read with the rail at its end.
  Future<double> wholeGap(WidgetTester tester, Finder list, String id) async {
    final pixels = rail(tester).pixels;
    await jumpRail(tester, rail(tester).maxScrollExtent);
    final gap =
        tester.getRect(groupBody(id)).bottom - tester.getRect(list).bottom;
    await jumpRail(tester, pixels);
    return gap;
  }

  testWidgets('a group the window shows a part of ends its list where the '
      'window ends, and the wheel alone brings up its last row', (
    tester,
  ) async {
    await pumpTheCardsFixture(tester);
    final gap = await wholeGap(tester, settings(), toolSettingsGroupId);
    final window = tester.getRect(leftRail);

    expect(
      tester.getRect(settings()).bottom,
      closeTo(window.bottom - gap, 1e-6),
      reason: 'the settings scroll within the part the window shows',
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getRect(settings()).center),
    );
    for (var turn = 0; turn < 40 && inner(tester).extentAfter > 0; turn++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump();
    }
    expect(inner(tester).extentAfter, 0, reason: 'the list came to its end');
    expect(
      rail(tester).pixels,
      0,
      reason: 'and did so before the wheel went on to the rail',
    );
    expect(
      tester.getRect(settings()).bottom,
      lessThanOrEqualTo(window.bottom),
      reason: 'so its last row is in the window',
    );
  });

  testWidgets('the part grows as the rail brings the group in, landed on '
      'the window\'s pixel, and is the whole group once all of it shows', (
    tester,
  ) async {
    await pumpTheCardsFixture(tester);
    final gap = await wholeGap(tester, settings(), toolSettingsGroupId);
    final window = tester.getRect(leftRail);

    // 100.1 lands the window on a device pixel the position is not on.
    for (final pixels in [37.0, 100.1, 180.0]) {
      await jumpRail(tester, pixels);
      final body = tester.getRect(groupBody(toolSettingsGroupId));
      final list = tester.getRect(settings());
      expect(body.bottom, greaterThan(window.bottom), reason: 'at $pixels');
      expect(
        list.bottom,
        closeTo(window.bottom - gap, 1e-6),
        reason: 'at $pixels',
      );
    }

    await jumpRail(tester, rail(tester).maxScrollExtent);
    final body = tester.getRect(groupBody(toolSettingsGroupId));
    expect(tester.getRect(settings()).bottom, closeTo(body.bottom - gap, 1e-6));
    expect(
      tester.getRect(groupBody(toolSettingsGroupId)).bottom,
      lessThanOrEqualTo(window.bottom),
      reason: 'premise: all of it shows',
    );
  });

  testWidgets('a group whose top the window has passed scrolls within what '
      'is left of it, from the window\'s top', (tester) async {
    await pumpTheCardsFixture(tester);
    final whole = tester.getRect(library());
    final group = tester.getRect(groupBody(EditorWorkspace.leftGroupId));
    // Where the list stands under its group's strip.
    final under = whole.top - group.top - EditorPanelTabs.stripHeight;

    await jumpRail(tester, rail(tester).maxScrollExtent);
    final window = tester.getRect(leftRail);
    final moved = rail(tester).pixels;
    expect(
      whole.top - moved,
      lessThan(window.top),
      reason: 'premise: the window has passed the top of the library\'s list',
    );

    final list = tester.getRect(library());
    expect(list.top, closeTo(window.top + under, 1e-6));
    expect(list.bottom, closeTo(whole.bottom - moved, 1e-6));
  });

  testWidgets('the window a rail\'s layout moves it to is the window its '
      'groups are laid to, in that frame', (tester) async {
    await pumpTheCardsFixture(tester);
    final whole = tester.getRect(library());
    await jumpRail(tester, rail(tester).maxScrollExtent);
    expect(
      tester.getRect(library()).height,
      lessThan(whole.height),
      reason: 'premise: the library is laid to the window\'s part of it',
    );

    // Closing the settings leaves the library alone on a rail it fits:
    // the rail's layout pulls its position back to the top.
    await pressToolSettingsButton(tester);
    await tester.pump();

    expect(rail(tester).pixels, 0, reason: 'premise: pulled back in layout');
    expect(tester.getRect(library()), whole);
  });

  testWidgets('a group is never laid shorter than its panels lay out in — '
      'the colours, cut from above, keep their floor and their bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 907));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    const colours = EditorWorkspace.rightGroupId;
    await tester.tap(railGroupButton(colours));
    await tester.pumpAndSettle();
    final railRight = railScroll(right: true);
    final position = railPosition(tester, right: true);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final window = tester.getRect(railRight);
    final group = tester.getRect(groupBody(colours));
    final host = tester.getRect(
      find.descendant(
        of: groupBody(colours),
        matching: find.byType(EditorDockHost),
      ),
    );
    expect(group.top, lessThan(window.top), reason: 'premise: cut from above');
    expect(host.bottom, group.bottom);
    expect(
      host.height,
      greaterThan(EditorPanelTabs.stripHeight + group.bottom - window.top),
      reason: 'the colour wheel cannot be laid out in the part shown',
    );
  });

  testWidgets('a group shown a sliver of cuts what does not scroll in it, '
      'top down — the preview pinned over the brush\'s settings, and the '
      'rows of the cut', (tester) async {
    await pumpTheCardsFixture(tester);
    final hand = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    // What stands first in each, and how far under the panel's top.
    final cases = <CanvasTool, (Finder, double)>{
      CanvasTool.brush: (find.byKey(ToolSettingsPreview.slotKey), 0),
      CanvasTool.cutWhole: (
        find
            .descendant(
              of: find.byKey(ToolSettingsSection.keyFor('cut-grab')),
              matching: find.byType(Column),
            )
            .first,
        ToolSettingsSection.inset.top,
      ),
    };
    for (final MapEntry(key: tool, value: (first, under)) in cases.entries) {
      hand.value = hand.value.copyWith(tool: tool);
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(ToolSettingsPanel));
      expect(
        panel.height,
        lessThan(ToolSettingsPreview.extent),
        reason: 'premise: $tool is shown a sliver of',
      );
      expect(
        panel.bottom,
        lessThanOrEqualTo(tester.getRect(leftRail).bottom),
        reason: '$tool: laid to the part shown',
      );
      expect(
        tester.getRect(first).top,
        panel.top + under,
        reason: '$tool',
      );
    }
  });
}
