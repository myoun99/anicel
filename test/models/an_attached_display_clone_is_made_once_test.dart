import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🚨A SYNCED ROW'S DISPLAY CLONE IS MADE ONCE PER PAIR OF INSTANCES (F-166,
/// 2026-09-24): the rows are read once per timeline cell during a stroke,
/// and making every clone anew on every read is what starved the pen at
/// the start of a stroke on a heavy cut. The same row and base answer the
/// same clone; a changed row or base — a new instance — answers a new one
/// that mirrors it.
void main() {
  Layer base(Map<int, String> blocks) => Layer(
    id: const LayerId('base'),
    name: 'base',
    kind: LayerKind.animation,
    frames: [
      for (final cel in blocks.values.toSet())
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in blocks.entries)
        entry.key: TimelineExposure.drawing(FrameId(entry.value), length: 1),
    },
  );

  Layer attached(Map<String, String> links) => Layer(
    id: const LayerId('mirror'),
    name: 'mirror',
    kind: LayerKind.animation,
    frames: [
      for (final cel in links.values)
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: const {},
    attachedToLayerId: const LayerId('base'),
    attachedMode: AttachedMode.synced,
    baseFrameLinks: {
      for (final entry in links.entries)
        FrameId(entry.key): FrameId(entry.value),
    },
  );

  List<(int, String)> blocksOf(Layer layer) => [
    for (final entry in layer.timeline.entries)
      (entry.key, entry.value.frameId!.value),
  ];

  test('the same row and base answer the same clone', () {
    final row = attached({'a': 'a1', 'b': 'b1'});
    final b = base({0: 'a', 1: 'b'});
    final first = attachedDisplayLayer(attached: row, base: b);
    expect(blocksOf(first), [(0, 'a1'), (1, 'b1')]);
    expect(
      identical(attachedDisplayLayer(attached: row, base: b), first),
      isTrue,
      reason: 'nothing changed: the clone already made',
    );
  });

  test('a new base instance answers a new clone that mirrors it', () {
    final row = attached({'a': 'a1', 'b': 'b1'});
    final before = attachedDisplayLayer(
      attached: row,
      base: base({0: 'a', 1: 'b'}),
    );
    final after = attachedDisplayLayer(
      attached: row,
      base: base({0: 'b', 3: 'a'}),
    );
    expect(identical(after, before), isFalse);
    expect(blocksOf(after), [(0, 'b1'), (3, 'a1')]);
  });

  test('a new row instance answers a new clone that mirrors it', () {
    final b = base({0: 'a', 1: 'b'});
    final before = attachedDisplayLayer(
      attached: attached({'a': 'a1', 'b': 'b1'}),
      base: b,
    );
    final after = attachedDisplayLayer(
      attached: attached({'a': 'a2'}),
      base: b,
    );
    expect(identical(after, before), isFalse);
    expect(blocksOf(after), [(0, 'a2')]);
  });
}
