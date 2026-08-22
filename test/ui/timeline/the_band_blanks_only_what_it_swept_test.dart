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

/// 🚨결정 14 ①ⓑ (유저 확정 2026-08-22) — **X BLANKS EXACTLY WHAT WAS SWEPT.**
///
/// The playhead X truncates: it cuts the covering block off at the pressed
/// frame and everything past it goes uncovered. Over a BAND that would blank
/// past the sweep — a block running 0..5 swept at 1..3 would lose 4 and 5 as
/// well — and the user chose the other reading: the swept cells go empty and
/// the block's tail stays exactly where it stands.
///
/// ⛔Nothing shifts. That is what separates X from 잘라내기, which lifts the
/// cells and drags the tail back.
void main() {
  const idA = LayerId('band-a');
  const idB = LayerId('band-b');

  /// One block per row, six frames long, so a sweep in the middle leaves a
  /// head AND a tail — the case that tells the two readings apart.
  Layer sixFrameRow(LayerId id) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.animation,
    frames: [
      Frame(id: FrameId('${id.value}-cel'), duration: 6, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('${id.value}-cel'), length: 6),
    },
  );

  (EditorSessionManager, List<LayerId>) rig() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('band-blank'),
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
                duration: 10,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [sixFrameRow(idA), sixFrameRow(idB)],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return (session, const [idA, idB]);
  }

  /// Which frames of [id] are COVERED — the only question X answers, and the
  /// one a length-plus-start reading gets wrong when a block is split.
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

  test('presence first: both rows are covered 0..5', () {
    final (session, ids) = rig();
    for (final id in ids) {
      expect(coveredFrames(session, id), [0, 1, 2, 3, 4, 5]);
    }
  });

  test('a sweep in the middle leaves the head AND the tail standing', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 4);
    expect(session.canBlankExposureForSelection, isTrue);
    session.blankExposureAtCurrentFrame();

    for (final id in ids) {
      expect(
        coveredFrames(session, id),
        [0, 4, 5],
        reason: '①ⓑ — 1·2·3만 비고 4·5는 제자리. 옛 X의 뜻(가장 이른 칸부터 '
            '블록 끝까지)이었다면 [0]만 남았을 것이다',
      );
    }
  });

  test('the tail re-opens on the SAME cel, not a new drawing', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 4);
    session.blankExposureAtCurrentFrame();

    final layer = session.layers.firstWhere((l) => l.id == ids.first);
    expect(layer.timeline[4]?.frameId, FrameId('${ids.first.value}-cel'));
    expect(
      layer.frames,
      hasLength(1),
      reason: 'two entries on ONE cel is linked reuse, which the model '
          'already has — blanking must not mint a second drawing',
    );
  });

  test('a sweep that runs off the block only eats the overlap', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 4, toExclusive: 9);
    session.blankExposureAtCurrentFrame();
    expect(
      coveredFrames(session, ids.first),
      [0, 1, 2, 3],
      reason: 'the span reaches past the block; frames 6..8 were never '
          'covered and there is nothing there to blank',
    );
  });

  test('a sweep that swallows the block whole leaves the row empty', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 0, toExclusive: 6);
    session.blankExposureAtCurrentFrame();
    for (final id in ids) {
      expect(coveredFrames(session, id), isEmpty);
    }
  });

  test('one press is ONE undo across every swept row', () {
    final (session, ids) = rig();
    sweep(session, ids, from: 1, toExclusive: 4);
    session.blankExposureAtCurrentFrame();
    expect(coveredFrames(session, ids.first), [0, 4, 5]);
    expect(coveredFrames(session, ids[1]), [0, 4, 5]);

    session.undo();
    for (final id in ids) {
      expect(
        coveredFrames(session, id),
        [0, 1, 2, 3, 4, 5],
        reason: 'both rows moved together, so both come back together',
      );
    }
  });

  test('a band naming only rows with nothing covered is a NO-OP', () {
    final (session, ids) = rig();
    // Frames 6..9 are past both blocks.
    sweep(session, ids, from: 6, toExclusive: 9);
    expect(session.canBlankExposureForSelection, isFalse);
    session.blankExposureAtCurrentFrame();
    for (final id in ids) {
      expect(coveredFrames(session, id), [0, 1, 2, 3, 4, 5]);
    }
  });

  test('with no band the playhead X still truncates, unchanged', () {
    final (session, ids) = rig();
    session.selectLayer(ids.first);
    session.selectFrameIndex(3);
    session.clearFrameRangeSelection();

    expect(session.canBlankExposureAtCurrentFrame, isTrue);
    session.blankExposureAtCurrentFrame();
    expect(
      coveredFrames(session, ids.first),
      [0, 1, 2],
      reason: 'the single-row rung is untouched — X there still cuts the '
          'block off at the playhead, which is what it has always meant',
    );
    expect(coveredFrames(session, ids[1]), [0, 1, 2, 3, 4, 5]);
  });
}
