import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/frozen_collections.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';

/// 🔬F-620 (2026-11-19, the Surface): a ruler's bar lays the tree of every
/// frame of a cut again after each edit, and laying the rows a chain reads
/// ([withTheRowsTheyRead]) rebuilt every node and copied every list it
/// passed — about a quarter of laying the trees, on a cut no chain of which
/// read a row. A node that reads nothing, all of whose parts come back as
/// they were, comes back itself.
void main() {
  final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [2]);
  ResolvedLayerEffect readingMap(String row) => ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: const [],
    layers: {'blurMapLayer': LayerId(row)},
  );

  /// Every kind of node, none of whose chains names a row — but for the
  /// leaf [reader], when given, whose chain reads row `map`.
  ({List<CompositeNode<String>> nodes, CompositeLeaf<String> beside})
  everyKind({String? reader}) {
    const beside = CompositeLeaf<String>('beside');
    final number = CompositeCelNumber<String>(
      on: const CompositeLeaf<String>('numbered'),
      letters: CelNumberLetters(
        text: '1',
        color: 0xFF000000,
        center: CanvasPoint(x: 0, y: 0),
        scale: CanvasPoint(x: 1, y: 1),
      ),
    );
    final read = CompositeReadsRows<String>(
      node: const CompositeLeaf<String>('read'),
      rows: frozenMap({
        const LayerId('elsewhere'): frozenList([
          const CompositeLeaf<String>('e'),
        ]),
      }),
    );
    final clip = CompositeClip<String>(
      base: const CompositeLeaf<String>('base'),
      scope: frozenList([
        CompositeLeaf<String>(reader ?? 'clipped'),
        const CompositeOpaque<String>(CompositeLeaf<String>('shut')),
      ]),
      opacity: 1,
      blendMode: LayerBlendMode.normal,
    );
    return (
      beside: beside,
      nodes: frozenList([
        CompositeGroup<String>(
          children: frozenList([beside, number, read]),
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: [blur],
        ),
        CompositeBackdropBlend<String>(
          backdrop: frozenList([const CompositeLeaf<String>('under')]),
          source: CompositeAdjustment<String>(
            children: frozenList([clip]),
            effects: [blur],
            mix: 1,
          ),
          blendMode: LayerBlendMode.multiply,
        ),
      ]),
    );
  }

  List<CompositeNode<String>> lay(List<CompositeNode<String>> nodes) =>
      withTheRowsTheyRead(
        nodes,
        effectsOf: (row) => row == 'reader' ? [readingMap('map')] : const [],
        drawnOf: (row, by) => [CompositeLeaf<String>('drawn ${row.value}')],
      );

  test('a tree no chain of which reads a row is the tree it was handed', () {
    final tree = everyKind().nodes;

    expect(lay(tree), same(tree));
  });

  test('a row read deep in the tree lays anew only the nodes above it', () {
    final tree = everyKind(reader: 'reader');
    final laid = lay(tree.nodes);

    final folder = laid[0] as CompositeGroup<String>;
    expect(folder, same(tree.nodes[0]));
    expect(folder.children.first, same(tree.beside));

    final blend = laid[1] as CompositeBackdropBlend<String>;
    final handed = tree.nodes[1] as CompositeBackdropBlend<String>;
    expect(blend, isNot(same(handed)));
    expect(blend.backdrop, same(handed.backdrop));
    final clip =
        (blend.source as CompositeAdjustment<String>).children.single
            as CompositeClip<String>;
    final handedClip =
        (handed.source as CompositeAdjustment<String>).children.single
            as CompositeClip<String>;
    expect(clip.base, same(handedClip.base));
    expect(clip.scope.last, same(handedClip.scope.last));
    expect(
      clip.scope.first,
      isA<CompositeReadsRows<String>>()
          .having((it) => it.node, 'node', same(handedClip.scope.first))
          .having((it) => it.rows.keys, 'rows', [const LayerId('map')]),
    );
  });
}
