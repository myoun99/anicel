import 'dart:math' as math;

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️R9-rest, 유저 2026-10-06 of the text tool's 「선택된 텍스트」 list:
/// 「거기서 다른 텍스트 선택할수있게 리스트 고르는. 팝오버로 리스트
/// 고를수있게하고. 텍스트의 이름은 그냥 텍스트 글자대로. 그리고 옆에
/// 삭제버튼 있고」 — and of the drawing made from it, a delete on every row:
/// 「1 ok」.
///
/// The list is the app's one picker (F-230), so what it lacked went INTO it
/// rather than round it: a row can carry one small command of its own at
/// its end ([PanelFlyoutRowAction]), and a name as long as its owner likes
/// stays on one line.
void main() {
  const opener = ValueKey<String>('flyout-under-test');

  Future<void> pumpList(
    WidgetTester tester,
    List<PanelFlyoutEntry> Function() entries,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: PanelFlyoutButton(
              key: opener,
              label: 'Texts',
              entriesBuilder: entries,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(opener));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  testWidgets('🚨the command at a row\'s end is pressed INSTEAD of the row: '
      'the list closes, the command runs, and the row is not chosen', (
    tester,
  ) async {
    final heard = <String>[];
    await pumpList(
      tester,
      () => [
        PanelFlyoutItem(
          keyValue: 'row-a',
          label: 'a',
          onSelected: () => heard.add('chose a'),
          action: PanelFlyoutRowAction(
            keyValue: 'row-a-delete',
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () => heard.add('deleted a'),
          ),
        ),
        PanelFlyoutItem(
          keyValue: 'row-b',
          label: 'b',
          onSelected: () => heard.add('chose b'),
          action: PanelFlyoutRowAction(
            keyValue: 'row-b-delete',
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () => heard.add('deleted b'),
          ),
        ),
      ],
    );
    expect(key('row-b-delete'), findsOneWidget, reason: '⛔fixture');

    await tester.tap(key('row-b-delete'));
    await tester.pumpAndSettle();

    expect(heard, ['deleted b']);
    expect(key('row-b'), findsNothing, reason: 'the list closed');
  });

  testWidgets('a press on the ROW chooses it, and its command is not run', (
    tester,
  ) async {
    final heard = <String>[];
    await pumpList(
      tester,
      () => [
        PanelFlyoutItem(
          keyValue: 'row-a',
          label: 'a',
          onSelected: () => heard.add('chose a'),
          action: PanelFlyoutRowAction(
            keyValue: 'row-a-delete',
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            onPressed: () => heard.add('deleted a'),
          ),
        ),
      ],
    );

    // Where the row's own name is, well clear of the button at its end.
    await tester.tapAt(tester.getTopLeft(key('row-a')) + const Offset(24, 16));
    await tester.pumpAndSettle();

    expect(heard, ['chose a']);
  });

  testWidgets('the command runs AFTER the list has closed: nothing is left '
      'to go back from', (tester) async {
    bool? listStillOpen;
    await pumpList(
      tester,
      () => [
        PanelFlyoutItem(
          keyValue: 'row-a',
          label: 'a',
          action: PanelFlyoutRowAction(
            keyValue: 'row-a-delete',
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            // The list is a route over the page: while it is open there
            // is one to pop.
            onPressed: () => listStillOpen = tester
                .state<NavigatorState>(find.byType(Navigator))
                .canPop(),
          ),
        ),
      ],
    );
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isTrue,
      reason: '⛔fixture: the open list is a route',
    );

    await tester.tap(key('row-a-delete'));
    await tester.pumpAndSettle();

    expect(listStillOpen, isFalse);
  });

  testWidgets('a command that DELETES wears the app\'s delete red; one that '
      'does not wears the row\'s ink', (tester) async {
    await pumpList(
      tester,
      () => [
        PanelFlyoutItem(
          keyValue: 'row-a',
          label: 'a',
          action: PanelFlyoutRowAction(
            keyValue: 'row-a-delete',
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () {},
          ),
        ),
        PanelFlyoutItem(
          keyValue: 'row-b',
          label: 'b',
          action: PanelFlyoutRowAction(
            keyValue: 'row-b-rename',
            icon: Icons.edit_outlined,
            tooltip: 'Rename',
            onPressed: () {},
          ),
        ),
      ],
    );

    Icon glyph(String button, IconData icon) => tester.widget<Icon>(
      find.descendant(of: key(button), matching: find.byIcon(icon)),
    );

    expect(
      glyph('row-a-delete', Icons.delete_outline).color,
      AppColors.deleteGlyph(enabled: true),
    );
    expect(glyph('row-b-rename', Icons.edit_outlined).color, isNull);
  });

  testWidgets('a row with no command of its own draws no button', (
    tester,
  ) async {
    await pumpList(
      tester,
      () => [const PanelFlyoutItem(keyValue: 'row-a', label: 'a')],
    );

    expect(
      find.descendant(of: key('row-a'), matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: key('row-a'), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('🚨a name as long as its owner likes stays on ONE line and '
      'ends in an ellipsis', (tester) async {
    final long = 'BG only 3コマ打ち、口パクなし ' * 12;
    await pumpList(
      tester,
      () => [PanelFlyoutItem(keyValue: 'row-a', label: long)],
    );

    final name = tester.widget<Text>(find.text(long));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(key('row-a')).height, flyoutRowHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('🚨and it is cut where the ROW ends, not after the last word '
      'that fits: a name of several words fills its row', (tester) async {
    // A short word, and then one longer than any row. Let to wrap, the
    // line would end after the first and show two letters of the name.
    final long = 'ab ${'c' * 400}';
    await pumpList(
      tester,
      () => [PanelFlyoutItem(keyValue: 'row-a', label: long)],
    );

    final name = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(long), matching: find.byType(RichText)),
    );
    final reach = name
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: long.length),
        )
        .map((box) => box.right)
        .reduce(math.max);
    // In the test font a letter is as wide as its size, twelve: the name
    // runs to within a letter and the ellipsis of where the row ends.
    expect(reach, greaterThan(name.size.width - 3 * 12));
    expect(name.size.width, greaterThan(10 * 12), reason: '⛔fixture');
  });

  testWidgets('⛔a list with nothing in it does not open — a press is '
      'nothing, and nothing throws', (tester) async {
    await pumpList(tester, () => const []);

    expect(tester.takeException(), isNull);
    expect(find.byType(PopupMenuItem<PanelFlyoutItem>), findsNothing);
  });
}
