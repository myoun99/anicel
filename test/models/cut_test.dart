import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';

void main() {
  group('Cut storyboard layer correction', () {
    test('does not serialize storyboardLayer', () {
      final json = _cut().toJson();

      expect(json.containsKey('storyboardLayer'), isFalse);
    });

    test('old JSON with storyboardLayer is ignored', () {
      final json = _cut().toJson()
        ..['storyboardLayer'] = {
          'panels': [
            {
              'id': {'value': 'panel-1'},
              'actionMemo': 'Old action',
              'dialogueMemo': 'Old dialogue',
              'note': 'Old note',
            },
          ],
        };

      final restoredCut = Cut.fromJson(json);

      // Loading backfills the SE/instruction fixture rows.
      final expected = _cut();
      expect(
        restoredCut,
        expected.copyWith(
          layers: withEnsuredSectionLayers(expected.id, expected.layers),
        ),
      );
      expect(restoredCut.toJson().containsKey('storyboardLayer'), isFalse);
    });

    test(
      'layers can represent storyboard workflow via LayerKind.storyboard',
      () {
        final cut = _cut(
          layers: [
            Layer(
              id: const LayerId('storyboard-layer'),
              name: 'Storyboard',
              frames: const [],
              kind: LayerKind.storyboard,
            ),
          ],
        );

        final restoredCut = Cut.fromJson(cut.toJson());

        expect(restoredCut.layers.first.kind, LayerKind.storyboard);
        expect(
          restoredCut.layers.where(
            (layer) => layer.kind == LayerKind.storyboard,
          ),
          hasLength(1),
        );
      },
    );
  });

  group('CutMetadata scope', () {
    test('CutMetadata remains note-only', () {
      const metadata = CutMetadata(note: 'General note');

      expect(metadata.toJson(), {'note': 'General note'});
      expect(metadata.toString(), contains('note: General note'));
      expect(metadata.toJson().containsKey('actionMemo'), isFalse);
      expect(metadata.toJson().containsKey('dialogueMemo'), isFalse);
    });
  });
}

Cut _cut({List<Layer> layers = const []}) {
  return Cut(
    id: const CutId('cut-1'),
    name: 'Cut 1',
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}
