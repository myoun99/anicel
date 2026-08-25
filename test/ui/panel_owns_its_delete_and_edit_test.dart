import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/models/edit_instance_subject.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// R5q1 — **delete and edit follow the panel they are pressed in.**
///
/// 유저 2026-08-25, 답 1번: 「삭제·편집도 패널을 따라 대상을 바꾼다. 스토리보드
/// 에서는 스토리보드의 것을, 타임라인에서는 타임라인의 것을 지운다」 — the law
/// D28 already gave 커서·코마·＋.
///
/// ⚠️This NARROWS ⑰ (2026-08-12): 「딜리트버튼 … 컷도 마찬가지로 컷 선택하고
/// 삭제버튼누르면 컷 삭제」, whose rule was that the verb asks what is selected
/// and never which button was pressed. It still asks what is selected — what
/// the panel decides is which selections are ITS nouns, and cuts are the
/// storyboard's. Later ruling wins; the older one is not deleted, it is
/// narrowed, and both are written at the ladder.
void main() {
  EditorSessionManager sessionWithCutRange() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A CUT range, the storyboard's own selection. Under the one-selection
    // law this is the only live selection while it stands.
    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 0,
      headGlobalFrame: 1,
    );
    return session;
  }

  test('premise: the session ladder still names cuts', () {
    final session = sessionWithCutRange();
    expect(
      session.trackFrameRangeSelection.value,
      isNotNull,
      reason: 'fixture premise: a cut range is live',
    );
    expect(session.deleteSubject, DeleteSubject.cuts);
    expect(session.editInstanceSubject, EditInstanceSubject.cuts);
  });

  test('the TIMELINE panel does not reach for them', () {
    final session = sessionWithCutRange();
    final timeline = TimelineToolbarPanelContext(session);

    expect(
      timeline.deleteSubject,
      isNot(DeleteSubject.cuts),
      reason: 'a cut is not the timeline panel\'s noun — 「타임라인에서는 '
          '타임라인의 것을」',
    );
  });

  test('and its Edit does not either', () {
    final session = sessionWithCutRange();
    final timeline = TimelineToolbarPanelContext(session);

    // The gate is what the button lights on; if it lights, the press has to
    // do the timeline's thing (T25: one answer behind both).
    expect(
      session.editInstanceSubjectFor(cutsAreThisPanels: false),
      isNot(EditInstanceSubject.cuts),
    );
    // Reading it through the panel too, because the panel is what the
    // toolbar actually asks.
    expect(
      timeline.canEditInstance,
      session.editInstanceSubjectFor(cutsAreThisPanels: false) !=
          EditInstanceSubject.nothing,
    );
  });
}
