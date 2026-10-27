import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';

/// 🚨유저 #7 (2026-08-14): 「**1,2,3,4,N 에서 n버튼 오른쪽만 미묘하게 짧다**
/// 던가, **fx버튼의 오른쪽이 미묘하게 공간 있다**던가. 이런 미묘한 이상한
/// 패딩 싹 삭제」.
///
/// ★A pill owes its contents the same margin on both ends. The tail was a
/// flat 4 while a TEXT name cell pays 1 + 6 on its leading edge, so a
/// text-headed pill measured 7 in and 4 out — and `N`, a glyph with no
/// bearing of its own, is exactly where those three pixels showed.
///
/// 🚨Measured on the REAL bar (frame-pill-tail-breath-regressed,
/// 2026-10-27): the bare pills here all breathed even while the frame
/// pill's name sat in a gated group and its tail paid 5 after a 7 — the
/// bar's own build is what went wrong, so the bar is what is measured.
void main() {
  Future<Rect> pillRect(WidgetTester tester, Widget pill) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: pill))),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(CommandPill));
  }

  testWidgets('every pill on the bar breathes the same on both ends', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(2400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: TimelineActionToolbar(
              session: session,
              panelContext: TimelineToolbarPanelContext(session),
              onAddLayer: () {},
              onRenameLayer: () {},
              onDeleteLayer: () {},
              onEditInstance: () {},
              onCreateInstance: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect rectOf(Widget widget) => tester.getRect(find.byWidget(widget));
    // A name cell's padding is the pill's breath, so it is measured to the
    // cell's WORD; a verb's inset is its own, so to the verb's box.
    Rect? wordOf(Widget? head) => switch (head) {
      final head? => tester.getRect(
        find.descendant(
          of: find.byWidget(head),
          matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
        ),
      ),
      null => null,
    };

    const names = ['cut', 'layer', 'frame', 'shared', 'fx'];
    final pills = tester.widgetList<CommandPill>(find.byType(CommandPill));
    expect(pills, hasLength(names.length), reason: 'the bar\'s five pills');
    for (final (index, pill) in pills.indexed) {
      final edge = rectOf(pill);
      final word = wordOf(pill.head);
      final first = word ?? rectOf(pill.children.first);
      final last = pill.children.isEmpty ? word! : rectOf(pill.children.last);

      expect(
        edge.right - last.right,
        first.left - edge.left,
        reason:
            'the ${names[index]} pill\'s tail owes what its head pays — '
            '「n버튼 오른쪽만 짧다」',
      );
    }
  });

  testWidgets('an ICON-headed pill too', (tester) async {
    const verb = SizedBox(
      key: ValueKey<String>('verb'),
      width: 24,
      height: 24,
    );
    final rect = await pillRect(
      tester,
      CommandPill(
        head: PillNameCell(
          keyValue: 'head',
          icon: Icons.folder,
          entriesBuilder: () => const [],
        ),
        children: [verb],
      ),
    );
    final head = tester.getRect(find.byIcon(Icons.folder));
    final tail = tester.getRect(find.byKey(const ValueKey<String>('verb')));

    expect(rect.right - tail.right, head.left - rect.left);
  });

  testWidgets('⛔a head the pill cannot read is an error, never a guess', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CommandPill(
          head: SizedBox(width: 24),
          children: [SizedBox(width: 24)],
        ),
      ),
    );

    expect(tester.takeException(), isA<StateError>());
  });
}
