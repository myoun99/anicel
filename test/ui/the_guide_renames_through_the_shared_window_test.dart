import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🚨★★★유저 (guide-sym): 「대칭/퍼스 버튼에서 **비지블버튼 왼쪽에 이름변경
/// 버튼** 추가해서 **공통 이름변경ui창** 띄우도록. 이름은 **중복이어도
/// 상관없도록**. 만약 로직적으로 지금 중복허용x면 그대로 해도됨」.
void main() {
  const a = GuideId('a');
  const b = GuideId('b');

  DrawingGuide guide(GuideId id, String name) => DrawingGuide(
    id: id,
    name: name,
    shape: SymmetryShape(
      axis: GuideAxis(origin: CanvasPoint(x: 10, y: 10), angleDegrees: 0),
    ),
  );

  Future<CutGuides> pump(
    WidgetTester tester, {
    required CutGuides start,
    required void Function(CutGuides) onCommitted,
  }) async {
    var guides = start;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => GuideLibraryList(
              guides: guides,
              canvasSize: const CanvasSize(width: 200, height: 200),
              selectedGuideId: null,
              onGuideSelected: (_) {},
              onGuidesCommitted: (next) {
                onCommitted(next);
                setState(() => guides = next);
              },
            ),
          ),
        ),
      ),
    );
    return guides;
  }

  Finder button(String keyValue) => find.byWidgetPredicate(
    (w) => w is AppIconButton && w.keyValue == keyValue,
  );

  testWidgets('the rename button sits LEFT of the eye', (tester) async {
    await pump(
      tester,
      start: CutGuides(guides: [guide(a, '대칭 1')]),
      onCommitted: (_) {},
    );

    final rename = button('guide-rename-a');
    final eye = button('guide-visible-a');
    expect(rename, findsOneWidget);
    expect(eye, findsOneWidget);
    expect(
      tester.getCenter(rename).dx,
      lessThan(tester.getCenter(eye).dx),
      reason: '「비지블버튼 왼쪽에 이름변경 버튼」',
    );
  });

  testWidgets('it opens the SHARED rename window and the name lands', (
    tester,
  ) async {
    CutGuides? committed;
    await pump(
      tester,
      start: CutGuides(guides: [guide(a, '대칭 1')]),
      onCommitted: (next) => committed = next,
    );

    await tester.tap(button('guide-rename-a'));
    await tester.pumpAndSettle();

    // ★The premise: it is the app's own rename window, not a private one —
    // these are the keys `AppPromptDialog` carries for every subject.
    expect(
      find.byKey(const ValueKey<String>('rename-guide-text-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rename-guide-ok-button')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-guide-text-field')),
      '왼쪽 대칭',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-guide-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(committed?.guides.single.name, '왼쪽 대칭');
  });

  testWidgets('⛔cancel changes nothing', (tester) async {
    var commits = 0;
    await pump(
      tester,
      start: CutGuides(guides: [guide(a, '대칭 1')]),
      onCommitted: (_) => commits += 1,
    );

    await tester.tap(button('guide-rename-a'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-guide-text-field')),
      '버려질 이름',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-guide-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(commits, 0);
  });

  testWidgets('🚨two guides may carry the SAME name', (tester) async {
    // 유저: 「이름은 중복이어도 상관없도록」 — nothing in the model forbids it,
    // and this is the case that keeps it that way.
    CutGuides? committed;
    await pump(
      tester,
      start: CutGuides(guides: [guide(a, '대칭 1'), guide(b, '대칭 2')]),
      onCommitted: (next) => committed = next,
    );

    await tester.tap(button('guide-rename-b'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-guide-text-field')),
      '대칭 1',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-guide-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(
      committed?.guides.map((g) => g.name).toList(),
      ['대칭 1', '대칭 1'],
      reason: 'no rule rejects it, and none is invented here',
    );
  });
}
