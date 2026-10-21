import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// F-352 — a paste keeps the cut on its conte row by the comma's law
/// (`the_comma_buttons_keep_the_cut_on_its_row_test.dart`): the cut ends
/// where the row ends. So does every verb the paste shares its splice with
/// — the cut, the duplicate.
///
/// 유저 2026-10-12: 「다른 컷에 있던 콘티블록 복붙하니까 이렇게됨. 콘티레이어는
/// 엔드라인이랑 같은 길이? 클리핑되야하는데 넘어서버림. 복붙할때 필요한 공간에
/// 맞춰서 엔드라인 늘리는것도 같이하도록. 같이한다기보다 근본/구조적으로
/// 그렇게 되도록.」
void main() {
  /// The default project's cut (24 frames) with a conte row divided at
  /// frame 5: {0: 5, 5: 19}.
  (EditorSessionManager, LayerId) scene() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final conte = addConteRow(session);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    expect(rowOf(session, conte), {0: 5, 5: 19}, reason: 'fixture');
    expect(session.requireActiveCut.duration, 24, reason: 'fixture');
    return (session, conte);
  }

  void select(
    EditorSessionManager session,
    LayerId row,
    int start,
    int endExclusive,
  ) {
    session.selectLayer(row);
    session.selectFrameIndex(start);
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row,
      startIndex: start,
      endIndexExclusive: endExclusive,
    );
  }

  void stand(EditorSessionManager session, LayerId row, int frameIndex) {
    session.clearTimelineSelections();
    session.selectLayer(row);
    session.selectFrameIndex(frameIndex);
  }

  test('a panel from ANOTHER cut pasted on this cut\'s conte row takes the '
      'end line out with it — the paste the user made', () {
    final (session, first) = scene();
    select(session, first, 5, 24);
    session.copyFrameAtCurrentFrame();

    session.cutVerbs.createCut();
    final second = addConteRow(session);
    final length = session.requireActiveCut.duration;
    stand(session, second, 0);
    session.pasteIndependentFrameAtCurrentFrame();

    expect(rowOf(session, second), {0: 19, 19: length});
    expect(session.requireActiveCut.duration, 19 + length);
  });

  test('a panel pasted inside the row pushes the cut out to the row\'s new '
      'end, and one undo takes both back', () {
    final (session, conte) = scene();
    select(session, conte, 0, 5);
    session.copyFrameAtCurrentFrame();
    stand(session, conte, 5);

    session.pasteIndependentFrameAtCurrentFrame();

    expect(rowOf(session, conte), {0: 5, 5: 5, 10: 19});
    expect(session.requireActiveCut.duration, 29);

    session.undo();

    expect(rowOf(session, conte), {0: 5, 5: 19});
    expect(session.requireActiveCut.duration, 24);
  });

  test('a linked paste answers the same', () {
    final (session, conte) = scene();
    select(session, conte, 0, 5);
    session.copyFrameAtCurrentFrame();
    stand(session, conte, 5);

    session.pasteLinkedFrameAtCurrentFrame();

    expect(rowOf(session, conte), {0: 5, 5: 5, 10: 19});
    expect(session.requireActiveCut.duration, 29);
  });

  // The playhead past the new end comes back inside: the tidy-up a cut
  // command owes, the comma's own ending.
  test('a shorter panel put in a longer one\'s place draws the cut in, and '
      'the playhead with it', () {
    final (session, conte) = scene();
    select(session, conte, 0, 5);
    session.copyFrameAtCurrentFrame();
    select(session, conte, 5, 24);
    session.selectFrameIndex(20);

    session.pasteIndependentFrameAtCurrentFrame();

    expect(rowOf(session, conte), {0: 5, 5: 5});
    expect(session.requireActiveCut.duration, 10);
    expect(playheadOf(session), 9);
  });

  test('a panel cut out of the row draws the cut in after it, and the '
      'playhead with it', () {
    final (session, conte) = scene();
    select(session, conte, 0, 5);
    session.selectFrameIndex(20);

    session.clipboard.cutRunAtCurrentFrame();

    expect(rowOf(session, conte), {0: 19});
    expect(session.requireActiveCut.duration, 19);
    expect(playheadOf(session), 18);

    session.undo();

    expect(rowOf(session, conte), {0: 5, 5: 19});
    expect(session.requireActiveCut.duration, 24);
  });

  test('a duplicated panel pushes the cut out', () {
    final (session, conte) = scene();
    stand(session, conte, 0);

    session.frameVerbs.duplicateActiveBlock(linked: false);

    expect(rowOf(session, conte), {0: 5, 5: 5, 10: 19});
    expect(session.requireActiveCut.duration, 29);
  });

  test('⛔a drawing row\'s paste still leaves the cut alone', () {
    final (session, _) = scene();
    final cel = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    stand(session, cel, 0);
    session.createDrawingAtCurrentFrame();
    select(session, cel, 0, 1);
    session.copyFrameAtCurrentFrame();
    stand(session, cel, 23);

    session.pasteIndependentFrameAtCurrentFrame();
    session.pasteIndependentFrameAtCurrentFrame();

    expect(session.requireActiveCut.duration, 24);
  });
}

/// A conte row added to the active cut, the cut's own.
LayerId addConteRow(EditorSessionManager session) {
  session.layerStack.addLayerOfKind(LayerKind.storyboard);
  return storyboardLayerForCut(session.requireActiveCut)!.id;
}

int playheadOf(EditorSessionManager session) =>
    session.activeCutControllers.timelineController.currentFrameIndex;

Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => session
    .layers
    .firstWhere((layer) => layer.id == id)
    .timeline
    .map((key, value) => MapEntry(key, value.length));
