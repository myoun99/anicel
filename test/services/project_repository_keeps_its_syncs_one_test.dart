import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_sync.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

/// The repository keeps a 동기컷 one on every write (I-150-Q3) — and the
/// writes of a history step as ONE (`asOneConteWrite`): a step writes a
/// mirrored row cut by cut, the 동기컷's with the lanes it held before.
void main() {
  const x = CutId('x');
  const y = CutId('y');
  const xRow = LayerId('x-a');
  const yRow = LayerId('y-a');
  final cel = Frame(id: const FrameId('f1'), duration: 1, strokes: const []);
  final added = Frame(id: const FrameId('f2'), duration: 1, strokes: const []);
  const drawn = {0: TimelineExposure.drawing(FrameId('f2'), length: 3)};

  Track track(String id, CutId cut, LayerId row) => Track(
    id: TrackId(id),
    name: 'V',
    cuts: [
      Cut(
        id: cut,
        name: cut.value,
        layers: [
          Layer(id: row, name: 'A', frames: [cel]),
        ],
        duration: 10,
        canvasSize: const CanvasSize(width: 32, height: 32),
      ),
    ],
  );

  LayerLinkMember member(String track, CutId cut, LayerId row) =>
      LayerLinkMember(trackId: TrackId(track), cutId: cut, layerId: row);

  /// x in the first timeline, y in the second — the one open.
  ProjectRepository repository() => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'p',
      createdAt: DateTime.utc(2026, 11, 4),
      timelines: [
        ProjectTimeline(
          id: const TimelineId('tl-1'),
          number: 1,
          tracks: [track('t1', x, xRow)],
        ),
        ProjectTimeline(
          id: const TimelineId('tl-2'),
          number: 2,
          tracks: [track('t2', y, yRow)],
        ),
      ],
      currentTimelineId: const TimelineId('tl-2'),
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'link-1',
            members: [member('t1', x, xRow), member('t2', y, yRow)],
          ),
        ],
        syncs: [
          CutSync(id: 'sync-1', cuts: const [x, y]),
        ],
      ),
    ),
  );

  Cut cutOf(ProjectRepository repository, CutId id) => repository
      .requireProject()
      .tracksOfEveryTimeline
      .expand((track) => track.cuts)
      .singleWhere((cut) => cut.id == id);

  Layer rowOf(ProjectRepository repository, CutId id) =>
      cutOf(repository, id).layers.single;

  Layer drawnOn(Layer row) =>
      row.copyWith(frames: [cel, added], timeline: drawn);

  test('a write of one cut of a sync is the other\'s', () {
    final r = repository();

    r.updateLayer(layerId: yRow, update: drawnOn);

    expect(rowOf(r, x).timeline, drawn);
    expect(rowOf(r, x).frames, [cel, added]);
  });

  test('a step\'s writes are made one once: the 동기컷 written last, with '
      'the lanes it held before the step, does not take back the edit', () {
    final r = repository();
    final before = rowOf(r, x);

    r.asOneConteWrite(() {
      r.updateLayer(layerId: yRow, update: drawnOn);
      // The mirror's write: the bank adopted, the lanes the member's own.
      r.replaceLayer(layer: before.copyWith(frames: [cel, added]));
    });

    expect(rowOf(r, y).timeline, drawn);
    expect(rowOf(r, x).timeline, drawn);
  });

  test('a row the table links before the other cut holds it is no row of '
      'that cut yet: a step run outside the history, writing the table '
      'first and the rows of each cut after, makes it once', () {
    final r = repository();
    const xNew = LayerId('x-b');
    const yNew = LayerId('y-b');
    r.updateProject(
      (project) => project.copyWith(
        linkRegistry: project.linkRegistry.copyWith(
          groups: [
            ...project.linkRegistry.groups,
            LayerLinkGroup(
              id: 'link-2',
              members: [member('t1', x, xNew), member('t2', y, yNew)],
            ),
          ],
        ),
      ),
    );

    r.insertLayer(
      cutId: y,
      layer: Layer(id: yNew, name: 'B', frames: [cel]),
    );
    expect(
      [for (final row in cutOf(r, x).layers) row.id],
      [xRow],
      reason: 'x-b is the row the next write puts in x',
    );
    r.insertLayer(
      cutId: x,
      layer: Layer(id: xNew, name: 'B', frames: [cel]),
    );
    expect([for (final row in cutOf(r, x).layers) row.id], [xRow, xNew]);
  });
}
