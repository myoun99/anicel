// WHICH LAYER YOU STAND ON AFTER THE LIST CHANGES UNDER YOU.
//
// Two laws that lived in the session manager until 2026-09-03 and had no
// pins of their own; the layer verbs read them on every delete, so a wrong
// answer lands the user on a row they never chose. The storyboard's conte
// rows, addressed by their seats, follow by the same law (F-322).
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/layer_standing_after_change.dart';

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id.toUpperCase(), frames: const []);

List<Layer> _layers(List<String> ids) => [for (final id in ids) _layer(id)];

const _track = TrackId('t1');

LayerRowAddress _seat(int seat) =>
    LayerRowAddress(trackConteRowId(_track, seat: seat));

/// Cut [id] holding [rows] in its stack order, bottom first: `conte` its
/// conte, `-name` a row riding it below, `+name` one riding it above.
Cut _cut(String id, List<String> rows) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    for (final row in rows)
      Layer(
        id: LayerId('$id-${row.replaceFirst(RegExp('^[+-]'), '')}'),
        name: row,
        kind: LayerKind.storyboard,
        frames: const [],
        attachedToLayerId: row == 'conte' ? null : LayerId('$id-conte'),
        attachedPlacement: row.startsWith('-')
            ? AttachedPlacement.below
            : AttachedPlacement.above,
      ),
  ],
);

Project _film(List<Cut> cuts) => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [Track(id: _track, name: 'V1', cuts: cuts)],
);

/// Every cut holding the same group: Under (−1), the conte, Over (+1) and
/// High (+2).
Project _full() => _film([
  _cut('a', ['-under', 'conte', '+over', '+high']),
  _cut('b', ['-under', 'conte', '+over', '+high']),
]);

void main() {
  group('stableLayerIdAfterDeleting', () {
    test('the row that takes the deleted index stands next', () {
      expect(
        stableLayerIdAfterDeleting(
          beforeLayers: _layers(['a', 'b', 'c']),
          deletedLayerId: const LayerId('b'),
        ),
        const LayerId('c'),
      );
    });

    test('deleting the last row hands off to the one above it', () {
      expect(
        stableLayerIdAfterDeleting(
          beforeLayers: _layers(['a', 'b', 'c']),
          deletedLayerId: const LayerId('c'),
        ),
        const LayerId('b'),
      );
    });

    test('nothing stands when the list empties or never held the row', () {
      expect(
        stableLayerIdAfterDeleting(
          beforeLayers: _layers(['a']),
          deletedLayerId: const LayerId('a'),
        ),
        isNull,
      );
      expect(
        stableLayerIdAfterDeleting(
          beforeLayers: _layers(['a', 'b']),
          deletedLayerId: const LayerId('zz'),
        ),
        isNull,
      );
    });
  });

  group('preferredLayerAfterLayerListChange', () {
    test('an inserted layer wins', () {
      expect(
        preferredLayerAfterLayerListChange(
          beforeLayers: _layers(['a', 'b']),
          afterLayers: _layers(['a', 'n', 'b']),
          previousActiveLayerId: const LayerId('a'),
        ),
        const LayerId('n'),
      );
    });

    test('a removed active layer hands off by the deletion law', () {
      expect(
        preferredLayerAfterLayerListChange(
          beforeLayers: _layers(['a', 'b', 'c']),
          afterLayers: _layers(['a', 'c']),
          previousActiveLayerId: const LayerId('b'),
        ),
        const LayerId('c'),
      );
    });

    test('otherwise the active layer keeps its place', () {
      expect(
        preferredLayerAfterLayerListChange(
          beforeLayers: _layers(['a', 'b']),
          afterLayers: _layers(['b', 'a']),
          previousActiveLayerId: const LayerId('a'),
        ),
        const LayerId('a'),
      );
      expect(
        preferredLayerAfterLayerListChange(
          beforeLayers: _layers(['a']),
          afterLayers: _layers(['a']),
          previousActiveLayerId: null,
        ),
        isNull,
      );
    });
  });

  group('🗣️F-322 conteRowAfterChange — a conte row goes where its rows went',
      () {
    test('a re-order takes it to its rows\' new seat, a lane of it along', () {
      final swapped = _film([
        _cut('a', ['-under', 'conte', '+high', '+over']),
        _cut('b', ['-under', 'conte', '+high', '+over']),
      ]);
      expect(
        conteRowAfterChange(_seat(2), before: _full(), after: swapped),
        _seat(1),
      );
      expect(
        conteRowAfterChange(
          LaneRowAddress(_seat(2).layerId, 'position'),
          before: _full(),
          after: swapped,
        ),
        LaneRowAddress(_seat(1).layerId, 'position'),
      );
    });

    test('every other row comes back as it is', () {
      final pulled = _film([
        _cut('a', ['-under', 'conte', '+high']),
        _cut('b', ['-under', 'conte', '+high']),
      ]);
      for (final row in <TimelineRowAddress>[
        const LayerRowAddress(LayerId('s1')),
        const TrackRowAddress(_track),
        LayerRowAddress(trackCameraRowId(_track)),
      ]) {
        expect(
          conteRowAfterChange(row, before: _full(), after: pulled),
          row,
        );
      }
    });

    test('a seat no cut held has no rows to follow, so it stays — the '
        'conte\'s own, on a track with no conte yet', () {
      expect(
        conteRowAfterChange(
          _seat(0),
          before: _film([_cut('a', [])]),
          after: _film([
            _cut('a', ['conte']),
          ]),
        ),
        _seat(0),
      );
    });

    test('its rows all gone, it follows none', () {
      expect(
        conteRowAfterChange(
          _seat(2),
          before: _full(),
          after: _film([
            _cut('a', ['-under', 'conte', '+over']),
            _cut('b', ['-under', 'conte', '+over']),
          ]),
        ),
        isNull,
      );
    });

    test('where the cuts\' groups part, the first of its rows in cut order '
        'still standing says where — the row that speaks for it', () {
      expect(
        conteRowAfterChange(
          _seat(2),
          before: _full(),
          after: _film([
            _cut('a', ['-under', 'conte', '+high']),
            _cut('b', ['-under', 'conte', '+over', '+high']),
          ]),
        ),
        _seat(1),
        reason: 'cut a\'s High came down a seat',
      );
      expect(
        conteRowAfterChange(
          _seat(2),
          before: _full(),
          after: _film([
            _cut('a', ['-under', 'conte', '+over']),
            _cut('b', ['-under', 'conte', '+over', '+high']),
          ]),
        ),
        _seat(2),
        reason: 'cut a\'s High is gone; cut b\'s still sits there',
      );
    });
  });

  group('🗣️F-322 conteRowHandedOff — a stand whose rows are gone goes where '
      'the timeline\'s delete hands on, over the group', () {
    test('the outermost gone: to the row under it', () {
      expect(
        conteRowHandedOff(
          _seat(2),
          before: _full(),
          after: _film([
            _cut('a', ['-under', 'conte', '+over']),
            _cut('b', ['-under', 'conte', '+over']),
          ]),
        ),
        _seat(1),
      );
    });

    test('a lane of it: to the row, not to a lane of it', () {
      expect(
        conteRowHandedOff(
          LaneRowAddress(_seat(2).layerId, 'position'),
          before: _full(),
          after: _film([
            _cut('a', ['-under', 'conte', '+over']),
            _cut('b', ['-under', 'conte', '+over']),
          ]),
        ),
        _seat(1),
      );
    });

    test('the group gone whole: to the conte\'s own seat', () {
      expect(
        conteRowHandedOff(
          _seat(2),
          before: _full(),
          after: _film([_cut('a', []), _cut('b', [])]),
        ),
        _seat(0),
      );
    });
  });
}
