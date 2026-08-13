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
    // ⚠️The LAYER delete has since been folded in too (F). It stayed only
    // until the shared verb could name a layer at all — ⑨ built that row
    // selection, and the confirmation moved across with it — so the loose
    // button held nothing this one cannot do.
    expect(
      find.byKey(const ValueKey<String>('timeline-delete-layer-button')),
      findsNothing,
    );
    // ⚠️And the CUT delete has now gone too (T24). It was the last one held
    // back, on the ground that cut selection lives on the storyboard's axis
    // alone so the shared verb could never be handed a cut from here — true,
    // and retired by the user rather than disproved: 「타임라인에서 컷 선택은
    // 못해도되. 할필요도없어. 컷 편집은 스토리보드패널에서 하는거고」. A
    // capability the timeline is not meant to have is not one it loses.
    expect(
      find.byKey(const ValueKey<String>('delete-cut-button')),
      findsNothing,
    );
    // The frame menu's cell delete went with them — the same verb the shared
    // ladder falls through to with nothing else selected.
    expect(
      find.byKey(const ValueKey<String>('delete-cell-button')),
      findsNothing,
    );
    // Which leaves exactly one door.
    expect(
      find.byKey(const ValueKey<String>('shared-delete-button')),
      findsOneWidget,
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
    // CONTRACT CHANGED (T16, 2026-08-13): disabled used to be `null`, which
    // handed the icon to the BUTTON's own ink — and a button has two of
    // those, so red → grey travelled through near-white, and a folded bar
    // (the command groups are baked pictures) could freeze there.
    // 유저: 「빨강→하양→회색. 중간에 이상하게 하얀색이 존재하는 버그」.
    // Both ends are named now, so there is no third value to stop on.
    expect(AppColors.deleteGlyph(enabled: false), AppColors.glyphDisabled);
    expect(AppColors.deleteGlyph(enabled: false), isNot(AppColors.text));
    expect(AppColors.addGlyph(enabled: false), AppColors.glyphDisabled);
  });
}
