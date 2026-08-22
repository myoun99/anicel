import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨결정 9 / R8-c (유저 확정 2026-08-22) — **THE MARK LEARNED THE BAND.**
///
/// > 「지우기 눌렀다고해서 **현재 행만 지우는게아니라 선택된 모든게 지워지는걸**
/// > 말하는거임. **복사든 뭐든 마찬가지**」
///
/// The ● used to END the ladder at a live band: it could only reach the
/// active row, and dotting that row while the highlight sat on another was
/// an edit nobody swept. Refusing was the honest answer for a verb with one
/// row of reach. Now it has the band's, so serving it is.
///
/// ⚠️It SETS, never toggles each frame. A band holding a mix would otherwise
/// invert under the hand and hand back the complement of what was there —
/// the one outcome nobody presses a button for.
void main() {
  const idA = LayerId('band-a');
  const idB = LayerId('band-b');

  /// Two drawing rows, each ONE block four frames long. A mark lives on a
  /// HELD frame ([TimelineController.canToggleMarkAt] refuses the head), so
  /// a row of single-frame cels has nothing to mark and would make every pin
  /// below vacuously true — the presence test says so out loud.
  Layer heldRow(LayerId id) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('${id.value}-cel'), duration: 4, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('${id.value}-cel'), length: 4),
    },
  );

  (EditorSessionManager, List<LayerId>) rig() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('band-mark'),
        name: 'Band',
        createdAt: DateTime.utc(2026, 8, 22),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut-1'),
                name: '1',
                duration: 8,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [heldRow(idA), heldRow(idB)],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return (session, const [idA, idB]);
  }

  List<int> marksOf(EditorSessionManager session, LayerId id) {
    final layer = session.layers.firstWhere((l) => l.id == id);
    final entry = layer.timeline[0];
    return entry == null
        ? const []
        : [...entry.breakdownOffsets]
      ..sort();
  }

  void sweep(
    EditorSessionManager session,
    List<LayerId> ids, {
    required int from,
    required int toExclusive,
  }) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: ids.first,
      startIndex: from,
      endIndexExclusive: toExclusive,
      layerIds: ids,
    );
  }

  test('the fixture really holds markable frames (presence first)', () {
    final (session, ids) = rig();
    for (final id in ids) {
      final layer = session.layers.firstWhere((l) => l.id == id);
      expect(
        layer.timeline[0]?.length,
        4,
        reason: 'a four-frame hold, so frames 1..3 can take a mark',
      );
      expect(marksOf(session, id), isEmpty);
    }
  });

  test('one press marks every swept frame of EVERY swept row', () {
    final (session, ids) = rig();
    // Stand on the FIRST row and sweep both: the point of the round is that
    // the press follows the band and not the active row.
    session.selectLayer(ids.first);
    sweep(session, ids, from: 1, toExclusive: 3);

    expect(session.canToggleMarkForSelection, isTrue);
    session.toggleMarkAtCurrentFrame();

    for (final id in ids) {
      expect(
        marksOf(session, id),
        [1, 2],
        reason: 'both swept frames of $id — 「선택된 모든게」, and the row '
            'that is not active is the one the old ladder could not reach',
      );
    }
  });

  test('several swept frames in ONE block all survive the same press', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 4);
    session.toggleMarkAtCurrentFrame();
    expect(
      marksOf(session, ids.first),
      [1, 2, 3],
      reason: 'they share one timeline entry, so each write has to see the '
          'marks the ones before it made — off the ORIGINAL entry the last '
          'write would win and the first two would vanish',
    );
  });

  test('a mixed band goes one way: anything unmarked marks them all', () {
    final (session, ids) = rig();
    // Mark frame 1 of the first row alone, through the band.
    sweep(session, [ids.first], from: 1, toExclusive: 2);
    session.toggleMarkAtCurrentFrame();
    expect(marksOf(session, ids.first), [1]);

    // Now sweep 1..3 across both rows: the band is MIXED.
    sweep(session, ids, from: 1, toExclusive: 3);
    session.toggleMarkAtCurrentFrame();
    for (final id in ids) {
      expect(
        marksOf(session, id),
        [1, 2],
        reason: 'a mixed band FILLS. Toggling each frame would have cleared '
            'frame 1 and set frame 2 — the complement of what was there',
      );
    }
  });

  test('an all-marked band clears', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 3);
    session.toggleMarkAtCurrentFrame();
    expect(marksOf(session, ids.first), [1, 2]);

    session.toggleMarkAtCurrentFrame();
    for (final id in ids) {
      expect(marksOf(session, id), isEmpty, reason: 'the second press clears');
    }
  });

  test('one press is ONE undo', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 3);
    session.toggleMarkAtCurrentFrame();
    expect(marksOf(session, ids.first), [1, 2]);
    expect(marksOf(session, ids[1]), [1, 2]);

    session.undo();
    for (final id in ids) {
      expect(
        marksOf(session, id),
        isEmpty,
        reason: 'both rows moved together, so both come back together — two '
            'undo steps for one press is the shape this round exists to '
            'avoid',
      );
    }
  });

  test('a band holding nothing markable is a NO-OP, never a redirect', () {
    final (session, ids) = rig();
    session.selectLayer(ids.first);
    // Frame 0 is the block HEAD, which cannot take a mark. The band names a
    // row and holds nothing this verb may touch.
    sweep(session, [ids[1]], from: 0, toExclusive: 1);

    expect(session.canToggleMarkForSelection, isFalse);
    expect(
      session.canToggleMarkAtCurrentFrame,
      isFalse,
      reason: '⛔the press must NOT fall through onto the active row — a cell '
          'drag never moves the active layer, so the swept row and the '
          'active row are routinely different ones',
    );
    session.toggleMarkAtCurrentFrame();
    for (final id in ids) {
      expect(marksOf(session, id), isEmpty);
    }
  });

  test('with no band at all the playhead press still works', () {
    final (session, ids) = rig();
    session.selectLayer(ids.first);
    session.selectFrameIndex(2);
    session.clearFrameRangeSelection();

    expect(session.canToggleMarkAtCurrentFrame, isTrue);
    session.toggleMarkAtCurrentFrame();
    expect(marksOf(session, ids.first), [2]);
    expect(
      marksOf(session, ids[1]),
      isEmpty,
      reason: 'the old single-row rung is untouched — this round ADDED reach',
    );
  });
}
