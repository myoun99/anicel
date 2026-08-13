import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨T12 — **컷 길이는 소재와 아무 관계가 없다** (유저 2026-08-13).
///
/// 「노리시로나 컷길이랑 소재랑 관계없다니까? 컷길이 넘어서도 공간은 항상
/// 존재하고 항상 보인다고. 스토리보드에서만 그걸 컷길이로 클램핑해서 보여줄
/// 뿐인거고. 이걸 몇번이나 말해야하는지」
///
/// ⛔The vocabulary is part of the law: calling the frames past the end line
/// a 「런웨이」 or 「노리시로」 quietly restores the idea that they are a
/// different KIND of place, and the special rules follow the word. The end
/// line is a line; both sides of it are the same space.
///
/// What this pins is the state the canvas reads. `editor_canvas_area` swaps
/// the layer stack for an empty one and turns off `paintPaper` when the
/// playhead is IN A GAP — that pair is what draws 「캔버스가 사라지고 이상한
/// 흰 외곽선만」 — so the question that matters is whether standing past the
/// end line is a gap. It is not, and it must stay not.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  test('standing past the cut end is NOT a gap, and the canvas keeps both '
      'its paper and its layers', () {
    final duration = session.requireActiveCut.duration;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();

    // Well past the end line, on the row's own axis.
    session.selectFrameIndex(duration + 5);
    expect(session.currentFrameIndex, duration + 5);

    expect(
      session.editingPlayheadInGap,
      isFalse,
      reason: 'a gap is "no cut here"; past the end of THIS cut is still this '
          'cut — and `inGap` is what would take the paper away',
    );
    expect(
      session.editingCanvasStack.nodes,
      isNotEmpty,
      reason: 'the void hands the canvas an empty stack; this must not be it',
    );
  });

  /// The single-cut case above is the one γ measured. A real project has
  /// neighbours, and the frames past one cut's end line are the NEXT cut's on
  /// the global axis — so this asks whether having a neighbour changes the
  /// answer.
  test('with a cut after it, past the end line is still not a gap', () {
    session.createCut();
    final cuts = session.activeTrack.cuts;
    expect(cuts.length, greaterThan(1));

    session.selectCut(cuts.first.id);
    final duration = session.requireActiveCut.duration;
    session.selectFrameIndex(duration + 4);

    expect(session.requireActiveCut.id, cuts.first.id, reason: 'still here');
    expect(session.editingPlayheadInGap, isFalse);
    expect(session.editingCanvasStack.nodes, isNotEmpty);
  });

  /// And the LAST cut's far side, which is a trailing gap on the global axis
  /// — the one place where "no cut here" is literally true.
  test('past the LAST cut, the cut-local playhead still is not in a gap', () {
    final cutId = session.requireActiveCut.id;
    final duration = session.requireActiveCut.duration;
    session.selectCut(cutId);
    session.selectFrameIndex(duration + 40);

    expect(
      session.editingPlayheadInGap,
      isFalse,
      reason: 'the cut-local seek clamps onto its own cut; only a GLOBAL seek '
          'into a gap parks, and that is a different verb',
    );
  });

  test('drawing works there, and the cut LENGTH does not move because of it', () {
    final duration = session.requireActiveCut.duration;
    session.selectFrameIndex(duration + 3);

    expect(session.canCreateDrawingAtCurrentFrame, isTrue);
    session.createDrawingAtCurrentFrame();
    expect(session.selectedFrame, isNotNull);

    expect(
      session.requireActiveCut.duration,
      duration,
      reason: '尺 is what the cut PLAYS, and it is the end-line handle that '
          'sets it — drawing past it must not quietly rewrite that number',
    );
  });
}
