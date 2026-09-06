import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_stack_order.dart';

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id, frames: const [], timeline: const {});

/// The one stack-order measurement under the attach placement, the
/// display-row hop and the lattice hop: "how far is `to` from `from`, and
/// null when either is not in this stack". Three hand loops spelled it
/// (round 8).
void main() {
  final layers = [_layer('a'), _layer('b'), _layer('c')];

  test('a later row answers a positive delta, an earlier one negative', () {
    expect(layerIndexDelta(layers, const LayerId('a'), const LayerId('c')), 2);
    expect(layerIndexDelta(layers, const LayerId('c'), const LayerId('a')), -2);
  });

  test('the same row answers zero — not null', () {
    expect(layerIndexDelta(layers, const LayerId('b'), const LayerId('b')), 0);
  });

  test('a row missing from the stack answers null, on EITHER side — the '
      'dangling anchor must never read as a direction or a hop', () {
    expect(
      layerIndexDelta(layers, const LayerId('gone'), const LayerId('a')),
      isNull,
    );
    expect(
      layerIndexDelta(layers, const LayerId('a'), const LayerId('gone')),
      isNull,
    );
    expect(
      layerIndexDelta(const [], const LayerId('a'), const LayerId('a')),
      isNull,
    );
  });
}
