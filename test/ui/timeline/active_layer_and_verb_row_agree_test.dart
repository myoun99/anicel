import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// F-20 — **the verb row names the active layer.**
///
/// 유저 2026-08-24: 「새 레이어를 만들어도 내부 액티브 레이어가 안 바뀐다 —
/// 증거: 그 상태에서 아래 화살표를 누르면 바로 밑이 아니라 밑의 밑이 선택된다.
/// … 🚨UI만 바꾸고 내부를 안 바꾸는 자리가 더 있는지 전수 점검」.
///
/// `_rebuildActiveCutControllers` is the ONE place the active layer moves
/// without [EditorSessionManager.selectLayer] — a fresh `LayerController` is
/// seated with `initialActiveLayerId`, and `selectLayer`, which is where the
/// verb row is kept in step, never runs. So after Add Layer the active layer
/// was the new row and the verb row was still the old one: ↓ counted from the
/// old row and landed a row further than it looked.
void main() {
  EditorSessionManager sessionFor() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('adding a layer moves the verb row with the active layer', () {
    final session = sessionFor();
    final before = session.activeLayerId;
    expect(before, isNotNull, reason: 'fixture premise');
    // 🚨THE PREMISE THIS TEST WAS MISSING (measured 2026-09-07): with
    // nothing ever picked, the verb row is unset and `currentRow` falls
    // back to the active layer — so the seating below could be deleted and
    // this still passed. Standing on a row first is what makes the stale
    // row possible at all.
    session.selectLayer(before!);
    expect(session.currentRow, LayerRowAddress(before));

    session.layerStack.addLayer();

    final active = session.activeLayerId;
    expect(
      active,
      isNot(before),
      reason: 'fixture premise: the new row becomes active',
    );
    expect(
      session.currentRow,
      LayerRowAddress(active!),
      reason: 'the walk that ↓ does starts from currentRow, so a row left '
          'behind on the old layer steps one row too far',
    );
  });

  test('and deleting one leaves them agreeing too', () {
    final session = sessionFor();
    session.layerStack.addLayer();

    session.deleteActiveLayer();

    final active = session.activeLayerId;
    expect(active, isNotNull);
    expect(session.currentRow, LayerRowAddress(active!));
  });
}
