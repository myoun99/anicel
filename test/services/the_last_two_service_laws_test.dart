import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/project_with_cut_layers.dart';
import 'package:anicel/src/services/persistence/zstd_payload.dart';

/// The last two shared laws in `services` with nothing naming them.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
  );

  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Project projectWith(List<Track> tracks) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    tracks: tracks,
  );

  List<String> layersOf(Project project, String cutId) => [
    for (final track in project.tracks)
      for (final c in track.cuts)
        if (c.id == CutId(cutId))
          for (final l in c.layers) l.id.value,
  ];

  group('projectWithCutLayers', () {
    Project twoTracks() => projectWith([
      Track(
        id: const TrackId('t1'),
        name: 'A',
        cuts: [
          cut('c1', [layer('a')]),
        ],
      ),
      Track(
        id: const TrackId('t2'),
        name: 'B',
        cuts: [
          cut('c2', [layer('b')]),
        ],
      ),
    ]);

    test('the cut named gets the layers, whichever track holds it', () {
      final next = projectWithCutLayers(twoTracks(), const CutId('c2'), [
        layer('x'),
        layer('y'),
      ]);

      expect(layersOf(next, 'c2'), ['x', 'y']);
      expect(layersOf(next, 'c1'), ['a'], reason: 'the other cut is untouched');
    });

    test('🚨THE WALK IS THE WHOLE PROJECT — a cut in the SECOND track is '
        'found without the caller knowing which track it is in', () {
      final next = projectWithCutLayers(twoTracks(), const CutId('c2'), [
        layer('x'),
      ]);

      expect(next.tracks.last.cuts.single.layers.single.id, const LayerId('x'));
      expect(
        [for (final track in next.tracks) track.id.value],
        ['t1', 't2'],
        reason:
            'every track is rebuilt, so each has to come back as '
            'ITSELF — the rebuild must not hand one track another\'s name',
      );
    });

    test('a cut id that is nowhere leaves the project alone', () {
      final before = twoTracks();
      final next = projectWithCutLayers(before, const CutId('nope'), const []);

      expect(layersOf(next, 'c1'), ['a']);
      expect(layersOf(next, 'c2'), ['b']);
    });

    test('an EMPTY layer list is a real answer — a cut can hold nothing', () {
      final next = projectWithCutLayers(
        twoTracks(),
        const CutId('c1'),
        const [],
      );

      expect(layersOf(next, 'c1'), isEmpty);
    });
  });

  group('decompressZstdPayload', () {
    test('🚨with no engine it is a FormatException NAMING what could not be '
        'read — "no engine" is something the user can act on, and it must '
        'not reach the screen as "corrupt"', () {
      // The engine is optional at runtime, and this test bench has none.
      expect(
        () => decompressZstdPayload(Uint8List.fromList([1, 2, 3]), 'drawing'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('drawing'), contains('zstd')),
          ),
        ),
      );
    });

    test('the name travels — a caller says what it was reading', () {
      expect(
        () => decompressZstdPayload(Uint8List(0), 'sound'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sound'),
          ),
        ),
      );
    });
  });
}
