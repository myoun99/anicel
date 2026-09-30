import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🗣️유저 2026-08-10: 「움직일때만 앵커로서 앞 컷에 앵커. 앞 컷이 없으면 현재
/// 컷에 앵커.」 — through the doors a cut really moves by.
///
/// Three 24-frame cuts z, a, b and an O.L over 42..53 across a|b. Every
/// edit that moves a carries the O.L with it, in the same undo step; an
/// undo puts it back where it stood.
void main() {
  const z = CutId('z');
  const a = CutId('a');

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut('z'), cut('a'), cut('b')],
          ),
        ],
      ),
    );
    s.transitions.updateTransitionInstructions({
      42: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    return s;
  }

  int olStart(EditorSessionManager s) =>
      s.activeTrack.transitionLayer.instructions.keys.single;

  int startOf(EditorSessionManager s, CutId id) {
    var frame = 0;
    for (final cut in s.activeTrack.cuts) {
      frame += cut.leadingGapFrames;
      if (cut.id == id) {
        return frame;
      }
      frame += cut.duration;
    }
    throw StateError('no cut $id');
  }

  /// [edit] moves a by some frames; the O.L moves by the same, and one undo
  /// takes both back (a redo brings both again).
  void ridesWithA(EditorSessionManager s, void Function() edit) {
    final aBefore = startOf(s, a);
    edit();
    final moved = startOf(s, a) - aBefore;
    expect(moved, isNot(0), reason: 'the edit moves the O.L\'s front cut');
    expect(olStart(s), 42 + moved);
    s.historyManager.undo();
    expect(startOf(s, a), aBefore);
    expect(olStart(s), 42);
    s.historyManager.redo();
    expect(olStart(s), 42 + moved);
  }

  test('a trim of the cut before it', () {
    final s = session();
    addTearDown(s.dispose);
    ridesWithA(
      s,
      () => s.cutCommandCoordinator.commitCutDurationDrag(
        beforeDurations: {z: 24},
        afterDurations: {z: 20},
      ),
    );
  });

  // 🗣️유저 2026-09-30 (F-227-ol-trim-Q1): 「경계를 따라간다」.
  test('its front cut\'s own end trimmed: the O.L follows the boundary — '
      'one undo takes both back', () {
    final s = session();
    addTearDown(s.dispose);
    s.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {a: 24},
      afterDurations: {a: 20},
    );
    expect(olStart(s), 38, reason: 'a|b moved back four, and six stay each side');
    s.historyManager.undo();
    expect(olStart(s), 42);
    s.historyManager.redo();
    expect(olStart(s), 38);
  });

  test('its front cut moved along the track', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(a);
    ridesWithA(s, s.cutVerbs.moveActiveCutRight);
  });

  test('a new cut made in front of it', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(z);
    ridesWithA(s, s.cutVerbs.createCut);
  });

  test('a duplicate lands at the track\'s end — nothing in front of the O.L '
      'moves, so the O.L stays, and its undo too', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(z);
    s.cutVerbs.duplicateActiveCut();
    expect(s.activeTrack.cuts.length, 4);
    expect(olStart(s), 42);
    s.historyManager.undo();
    expect(olStart(s), 42);
  });

  test('a linked cut made in front of it', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(z);
    ridesWithA(s, s.cutVerbs.createLinkedCutFromActiveCut);
  });

  test('a trim still under the hand shows the O.L where the release will '
      'carry it — the same function, so it never jumps on release', () {
    final s = session();
    addTearDown(s.dispose);
    final previewed = projectWithTimelineDragPreview(
      s.repository.requireProject(),
      CutTrimDragPreview(previewDurations: {z: 20}),
    );
    expect(
      previewed.tracks.single.transitionLayer.instructions.keys.single,
      38,
    );
  });

  test('its front cut deleted: the gap keeps b where it was, so the O.L '
      'stays, now joining the gap to b — and the undo keeps it there', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(a);
    s.cutVerbs.deleteActiveCut();
    expect(olStart(s), 42);
    s.historyManager.undo();
    expect(olStart(s), 42);
  });
}
