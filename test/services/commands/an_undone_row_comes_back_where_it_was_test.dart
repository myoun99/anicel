import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/rekey_brush_frames_command.dart';
import 'package:anicel/src/services/commands/track_se_layer_commands.dart';
import 'package:anicel/src/services/project_repository.dart';

/// Two more commands the undo stack carries with nothing naming them.
void main() {
  Layer se(String id, {String name = 'SE'}) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    timeline: const {},
    kind: LayerKind.se,
  );

  Project projectWith(List<Layer> seLayers) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        seLayers: seLayers,
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'c',
            layers: const [],
            duration: 12,
            canvasSize: const CanvasSize(width: 100, height: 100),
          ),
        ],
      ),
    ],
  );

  List<String> rowsOf(ProjectRepository repository) => [
    for (final layer in repository.requireProject().tracks.single.seLayers)
      layer.id.value,
  ];

  group('the track-owned SE row pair', () {
    test('an added row lands at the END when no index is given', () {
      final repository = ProjectRepository(
        initialProject: projectWith([se('a')]),
      );

      AddTrackSeLayerCommand(
        repository: repository,
        trackId: const TrackId('t'),
        layer: se('b'),
      ).execute();

      expect(rowsOf(repository), ['a', 'b']);
    });

    test('an index places it, and undo takes exactly that row back out', () {
      final repository = ProjectRepository(
        initialProject: projectWith([se('a'), se('c')]),
      );
      final command = AddTrackSeLayerCommand(
        repository: repository,
        trackId: const TrackId('t'),
        layer: se('b'),
        insertionIndex: 1,
      );

      command.execute();
      expect(rowsOf(repository), ['a', 'b', 'c']);

      command.undo();
      expect(rowsOf(repository), ['a', 'c']);
    });

    test('the description names the row the user added', () {
      expect(
        AddTrackSeLayerCommand(
          repository: ProjectRepository(initialProject: projectWith(const [])),
          trackId: const TrackId('t'),
          layer: se('b', name: 'Footsteps'),
        ).description,
        contains('Footsteps'),
      );
    });

    test('🚨a removed row comes back WHERE IT WAS, not at the end', () {
      final repository = ProjectRepository(
        initialProject: projectWith([se('a'), se('b'), se('c')]),
      );
      final command = RemoveTrackSeLayerCommand(
        repository: repository,
        trackId: const TrackId('t'),
        layerId: const LayerId('b'),
      );

      command.execute();
      expect(rowsOf(repository), ['a', 'c']);

      command.undo();
      expect(
        rowsOf(repository),
        ['a', 'b', 'c'],
        reason:
            'the row order is the stack the user reads — an undo that '
            'reappends is a different sheet',
      );
    });

    test('removing a row that is NOT there is refused loudly rather than '
        'quietly doing nothing', () {
      expect(
        RemoveTrackSeLayerCommand(
          repository: ProjectRepository(initialProject: projectWith([se('a')])),
          trackId: const TrackId('t'),
          layerId: const LayerId('nope'),
        ).execute,
        throwsStateError,
      );
    });
  });

  group('RekeyBrushFramesCommand', () {
    BrushFrameKey key(String frame) => BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: const CutId('c'),
      layerId: const LayerId('l'),
      frameId: FrameId(frame),
    );

    // A surface with NO tiles is not stored at all (the store treats an
    // empty one as a delete), so the fixture has to hold a pixel.
    BitmapSurface surface() => BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile.blank(
          size: 8,
        ),
      },
    );

    test('the drawings move to their new keys, and undo brings them home', () {
      final store = BrushFrameStore();
      final moved = surface();
      store.storeBakedSurface(key('f1'), moved);
      final command = RekeyBrushFramesCommand(
        store: store,
        pairs: [(key('f1'), key('f2'))],
      );

      command.execute();
      expect(store.bakedSurfaceOrNull(key('f2')), same(moved));
      expect(store.bakedSurfaceOrNull(key('f1')), isNull);

      command.undo();
      expect(store.bakedSurfaceOrNull(key('f1')), same(moved));
      expect(store.bakedSurfaceOrNull(key('f2')), isNull);
    });

    test('several DISJOINT pairs all move, and all come home', () {
      // ⚠️Disjoint is the shape the callers build, by construction: a
      // frameId names one cel, so a cel appears in exactly one pair and
      // no `to` is another pair's `from`. An OVERLAPPING chain would need
      // the replay to reverse the list order as well, and nothing makes
      // one — see the note on the command.
      final store = BrushFrameStore();
      final first = surface();
      final second = surface();
      store.storeBakedSurface(key('f1'), first);
      store.storeBakedSurface(key('f2'), second);
      final command = RekeyBrushFramesCommand(
        store: store,
        pairs: [(key('f1'), key('g1')), (key('f2'), key('g2'))],
      );

      command.execute();
      expect(store.bakedSurfaceOrNull(key('g1')), same(first));
      expect(store.bakedSurfaceOrNull(key('g2')), same(second));

      command.undo();
      expect(store.bakedSurfaceOrNull(key('f1')), same(first));
      expect(store.bakedSurfaceOrNull(key('f2')), same(second));
      expect(store.bakedSurfaceOrNull(key('g1')), isNull);
    });

    test('the description counts what it moved', () {
      expect(
        RekeyBrushFramesCommand(
          store: BrushFrameStore(),
          pairs: [(key('f1'), key('f2'))],
        ).description,
        contains('1'),
      );
    });
  });
}
