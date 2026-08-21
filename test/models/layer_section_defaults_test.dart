import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/track_id.dart';

const _cutId = CutId('cut-a');
const _trackId = TrackId('track-a');

Layer _layer(String id, LayerKind kind, {String? name}) {
  return Layer(
    id: LayerId(id),
    name: name ?? id,
    frames: const [],
    timeline: const {},
    kind: kind,
  );
}

Cut _cut(List<Layer> layers) {
  return Cut(
    id: _cutId,
    name: 'Cut A',
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );
}

void main() {
  group('withEnsuredSectionLayers (instruction fixture; SE moved to the '
      'track)', () {
    test('backfills Direction 1 before the camera layer', () {
      final layers = [
        _layer('cel', LayerKind.animation),
        _layer('cam', LayerKind.camera),
      ];

      final ensured = withEnsuredSectionLayers(_cutId, layers);

      expect(ensured.map((layer) => layer.kind), [
        LayerKind.animation,
        LayerKind.instruction,
        LayerKind.camera,
      ]);
      expect(ensured.map((layer) => layer.name), ['cel', 'Direction 1', 'cam']);
      expect(ensured[1].id, instructionLayerIdForCut(_cutId));
    });

    test('returns the same list when the floor is already met', () {
      final layers = [
        _layer('cel', LayerKind.animation),
        _layer('inst', LayerKind.instruction),
        _layer('cam', LayerKind.camera),
      ];

      expect(identical(withEnsuredSectionLayers(_cutId, layers), layers), true);
    });

    test('never adds SE rows (they are track fixtures now)', () {
      final ensured = withEnsuredSectionLayers(_cutId, [
        _layer('cel', LayerKind.animation),
      ]);

      expect(ensured.where((layer) => layer.kind == LayerKind.se), isEmpty);
      expect(
        ensured.where((layer) => layer.kind == LayerKind.instruction),
        hasLength(1),
      );
    });
  });

  group('withEnsuredTrackSeLayers', () {
    test('backfills the S1/S2 floor on an empty track', () {
      final ensured = withEnsuredTrackSeLayers(_trackId, const []);

      expect(ensured.map((layer) => layer.name), ['S1', 'S2']);
      expect(ensured[0].id, seLayerIdForTrack(_trackId, 1));
      expect(ensured[1].id, seLayerIdForTrack(_trackId, 2));
      expect(ensured.every((layer) => layer.kind == LayerKind.se), isTrue);
    });

    test('tops up a single row and skips names in use', () {
      final ensured = withEnsuredTrackSeLayers(_trackId, [
        _layer('voice', LayerKind.se, name: 'S1'),
      ]);

      expect(ensured, hasLength(2));
      expect(ensured[0].id, const LayerId('voice'));
      expect(ensured[1].name, 'S2');
    });

    test('returns the same list when the floor is met', () {
      final seLayers = [
        _layer('s1', LayerKind.se, name: 'S1'),
        _layer('s2', LayerKind.se, name: 'S2'),
      ];

      expect(
        identical(withEnsuredTrackSeLayers(_trackId, seLayers), seLayers),
        true,
      );
    });
  });

  group('Cut.fromJson section fixtures', () {
    test('backfills the missing instruction row on load (SE stays off the '
        'cut)', () {
      final legacy = _cut([
        _layer('cel', LayerKind.animation),
        _layer('cam', LayerKind.camera),
      ]);
      final json = legacy.toJson();

      final loaded = Cut.fromJson(json);

      expect(loaded.layers.map((layer) => layer.kind), [
        LayerKind.animation,
        LayerKind.instruction,
        LayerKind.camera,
      ]);
    });

    test('round-trips unchanged once the fixture exists', () {
      final loaded = Cut.fromJson(
        _cut([
          _layer('cel', LayerKind.animation),
          _layer('cam', LayerKind.camera),
        ]).toJson(),
      );

      final reloaded = Cut.fromJson(loaded.toJson());

      expect(reloaded, loaded);
    });
  });

  group('nextInstructionLayerName', () {
    test('skips names the cut already uses', () {
      expect(nextInstructionLayerName([]), 'Direction 1');
      expect(
        nextInstructionLayerName([
          _layer('a', LayerKind.instruction, name: 'Direction 1'),
          _layer('b', LayerKind.instruction, name: 'Direction 2'),
        ]),
        'Direction 3',
      );
    });

    test('saved CAM names from old files are ordinary names — a new row '
        'starts the Direction scheme beside them, no migration', () {
      expect(
        nextInstructionLayerName([
          _layer('a', LayerKind.instruction, name: 'CAM 1'),
        ]),
        'Direction 1',
      );
    });
  });
}
