import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// deselect-button — **the tablet's Esc.**
///
/// 유저: 「선택해제 버튼 (태블릿엔 키보드가 없다)」. Every other way out of a
/// selection is a TAP somewhere, and a tap also moves the playhead or the
/// standing row. This is the one that only lets go.
///
/// It lives on the SHARED pill because that pill's subject is 「지금 무엇이
/// 선택됐나」 — letting go is that subject's own verb, not a place picked for it.
void main() {
  const button = ValueKey<String>('shared-deselect-button');

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  testWidgets('it is there and DIM with nothing selected', (tester) async {
    await pump(tester);

    final finder = find.byKey(button);
    expect(
      finder,
      findsOneWidget,
      reason: '⛔없다가 생기는 UI 금지 — it is dimmed, never absent',
    );
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: 'nothing to let go of',
    );
  });

  testWidgets('a live selection lights it, and pressing it lets go', (
    tester,
  ) async {
    final session = await pump(tester);
    final layer = session.layers.first;

    session.updateFrameRangeSelectionDrag(
      layerId: layer.id,
      anchorIndex: 0,
      headIndex: 2,
    );
    await tester.pumpAndSettle();
    expect(
      session.frameRangeSelection.value,
      isNotNull,
      reason: 'fixture premise',
    );
    expect(
      tester.widget<IconButton>(find.byKey(button)).onPressed,
      isNotNull,
      reason: 'T25: it lights on the same question its press runs',
    );

    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();

    expect(session.frameRangeSelection.value, isNull);
    expect(
      session.currentFrameIndex,
      0,
      reason: 'and it ONLY lets go — the playhead is where it was, which is '
          'the whole reason a button exists instead of a tap somewhere',
    );
  });

  testWidgets('a ROW selection lights it too — one question, four kinds', (
    tester,
  ) async {
    final session = await pump(tester);

    session.beginRowSelection(session.currentRow);
    await tester.pumpAndSettle();
    expect(session.rowSelection.value, isNotEmpty, reason: 'fixture premise');

    expect(
      tester.widget<IconButton>(find.byKey(button)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
    expect(session.rowSelection.value, isEmpty);
  });
}
