import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_composite_structure.dart';

/// 🔬Card an-eye-toggle-holds-the-ui-thread (11-18, S5_BA cut 352 · 68
/// rows): after every edit a ruler's bar laid each frame's tree twice —
/// where the cut's spans are found, and where a span's picture is keyed.
/// The film's tree of a frame is laid once for the cut it is of, and an
/// edit — a new cut — is laid anew.
void main() {
  Layer drawing(String id, {required int from}) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {
      from: TimelineExposure.drawing(FrameId('frame-$id'), length: 4),
    },
  );

  Cut cut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [drawing('a', from: 0), drawing('b', from: 4)],
    duration: 8,
    canvasSize: const CanvasSize(width: 4, height: 4),
  );

  Set<LayerId> rowsOf(List<CompositeNode<CutFrameCompositeRow>> tree) => {
    for (final node in preorderNodes(tree))
      if (node
          case CompositeLeaf(payload: CutFrameCompositeEntry(:final layer)))
        layer.id,
  };

  test('a frame whose spans were found is read from the same laying', () {
    final held = cut();
    final spans = compositeStructureSpansIn(held, start: 0, end: 8);
    expect(spans, hasLength(2), reason: '⛔CONTROL: a span for each row');
    final before = debugCompositeTreesLaid;

    final trees = [for (final span in spans) filmTreeOf(held, span.start)];

    expect(debugCompositeTreesLaid - before, 0);
    expect(trees.map(rowsOf), [
      {const LayerId('a')},
      {const LayerId('b')},
    ]);
  });

  test('an edited cut — a new cut — is laid anew, as it is now', () {
    final held = cut();
    expect(rowsOf(filmTreeOf(held, 0)), {const LayerId('a')});
    final before = debugCompositeTreesLaid;
    final edited = held.copyWith(
      layers: [
        for (final layer in held.layers)
          if (layer.id == const LayerId('a'))
            layer.copyWith(isVisible: false)
          else
            layer,
      ],
    );

    expect(rowsOf(filmTreeOf(edited, 0)), isEmpty);
    expect(debugCompositeTreesLaid - before, 1);
  });

  test('a cut asked again after another is the one asked, as it is', () {
    final first = cut();
    final second = cut().copyWith(layers: [drawing('c', from: 0)]);

    filmTreeOf(first, 0);
    expect(rowsOf(filmTreeOf(second, 0)), {const LayerId('c')});
    expect(rowsOf(filmTreeOf(first, 0)), {const LayerId('a')});
  });
}
