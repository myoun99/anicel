import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/frame_name_conflict_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️I-18 (유저): 「이제 링크프레임이나 링크레이어 발동할때 뜨는 안내메시지를
/// 단일 변경만 대응하는게 아니라 복수 대응을 기본으로. 대상의 프레임을
/// 리스트로서 보여주도록」.
void main() {
  const list = ValueKey<String>('app-notice-details-list');

  Future<void> pump(WidgetTester tester, List<String> targets) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FrameNameConflictDialog(targets: targets)),
      ),
    );
    await tester.pump();
  }

  testWidgets('the frames the link takes are listed, OPEN — which ones is '
      'what the window asks about', (tester) async {
    const targets = ['1 · A · 3', '1 · A · 4'];
    await pump(tester, targets);

    expect(find.byKey(list), findsOneWidget, reason: 'open with the window');
    for (final line in targets) {
      expect(
        find.descendant(of: find.byKey(list), matching: find.text(line)),
        findsOneWidget,
        reason: line,
      );
    }
    expect(
      find.text('${AppText.strings.frameNameConflictListHeading} (2)'),
      findsOneWidget,
    );
  });

  testWidgets('one frame is a list of one', (tester) async {
    await pump(tester, const ['1 · A · 2']);

    expect(
      find.descendant(of: find.byKey(list), matching: find.byType(Text)),
      findsOneWidget,
    );
  });
}
