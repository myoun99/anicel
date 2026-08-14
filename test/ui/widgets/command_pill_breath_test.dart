import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';

/// 🚨유저 #7 (2026-08-14): 「**1,2,3,4,N 에서 n버튼 오른쪽만 미묘하게 짧다**
/// 던가, **fx버튼의 오른쪽이 미묘하게 공간 있다**던가. 이런 미묘한 이상한
/// 패딩 싹 삭제」.
///
/// ★A pill owes its contents the same margin on both ends. The tail was a
/// flat 4 while a TEXT name cell pays 1 + 6 on its leading edge, so a
/// text-headed pill measured 7 in and 4 out — and `N`, a glyph with no
/// bearing of its own, is exactly where those three pixels showed.
void main() {
  Future<Rect> pillRect(WidgetTester tester, Widget pill) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: pill))),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(CommandPill));
  }

  testWidgets('a TEXT-headed pill breathes the same on both ends', (
    tester,
  ) async {
    final verb = Container(
      key: const ValueKey<String>('verb'),
      width: 24,
      height: 24,
    );
    final rect = await pillRect(
      tester,
      CommandPill(
        head: PillNameCell(
          keyValue: 'head',
          label: '프레임',
          entriesBuilder: () => const [],
        ),
        children: [verb],
      ),
    );
    final head = tester.getRect(find.text('프레임'));
    final tail = tester.getRect(find.byKey(const ValueKey<String>('verb')));

    expect(
      rect.right - tail.right,
      head.left - rect.left,
      reason: 'the tail owes what the head pays — 「n버튼 오른쪽만 짧다」',
    );
  });

  testWidgets('an ICON-headed pill too', (tester) async {
    final verb = Container(
      key: const ValueKey<String>('verb'),
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

  testWidgets('⛔a head-only pill pays no tail at all — that gap was the fx '
      'button\'s', (tester) async {
    final rect = await pillRect(
      tester,
      CommandPill(
        head: PillNameCell(
          keyValue: 'head',
          label: 'Fx',
          entriesBuilder: () => const [],
        ),
        children: const [],
      ),
    );
    final head = tester.getRect(find.text('Fx'));

    expect(
      rect.right - head.right,
      head.left - rect.left,
      reason: 'the name cell already pays its own trailing padding',
    );
  });
}
