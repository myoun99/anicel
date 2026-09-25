import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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

    session.layerVerbs.deleteActiveLayer();

    final active = session.activeLayerId;
    expect(active, isNotNull);
    expect(session.currentRow, LayerRowAddress(active!));
  });

  /// F-183 ③ (유저 2026-09-26): 「어태치 프리 레이어 만들고 난 직후 … 기존의
  /// 어태치 레이어? 그 블록을 따라 플립됨 … 아래버튼 누르니 아래 레이어로 가는게
  /// 아니라 아래의 아래 레이어로 이동함. 즉 서있는 레이어 기준이 과거인거같음.
  /// 근본/구조적으로 해결」 — F-20's symptom, through a door F-20 did not
  /// cover. Every door that MOVES the active layer is here by name; the
  /// verbs' row follows them all at the session's announcement
  /// (`Standing.followActiveLayer`), so none has to remember it.
  group('every door that makes a row stands the verbs on it', () {
    final doors = <String, void Function(EditorSessionManager session)>{
      'add layer': (s) => s.layerStack.addLayer(),
      'attach free above': (s) => s.folders.addAttachedLayer(
        AttachedPlacement.above,
        mode: AttachedMode.free,
      ),
      'attach free below': (s) => s.folders.addAttachedLayer(
        AttachedPlacement.below,
        mode: AttachedMode.free,
      ),
      'attach synced above': (s) =>
          s.folders.addAttachedLayer(AttachedPlacement.above),
      'attach synced below': (s) =>
          s.folders.addAttachedLayer(AttachedPlacement.below),
      // (A LINK duplicate keeps its source active — it moves nothing to
      // follow, and is not in this list for that reason.)
      'duplicate': (s) => s.layerVerbs.duplicateActiveLayer(),
      'paste': (s) {
        s.layerClipboard.copyActiveLayer();
        s.layerClipboard.pasteLayerFromClipboard();
      },
    };
    for (final door in doors.entries) {
      test(door.key, () {
        final session = sessionFor();
        final before = session.activeLayerId!;
        session.selectLayer(before);
        expect(session.currentRow, LayerRowAddress(before), reason: 'premise');

        door.value(session);

        final made = session.activeLayerId;
        expect(made, isNot(before), reason: 'premise: the door made a row');
        expect(
          session.currentRow,
          LayerRowAddress(made!),
          reason: 'the flip and ↓ start from currentRow',
        );
      });
    }

    test('a block landing on another row takes the verbs with it', () {
      final session = sessionFor();
      session.createDrawingAtCurrentFrame();
      final from = session.activeLayerId!;
      session.layerStack.addLayer();
      final onto = session.activeLayerId!;
      session.selectLayer(from);
      expect(session.currentRow, LayerRowAddress(from), reason: 'premise');

      session.drawingBlockMove.beginDrawingBlockMoveDrag(
        layerId: from,
        blockStartIndex: 0,
      );
      session.drawingBlockMove.updateDrawingBlockMoveDrag(
        frameDelta: 1,
        targetLayerId: onto,
      );
      session.drawingBlockMove.endDrawingBlockMoveDrag();

      expect(session.activeLayerId, onto, reason: 'premise: R12-④');
      expect(session.currentRow, LayerRowAddress(onto));
    });

    test('standing on ANOTHER layer\'s lane keeps the lane — the row is the '
        'new active layer\'s own', () {
      final session = sessionFor();
      final first = session.activeLayerId!;
      session.layerStack.addLayer();
      final second = session.activeLayerId!;
      session.selectLayer(first);
      final lane = LaneRowAddress(second, 'position');

      session.standOnRow(lane);

      expect(session.activeLayerId, lane.layerId, reason: 'premise: it moved');
      expect(session.currentRow, lane);
    });
  });
}
