import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;

/// 🚨A5-2 · 결정 6 (유저 확정 2026-08-22) — **THE CARET STANDS WHERE THE ROW
/// CAN ACTUALLY LAND.**
///
/// > 「놓을 수 없는 곳엔 선을 안 그리고, 커서가 넘어가면 **갈 수 있는 마지막
/// > 자리에 붙여둔다** — 전 섹션 공통」
///
/// The rail already refused to DRAW a caret it had called illegal (the
/// painter gates on `legal`), so the half that was actually missing was the
/// clamp: past the last landing the line did not stay put, it vanished, and
/// the drag looked dead while it was merely being asked for something it
/// could not do. Pinning to the nearest landing makes the first half moot
/// rather than implementing it twice — there is no "illegal caret" state
/// left to hide.
///
/// ⛔The clamp stops AT the row's own place. A run owns the gaps at both its
/// ends and putting it back there is not a landing (④, 2026-08-12), so
/// "nothing legal between the cursor and home" still draws nothing — which
/// the first test pins, because a clamp that walked past home would announce
/// a move on the far side of a drag that has gone nowhere.
void main() {
  /// Three drawing rows under the instruction/transition/camera block, so
  /// the drawing section has somewhere to go AND a boundary to be pushed
  /// past. The default project supplies the sections; the two extra rows
  /// are what make a legal landing exist at all.
  ///
  /// Stack (bottom → top), MEASURED rather than assumed:
  ///   0 default-layer-1 (animation)  ← the one dragged
  ///   1,2 two more animation rows
  ///   3 instruction · 4 transition · 5 camera · 6,7 se
  (EditorSessionManager, LayerId) rig() {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    session.addLayerOfKind(LayerKind.animation);
    session.addLayerOfKind(LayerKind.animation);
    final bottom = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    expect(
      session.layers.where((l) => l.kind == LayerKind.animation).length,
      3,
      reason: 'the fixture needs a section with room to move inside it',
    );
    return (session, bottom.id);
  }

  ({int? caret, bool legal}) caretAt(EditorSessionManager session, int slot) {
    session.updateLayerRowDrag(session.layers, slot);
    final state = session.layerRowDrag.value;
    return (caret: state?.caretSlot, legal: state?.legal ?? false);
  }

  test('past the last landing the caret STAYS on it instead of vanishing', () {
    final (session, bottom) = rig();
    session.beginLayerRowDrag(LayerRowSubject(bottom));
    addTearDown(session.cancelLayerRowDrag);

    // The two landings the drawing section actually offers this row.
    expect(caretAt(session, 2), (caret: 2, legal: true));
    expect(caretAt(session, 3), (caret: 3, legal: true));

    // Everything above is another section, and the answer is the same one
    // every time: the last place it could go. ⚠️Every slot to the top of the
    // list, not just the first one past the boundary — 「전 섹션 공통」 means
    // the caret cannot come loose again further up.
    for (var slot = 4; slot <= session.layers.length; slot += 1) {
      expect(
        caretAt(session, slot),
        (caret: 3, legal: true),
        reason: 'slot $slot is out of the section — 갈 수 있는 마지막 자리에 '
            '붙여둔다 (결정 6). Before this rule the caret went dark here.',
      );
    }
  });

  test('between the cursor and the row own place there is nothing to draw', () {
    final (session, bottom) = rig();
    session.beginLayerRowDrag(LayerRowSubject(bottom));
    addTearDown(session.cancelLayerRowDrag);

    // The bottom row sits at index 0, so slots 0 and 1 are the gaps it
    // already occupies. ④ removed the caret there deliberately — a drag
    // that has gone nowhere must not announce a move — and the clamp must
    // not bring it back by walking through home to the other side.
    expect(caretAt(session, 0).legal, isFalse);
    expect(caretAt(session, 1).legal, isFalse);
  });

  test('the clamped caret is what RELEASING commits', () {
    final (session, bottom) = rig();
    final before = [for (final layer in session.layers) layer.id.value];
    session.beginLayerRowDrag(LayerRowSubject(bottom));
    // Dropped far past the section — the caret says slot 3, so slot 3 is
    // what has to happen. A caret that pinned for the eye only would be a
    // second answer to a question this drag already answered once.
    caretAt(session, session.layers.length);
    session.endLayerRowDrag();

    final after = [for (final layer in session.layers) layer.id.value];
    expect(after, isNot(before), reason: 'the release really moved it');
    expect(
      after.indexOf(bottom.value),
      2,
      reason: 'landing at slot 3 lifts the row out first, so it settles at '
          'index 2 — the top of its own section, never above it',
    );
    expect(
      after.sublist(3),
      before.sublist(3),
      reason: 'and nothing outside the drawing section moved',
    );
  });
}
