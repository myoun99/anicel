import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/controllers/timeline_controller.dart';

import '../helpers/run_edge_fixtures.dart';

/// 🗣️F-227 (유저 2026-09-29): 「타임라인패널에서도 홀드같은게 빨간엔드라인에서
/// 끝나는게아니라 여백엔드라인까지 가도록, 거기가 진짜 엔드라인이라는 느낌」.
///
/// A hold is "this picture until the end", and once an O.L asks a cut for
/// のりしろ the end is the DRAWN end. Stopping at the red line is what left
/// the leaving cut nothing to show through the second half of its own O.L —
/// 「컷1이 fo하다가 갑자기 컷2가 fi하는 상태」.
///
/// Measured through the REPOSITORY, because the drawn end moves without the
/// cut being touched: an O.L drawn or removed, a neighbour trimmed.
void main() {
  const trackId = TrackId('t');
  const leaving = CutId('a');
  const arriving = CutId('b');

  /// A row whose one 4-frame block HOLDS to the end.
  Layer heldRow(String id, {LayerKind kind = LayerKind.animation}) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(
        FrameId('$id-cel'),
        length: kind == LayerKind.image ? 1 : 4,
        endEdge: holdMark,
      ),
    },
  );

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: layers,
  );

  /// The track's transition row carrying an O.L over `[start, start + 12)`.
  Layer olRow(Track track, int start) => track.transitionLayer.copyWith(
    instructions: {
      start: const InstructionEvent(instructionId: 'ol', length: 12),
    },
  );

  /// Two 24-frame cuts; an O.L over frames 18..29 when [olAt] is given —
  /// six frames of のりしろ past the leaving cut's end, six before the
  /// arriving cut's start.
  ProjectRepository repositoryWith({
    int? olAt,
    List<Layer>? leavingRows,
  }) {
    final track = Track(
      id: trackId,
      name: 'T',
      cuts: [
        cut(leaving, leavingRows ?? [heldRow('ra')]),
        cut(arriving, [heldRow('rb')]),
      ],
    );
    return ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          if (olAt == null)
            track
          else
            track.copyWith(transitionLayer: olRow(track, olAt)),
        ],
      ),
    );
  }

  Layer row(ProjectRepository repository, CutId cutId, String id) =>
      requireLayer(
        repository.requireProject(),
        cutId: cutId,
        layerId: LayerId(id),
      );

  /// Where [id]'s picture stops showing — the end of its hold.
  int heldThrough(ProjectRepository repository, CutId cutId, String id) =>
      authoredTimelineExtent(row(repository, cutId, id).timeline);

  test('the leaving cut holds its picture through its のりしろ — to the drawn '
      'end, not the red line', () {
    final repository = repositoryWith(olAt: 18);
    expect(heldThrough(repository, leaving, 'ra'), 30, reason: '24 + 6');
    expect(
      exposedFrameIdAt(row(repository, leaving, 'ra').timeline, 29),
      const FrameId('ra-cel'),
      reason: 'the O.L\'s last frame still has the leaving picture',
    );
    expect(
      heldThrough(repository, arriving, 'rb'),
      30,
      reason: 'the arriving cut draws its のりしろ at its tail too',
    );
  });

  test('CONTROL: with nothing crossing, a hold ends at the red line', () {
    final repository = repositoryWith();
    expect(heldThrough(repository, leaving, 'ra'), 24);
    expect(heldThrough(repository, arriving, 'rb'), 24);
  });

  test('drawing the O.L fills a cut nobody touched; removing it pulls the '
      'hold back to the red line', () {
    final repository = repositoryWith();
    final track = repository.requireProject().tracks.single;
    repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: olRow(track, 18),
    );
    expect(heldThrough(repository, leaving, 'ra'), 30);
    expect(heldThrough(repository, arriving, 'rb'), 30);

    repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: track.transitionLayer,
    );
    expect(heldThrough(repository, leaving, 'ra'), 24);
    expect(heldThrough(repository, arriving, 'rb'), 24);
  });

  test('trimming the leaving cut moves BOTH drawn ends — the arriving cut '
      'untouched', () {
    final repository = repositoryWith(olAt: 18);
    repository.updateCutDuration(cutId: leaving, duration: 20);
    // The O.L still spans 18..29: 10 frames past the leaving cut's new end,
    // and only 2 before the arriving cut's new start.
    expect(heldThrough(repository, leaving, 'ra'), 30, reason: '20 + 10');
    expect(heldThrough(repository, arriving, 'rb'), 26, reason: '24 + 2');
  });

  test('the CONTE row\'s last panel holds through the のりしろ, and lets go '
      'when the O.L does', () {
    // 🗣️「ol시작컷은 콘티레이어의 마지막블록이 여백코마만큼 늘리도록이 맞을듯」.
    final conte = Layer(
      id: const LayerId('conte'),
      name: 'conte',
      kind: LayerKind.storyboard,
      frames: [
        Frame(id: const FrameId('p1'), duration: 1, strokes: const []),
        Frame(id: const FrameId('p2'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('p1'), length: 10),
        10: const TimelineExposure.drawing(FrameId('p2'), length: 14),
      },
    );
    final repository = repositoryWith(olAt: 18, leavingRows: [conte]);
    expect(heldThrough(repository, leaving, 'conte'), 30);
    expect(
      exposedFrameIdAt(row(repository, leaving, 'conte').timeline, 29),
      const FrameId('p2'),
    );
    expect(
      row(repository, leaving, 'conte').timeline[10]!.length,
      14,
      reason: 'the panels still tile the conte 尺 — the strip reads them',
    );

    final track = repository.requireProject().tracks.single;
    repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: track.transitionLayer.copyWith(instructions: const {}),
    );
    expect(heldThrough(repository, leaving, 'conte'), 24);
    expect(
      row(repository, leaving, 'conte').timeline[10]!.endEdge.isNone,
      isTrue,
      reason: 'owing nothing, the conte carries no hold',
    );
  });

  test('an IMAGE row holds its picture through the のりしろ as well', () {
    final repository = repositoryWith(
      olAt: 18,
      leavingRows: [heldRow('bg', kind: LayerKind.image)],
    );
    expect(heldThrough(repository, leaving, 'bg'), 30);
  });

  test('the timeline\'s own edits derive to the drawn end too — a comma '
      'preview holds the row through the のりしろ', () {
    final repository = repositoryWith(olAt: 18);
    final controller = TimelineController(
      repository: repository,
      cutId: leaving,
    );
    final retimed = controller.retimedLayerForBlocks(
      layer: row(repository, leaving, 'ra'),
      newLengthByStart: {0: 2},
    )!;
    expect(authoredTimelineExtent(retimed.timeline), 30);
  });

  test('a write that does not touch the image row keeps its instance — its '
      'hold already reaches the drawn end', () {
    final repository = repositoryWith(
      olAt: 18,
      leavingRows: [heldRow('bg', kind: LayerKind.image), heldRow('ra')],
    );
    final before = row(repository, leaving, 'bg');
    repository.updateLayer(
      layerId: const LayerId('ra'),
      update: (layer) => layer.copyWith(name: 'renamed'),
    );
    expect(identical(row(repository, leaving, 'bg'), before), isTrue);
  });
}
