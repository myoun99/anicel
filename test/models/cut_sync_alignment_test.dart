import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_sync.dart';
import 'package:anicel/src/models/cut_sync_alignment.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

/// THE ONE LAW of what a 동기컷 shares (I-150-Q3) — `syncedCopy` — and the
/// write that keeps the cuts of a sync one (`projectWithItsSyncsAligned`).
void main() {
  const x = CutId('x');
  const y = CutId('y');

  const drawn = {0: TimelineExposure.drawing(FrameId('f1'), length: 3)};

  Layer cel(String id, {Map<int, TimelineExposure> timeline = const {}}) =>
      Layer(
        id: LayerId(id),
        name: 'A',
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        ],
        timeline: timeline,
      );

  Layer direction(String id, String name) => Layer(
    id: LayerId(id),
    name: name,
    kind: LayerKind.instruction,
    frames: const [],
  );

  Cut cut(
    CutId id, {
    required String name,
    required List<Layer> layers,
    int duration = 10,
    int gap = 0,
  }) => Cut(
    id: id,
    name: name,
    layers: layers,
    duration: duration,
    canvasSize: const CanvasSize(width: 32, height: 32),
    leadingGapFrames: gap,
  );

  LayerLinkRegistry linked(List<(String, String)> rows) => LayerLinkRegistry(
    groups: [
      for (final (index, (from, to)) in rows.indexed)
        LayerLinkGroup(
          id: 'link-$index',
          members: [
            LayerLinkMember(
              trackId: const TrackId('t1'),
              cutId: x,
              layerId: LayerId(from),
            ),
            LayerLinkMember(
              trackId: const TrackId('t2'),
              cutId: y,
              layerId: LayerId(to),
            ),
          ],
        ),
    ],
    syncs: [
      CutSync(id: 'sync-1', cuts: [x, y]),
    ],
  );

  group('syncedCopy', () {
    test('the source\'s content under the other cut\'s rows: its length, '
        'its timing, its direction rows — the name and the gap stay', () {
      final source = cut(
        x,
        name: '12',
        duration: 30,
        layers: [cel('x-a', timeline: drawn), direction('x-d', 'Direction 1')],
      );
      final onto = cut(
        y,
        name: '7',
        gap: 5,
        layers: [
          cel('y-a'),
          direction('y-d', 'Old'),
          direction('y-d2', 'Gone'),
        ],
      );
      final registry = linked([('x-a', 'y-a')]);

      final copy = syncedCopy(
        source,
        onto: onto,
        rowOf: syncedRowsOf(source, onto: onto, registry: registry),
      );

      expect(copy.id, y);
      expect(copy.name, '7');
      expect(copy.leadingGapFrames, 5);
      expect(copy.duration, 30);
      expect([for (final row in copy.layers) row.id.value], ['y-a', 'y-d']);
      expect(copy.layers.first.timeline, source.layers.first.timeline);
      expect(copy.layers.last.name, 'Direction 1');
    });

    test('a row of its own that links and that no row comes across as — '
        'what its own track\'s conte gave it — stays where it stands', () {
      final source = cut(x, name: '12', layers: [cel('x-a'), cel('x-b')]);
      final fill = Layer(
        id: const LayerId('y-fill'),
        name: 'Fill',
        kind: LayerKind.storyboard,
        frames: const [],
      );
      final onto = cut(y, name: '7', layers: [cel('y-a'), fill, cel('y-b')]);

      final copy = syncedCopy(
        source,
        onto: onto,
        rowOf: syncedRowsOf(
          source,
          onto: onto,
          registry: linked([('x-a', 'y-a'), ('x-b', 'y-b')]),
        ),
      );

      expect(
        [for (final row in copy.layers) row.id.value],
        ['y-a', 'y-fill', 'y-b'],
      );
    });

    test('what a row points at is pointed at the row it came across as — '
        'or at none — and a row it held keeps its own conte key', () {
      final folder = Layer(
        id: const LayerId('x-f'),
        name: 'F',
        kind: LayerKind.folder,
        frames: const [],
      );
      final source = cut(
        x,
        name: '12',
        layers: [
          folder,
          cel('x-a').copyWith(
            folderId: const LayerId('x-f'),
            conteKey: const ConteKey('k-1'),
          ),
          cel('x-b').copyWith(folderId: const LayerId('x-gone')),
        ],
      );
      final onto = cut(
        y,
        name: '7',
        layers: [
          folder.copyWith(id: const LayerId('y-f')),
          cel('y-a').copyWith(conteKey: const ConteKey('k-2')),
          cel('y-b'),
        ],
      );

      final copy = syncedCopy(
        source,
        onto: onto,
        rowOf: syncedRowsOf(
          source,
          onto: onto,
          registry: linked([('x-f', 'y-f'), ('x-a', 'y-a'), ('x-b', 'y-b')]),
        ),
      );

      expect(copy.layers[1].folderId, const LayerId('y-f'));
      expect(copy.layers[1].conteKey, const ConteKey('k-2'));
      expect(copy.layers[2].folderId, isNull);
    });

    test('a direction row the other cut lacks is made there, under the id '
        'a redo makes again', () {
      final source = cut(
        x,
        name: '12',
        layers: [direction('x-d', 'D1'), direction('x-d2', 'D2')],
      );
      final onto = cut(y, name: '7', layers: [direction('y-d', 'D1')]);

      final rows = syncedRowsOf(
        source,
        onto: onto,
        registry: LayerLinkRegistry.empty,
      );

      expect(rows, {
        const LayerId('x-d'): const LayerId('y-d'),
        const LayerId('x-d2'): syncedRowId(source.layers.last, y),
      });
    });
  });

  group('projectWithItsSyncsAligned', () {
    Project twoTimelines(Cut first, Cut second, {required bool secondOpen}) =>
        Project(
          id: const ProjectId('p'),
          name: 'p',
          createdAt: DateTime.utc(2026, 11, 4),
          timelines: [
            ProjectTimeline(
              id: const TimelineId('tl-1'),
              number: 1,
              tracks: [
                Track(id: const TrackId('t1'), name: 'V', cuts: [first]),
              ],
            ),
            ProjectTimeline(
              id: const TimelineId('tl-2'),
              number: 2,
              tracks: [
                Track(id: const TrackId('t2'), name: 'V', cuts: [second]),
              ],
            ),
          ],
          currentTimelineId: TimelineId(secondOpen ? 'tl-2' : 'tl-1'),
          linkRegistry: linked([('x-a', 'y-a')]),
        );

    Project withCut(Project project, Cut cut) =>
        project.withTracksOfEveryTimeline(
          (tracks) => [
            for (final track in tracks)
              track.copyWith(
                cuts: [
                  for (final one in track.cuts)
                    if (one.id == cut.id) cut else one,
                ],
              ),
          ],
        );

    Cut cutOf(Project project, CutId id) => project.tracksOfEveryTimeline
        .expand((track) => track.cuts)
        .singleWhere((cut) => cut.id == id);

    final xCut = cut(x, name: '12', layers: [cel('x-a')]);
    final yCut = cut(y, name: '7', gap: 2, layers: [cel('y-a')]);

    test('a write that changed no cut of a sync is handed back as it is', () {
      final before = twoTimelines(xCut, yCut, secondOpen: true);
      final after = before.copyWith(name: 'renamed');

      expect(projectWithItsSyncsAligned(before, after), same(after));
    });

    test('the cut the write changed gives — in the timeline NOT open too, '
        'when the open one was only rebuilt equal', () {
      final before = twoTimelines(xCut, yCut, secondOpen: true);
      final after = withCut(
        withCut(before, xCut.copyWith(duration: 20)),
        yCut.copyWith(layers: [...yCut.layers]),
      );

      final aligned = projectWithItsSyncsAligned(before, after);

      expect(cutOf(aligned, y).duration, 20);
      expect(cutOf(aligned, y).leadingGapFrames, 2);
    });

    test('of two the write changed, the open timeline\'s gives', () {
      final before = twoTimelines(xCut, yCut, secondOpen: true);
      final after = withCut(
        withCut(before, xCut.copyWith(duration: 20)),
        yCut.copyWith(duration: 15),
      );

      final aligned = projectWithItsSyncsAligned(before, after);

      expect(cutOf(aligned, x).duration, 15);
      expect(cutOf(aligned, y).duration, 15);
    });

    test('a cut that just arrived adopts the cut already there — it never '
        'gives', () {
      final before = twoTimelines(xCut, yCut, secondOpen: true)
          .withTracksOfEveryTimeline(
            (tracks) => [
              for (final track in tracks)
                track.copyWith(
                  cuts: [
                    for (final one in track.cuts)
                      if (one.id != y) one,
                  ],
                ),
            ],
          );
      final after = twoTimelines(
        xCut,
        yCut.copyWith(duration: 3),
        secondOpen: true,
      );

      final aligned = projectWithItsSyncsAligned(before, after);

      expect(cutOf(aligned, x).duration, 10);
      expect(cutOf(aligned, y).duration, 10);
    });
  });
}
