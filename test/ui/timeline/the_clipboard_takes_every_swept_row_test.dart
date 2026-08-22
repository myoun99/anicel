import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨결정 14 ②ⓐ (유저 확정 2026-08-22) — **THE CLIPBOARD TAKES EVERY SWEPT
/// ROW.**
///
/// > 「지우기 눌렀다고해서 현재 행만 지우는게아니라 **선택된 모든게**
/// > 지워지는걸 말하는거임. **복사든 뭐든 마찬가지**」
///
/// ⛔This half had to come SECOND. A cut that lifts three rows while the
/// paste can only restore one is a clipboard that loses two rows of work, so
/// the paste learned the band first (③ⓐ) and the taking follows.
void main() {
  const rowA = LayerId('a');
  const rowB = LayerId('b');

  Layer drawn(LayerId id, String cel) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId(cel), duration: 3, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId(cel), length: 3)},
  );

  EditorSessionManager rig() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('clip-band'),
        name: 'Clip',
        createdAt: DateTime.utc(2026, 8, 22),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut-1'),
                name: '1',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                // Distinct cels per row, so a paste that mixed them up is
                // visible rather than merely plausible.
                layers: [drawn(rowA, 'cel-a'), drawn(rowB, 'cel-b')],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  List<int> coveredFrames(EditorSessionManager session, LayerId id) {
    final layer = session.layers.firstWhere((l) => l.id == id);
    final covered = <int>[];
    for (final entry in layer.timeline.entries) {
      if (!entry.value.isDrawing) {
        continue;
      }
      for (var i = 0; i < (entry.value.length ?? 1); i += 1) {
        covered.add(entry.key + i);
      }
    }
    return covered..sort();
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

  test('presence first: both rows carry their own three-frame block', () {
    final session = rig();
    expect(coveredFrames(session, rowA), [0, 1, 2]);
    expect(coveredFrames(session, rowB), [0, 1, 2]);
  });

  test('a CUT over a two-row band lifts both rows, in one undo', () {
    final session = rig();
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    sweep(session, const [rowA, rowB], from: 0, toExclusive: 3);

    session.cutRunAtCurrentFrame();
    expect(coveredFrames(session, rowA), isEmpty);
    expect(
      coveredFrames(session, rowB),
      isEmpty,
      reason: '「선택된 모든게」 — the unswept-active-row rule is not the '
          'point here; BOTH rows were swept',
    );

    session.undo();
    expect(coveredFrames(session, rowA), [0, 1, 2]);
    expect(
      coveredFrames(session, rowB),
      [0, 1, 2],
      reason: 'both come back together — two undo steps for one press is '
          'what the shared splice exists to prevent',
    );
  });

  test('🚨cut-then-paste puts BOTH rows back — the lift never exceeds what '
      'the board holds', () {
    final session = rig();
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    sweep(session, const [rowA, rowB], from: 0, toExclusive: 3);
    session.cutRunAtCurrentFrame();
    expect(coveredFrames(session, rowA), isEmpty);
    expect(coveredFrames(session, rowB), isEmpty);

    // Paste back at frame 5, across the same two rows.
    session.selectLayer(rowA);
    session.selectFrameIndex(5);
    sweep(session, const [rowA, rowB], from: 5, toExclusive: 8);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(
      coveredFrames(session, rowA),
      contains(5),
      reason: 'row A came back',
    );
    final b = session.layers.firstWhere((l) => l.id == rowB);
    expect(
      b.timeline[5]?.frameId,
      const FrameId('cel-b'),
      reason: '⛔row B is the whole point, and its CEL is how the failure '
          'shows. A cut that banks one row and lifts two loses B — and the '
          'loss HIDES, because a one-row board replicates the anchor to '
          'every swept row (③ⓐ), so B comes back wearing A\'s drawing and '
          'the frame count alone reads as recovered',
    );
  });

  test('each row gets ITS OWN clip back, not the anchor\'s', () {
    final session = rig();
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    sweep(session, const [rowA, rowB], from: 0, toExclusive: 3);
    session.copyFrameAtCurrentFrame();

    session.selectFrameIndex(5);
    sweep(session, const [rowA, rowB], from: 5, toExclusive: 8);
    session.pasteLinkedFrameAtCurrentFrame();

    final a = session.layers.firstWhere((l) => l.id == rowA);
    final b = session.layers.firstWhere((l) => l.id == rowB);
    expect(a.timeline[5]?.frameId, const FrameId('cel-a'));
    expect(
      b.timeline[5]?.frameId,
      const FrameId('cel-b'),
      reason: '⛔row B must receive B\'s cel. Replicating the anchor across '
          'a multi-row board would silently overwrite one row with another '
          'row\'s drawing — the pairing is what preserves what was copied',
    );
  });

  test('a ONE-row board still fills every swept row (③ⓐ survives)', () {
    final session = rig();
    // Copy row A ALONE — no band, so the board holds one row.
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    session.clearFrameRangeSelection();
    session.copyFrameAtCurrentFrame();

    session.selectFrameIndex(5);
    sweep(session, const [rowA, rowB], from: 5, toExclusive: 8);
    session.pasteLinkedFrameAtCurrentFrame();

    for (final id in const [rowA, rowB]) {
      final layer = session.layers.firstWhere((l) => l.id == id);
      expect(
        layer.timeline[5]?.frameId,
        const FrameId('cel-a'),
        reason: '$id receives the single banked row — 「모든 행에 같은 것을」',
      );
    }
  });

  test('with no band at all, copy banks exactly one row and cut lifts one',
      () {
    final session = rig();
    session.selectLayer(rowA);
    session.selectFrameIndex(0);
    session.clearFrameRangeSelection();

    session.cutRunAtCurrentFrame();
    expect(coveredFrames(session, rowA), isEmpty);
    expect(
      coveredFrames(session, rowB),
      [0, 1, 2],
      reason: 'no band means no other row — the single-row cut is the same '
          'code path, not a branch beside it',
    );
  });
}
