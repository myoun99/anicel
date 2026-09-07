import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★R4q — A BLOCK MOVE MUST NOT DRAG THE BLOCK BEHIND IT.
///
/// 유저 스샷 (board `R4q-unify`, 2장):
///
/// | | the row |
/// |---|---|
/// | before | `1 [2 3] · 4 5 6 7` |
/// | after one cell right | `1 4 [2 3] · 5 6 7` |
///
/// The selection moved one to the right — and block `4` came with it, jumping
/// to the LEFT of the selection while the gap that used to sit between them
/// was still there to be moved into. 유저: 「뒤엣것이 한 칸 일찍 밀린다」.
///
/// ⛔A move slides the SELECTION. Anything it did not select is scenery: it
/// moves only when the selection would land on top of it, and a gap is
/// exactly the slack that says "not yet".
void main() {
  /// The row from the screenshots, in exposure indexes: a cel at 0, the pair
  /// at 1..2 that gets selected, a gap at 3, then four more from 4.
  (EditorSessionManager, Layer) row() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    for (final index in const [1, 2, 4, 5, 6, 7]) {
      s.selectFrameIndex(index);
      s.createDrawingAtCurrentFrame();
    }
    final layer = s.activeLayer!;
    return (s, s.layers.firstWhere((l) => l.id == layer.id));
  }

  List<int> exposedAt(EditorSessionManager s, Layer layer) => [
    for (final entry
        in s.layers.firstWhere((l) => l.id == layer.id).timeline.entries)
      entry.key,
  ]..sort();

  /// The DRAWINGS sitting on [at] right now — the only way to say「the pair
  /// itself moved」, because a frame index says nothing about who holds it.
  List<FrameId> frameIdsAt(
    EditorSessionManager s,
    Layer layer,
    List<int> at,
  ) => [
    for (final index in at)
      s.layers.firstWhere((l) => l.id == layer.id).timeline[index]!.frameId!,
  ];

  List<int> framesOf(EditorSessionManager s, Layer layer, List<FrameId> ids) =>
      [
        for (final entry
            in s.layers.firstWhere((l) => l.id == layer.id).timeline.entries)
          if (ids.contains(entry.value.frameId)) entry.key,
      ]..sort();

  test('the fixture is the screenshot: a gap at 3, and cels either side', () {
    // ⛔Measured first. Every claim below is about what the gap does, so a
    // fixture without one would pass while proving nothing.
    final (s, a) = row();
    expect(exposedAt(s, a), [0, 1, 2, 4, 5, 6, 7]);
  });

  test('🚨moving the pair ONE right leaves the block after the gap alone', () {
    final (s, a) = row();
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(
      exposedAt(s, a),
      [0, 2, 3, 4, 5, 6, 7],
      reason:
          '유저 스샷: the pair lands on 2..3 and 4 STAYS — the gap it used to '
          'sit before is what it just moved into. 「뒤엣것이 한 칸 일찍 '
          '밀린다」 was 4 jumping to the left of the selection instead',
    );
  });

  test('and only once the slack IS used up does the pair take that seat', () {
    // The other half of the law: the block behind is not immovable, it is
    // just not moved EARLY. One more step and the pair is standing where
    // that block was, and only then does it give way.
    //
    // ⚠️THE EXPOSURE LIST CANNOT TELL THESE APART. Both steps leave the same
    // seven frames occupied — what changes is WHO holds 4. So this asks for
    // the pair's own frames, which is the thing the law is about.
    final (s, a) = row();
    final pair = frameIdsAt(s, a, const [1, 2]);
    s.updateFrameRangeSelectionDrag(
      layerId: a.id,
      anchorIndex: 1,
      headIndex: 2,
    );
    expect(s.rangeMove.beginFrameRangeMoveDrag(), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 2);
    s.rangeMove.endFrameRangeMoveDrag();

    expect(
      framesOf(s, a, pair),
      [3, 4],
      reason:
          'two steps is one for the gap and one for the swap, so the pair '
          'now stands on 4 — which is the seat it reached, 유저: 「빈칸을 '
          '다 쓴 뒤에야 4 와 자리를 바꿉니다」',
    );
    expect(
      exposedAt(s, a),
      [0, 2, 3, 4, 5, 6, 7],
      reason:
          'and the block it passed gave way BEHIND it rather than being '
          'bulldozed forward — nothing was lost and nothing was pushed',
    );
  });
}
