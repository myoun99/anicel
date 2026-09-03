// WHICH LAYER YOU STAND ON AFTER THE LIST CHANGES UNDER YOU.
//
// Two laws that lived in the session manager until 2026-09-03 and had no
// pins of their own; the layer verbs read them on every delete, so a wrong
// answer lands the user on a row they never chose.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/editing/layer_standing_after_change.dart';

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id.toUpperCase(), frames: const []);

List<Layer> _layers(List<String> ids) => [for (final id in ids) _layer(id)];

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
}
