import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// ⑰ 유저 2026-08-12: 「딜리트버튼, 슬 통일하고싶음. **버튼 그냥 하나로.**
/// 기본적으로 누르면 액티브레이어의 현재 프레임블록 삭제하고, 물론 선택범위로
/// 선택하고 삭제가능. 그리고 레이어 선택하고 누르면 레이어삭제 … 컷도 마찬가지로
/// 컷 선택하고 삭제버튼누르면 컷 삭제.」
///
/// The point is not that a button moved. It is that DELETE STOPPED BEING
/// THREE VERBS: `delete-cut-button` in the cut menu, `delete-layer-button` in
/// the layer menu and a loose `timeline-delete-layer-button` beside it, each
/// hard-wired to one noun. The same word did different things depending on
/// where you reached for it, and a cut could not be deleted at all without
/// opening one particular menu.
void main() {
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  testWidgets('the MENU deletes are gone and every subject still has a door — '
      'a predecessor may only go once the successor can do its job', (
    tester,
  ) async {
    await pump(tester);
    // The MENU copies are gone — each was a second door onto a button that
    // was already on the bar beside it.
    expect(
      find.byKey(const ValueKey<String>('delete-layer-button')),
      findsNothing,
      reason: 'the Layer flyout must not carry a second delete',
    );
    expect(
      find.byKey(const ValueKey<String>('shared-delete-button')),
      findsOneWidget,
    );
    // ⚠️And the two row-level deletes are still reachable, deliberately.
    //
    // ⑰ wants them folded in as well, and they will be — but the shared verb
    // reaches a LAYER through a row selection ⑨ has not built yet, and a CUT
    // through a cut selection that only exists on the storyboard's axis.
    // Removing them on the strength of the unified button would have left
    // layer deletion with no entrance at all and cut deletion unreachable from
    // the timeline. Both tests below existed before this round and caught
    // exactly that.
    expect(
      find.byKey(const ValueKey<String>('timeline-delete-layer-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('delete-cut-button')),
      findsOneWidget,
      reason: 'on the cut PILL now (①), not inside its menu',
    );
  });

  testWidgets('it asks WHAT IS SELECTED, in the user\'s order', (tester) async {
    final session = await pump(tester);

    // Nothing selected, a cel under the playhead: the frame axis answers.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(session.deleteSubject, DeleteSubject.cells);

    // A cut range outranks it — 「컷도 마찬가지로 컷 선택하고 삭제버튼누르면」.
    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 0,
      headGlobalFrame: 2,
    );
    await tester.pumpAndSettle();
    expect(
      session.deleteSubject,
      DeleteSubject.cuts,
      reason: 'a selected cut is what the press is about, not the cel beneath',
    );

    session.clearStoryboardCutSelection();
    await tester.pumpAndSettle();
    expect(session.deleteSubject, DeleteSubject.cells);
  });

  testWidgets('the glyph is RED wherever it is, and goes dark with the button',
      (tester) async {
    // 유저: 「+버튼은 강조색이라는 공통규칙있는데, 딜리트는 지금처럼 빨간색
    // 공통규칙두자」 — the plus rule's twin, so it is asked of the theme once.
    final session = await pump(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    Icon glyph() => tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('shared-delete-button')),
        matching: find.byType(Icon),
      ),
    );
    expect(session.deleteSubject, isNot(DeleteSubject.nothing));
    expect(glyph().color, AppColors.danger);
    expect(AppColors.deleteGlyph(enabled: false), isNull);
  });
}
