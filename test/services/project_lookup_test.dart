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
import 'package:anicel/src/services/project_lookup.dart';

// Direct coverage for the shared Project -> Track -> Cut -> Layer lookups.
// Command tests used to each carry a private copy of these walks (the
// `_cutById`/`_layerById` reimplementations); those now call these functions,
// but nothing named them directly, so this pins their found / not-found and
// track-owned-SE behaviour.
Cut _cut(String id, {List<Layer> layers = const []}) => Cut(
  id: CutId(id),
  name: id,
  duration: 1,
  canvasSize: const CanvasSize(width: 8, height: 8),
  layers: layers,
);

Layer _layer(String id) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  kind: LayerKind.animation,
);

Project _project({
  List<Cut> cuts = const [],
  List<Layer> seLayers = const [],
}) => Project(
  id: const ProjectId('p'),
  name: 'p',
  createdAt: DateTime.utc(2026, 6, 11),
  tracks: [
    Track(id: const TrackId('t'), name: 't', cuts: cuts, seLayers: seLayers),
  ],
);

void main() {
  group('project_lookup', () {
    test('requireCut returns the matching cut and throws when absent', () {
      final project = _project(cuts: [_cut('a'), _cut('b')]);

      expect(requireCut(project, const CutId('b')).id, const CutId('b'));
      expect(
        () => requireCut(project, const CutId('missing')),
        throwsStateError,
      );
    });

    test('requireTrackOfCut finds the holding track, else throws', () {
      final project = _project(cuts: [_cut('a')]);

      expect(
        requireTrackOfCut(project, const CutId('a')).id,
        const TrackId('t'),
      );
      expect(
        () => requireTrackOfCut(project, const CutId('missing')),
        throwsStateError,
      );
    });

    test('requireLayer is cut-scoped: found, wrong cut, missing layer', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
          _cut('b', layers: [_layer('lb')]),
        ],
      );

      expect(
        requireLayer(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('la'),
        ).id,
        const LayerId('la'),
      );
      // Layer lb lives in cut b, so it is not found scoped to cut a.
      expect(
        () => requireLayer(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('lb'),
        ),
        throwsStateError,
      );
      expect(
        () => requireLayer(
          project,
          cutId: const CutId('missing'),
          layerId: const LayerId('la'),
        ),
        throwsStateError,
      );
    });

    test('cutIdOfLayer returns the owning cut, or null for track SE rows', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
        ],
        seLayers: [_layer('se')],
      );

      expect(cutIdOfLayer(project, const LayerId('la')), const CutId('a'));
      // Track-owned SE rows have no owning cut.
      expect(cutIdOfLayer(project, const LayerId('se')), isNull);
      expect(cutIdOfLayer(project, const LayerId('missing')), isNull);
    });

    test('requireLayerAnywhere reaches cut layers AND track-owned SE rows', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
        ],
        seLayers: [_layer('se')],
      );

      expect(
        requireLayerAnywhere(project, const LayerId('la')).id,
        const LayerId('la'),
      );
      expect(
        requireLayerAnywhere(project, const LayerId('se')).id,
        const LayerId('se'),
      );
      expect(
        () => requireLayerAnywhere(project, const LayerId('missing')),
        throwsStateError,
      );
    });
  });
}
