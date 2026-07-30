import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// R6b — WHAT an adjustment layer filters.
///
/// The scope is the whole feature: everything below the row, leaking OUT
/// through pass-through folders (Photoshop's 통과) and stopping at the
/// first buffering one. These build the stack shapes that distinguish
/// those answers and read the tree back.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Layer drawing(String id, {String? folder}) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
  );

  LayerEffect brightness(double amount) => LayerEffect(
    id: const EffectId('fx'),
    kind: EffectKind.brightnessContrast,
    parameters: {'brightness': EffectParameter(value: amount)},
  );

  Layer adjustment(
    String id, {
    String? folder,
    double amount = 20,
    double opacity = 1,
    bool visible = true,
  }) => createAdjustmentLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
    folderId: folder == null ? null : LayerId(folder),
    effects: amount == 0 ? const [] : [brightness(amount)],
    opacity: opacity,
    isVisible: visible,
  );

  Layer folderRow(
    String id, {
    String? parent,
    LayerBlendMode? blendMode,
    double opacity = 1,
  }) => createFolderLayer(
    id: LayerId(id),
    name: id.toUpperCase(),
    parentId: parent == null ? null : LayerId(parent),
  ).copyWith(blendMode: blendMode, opacity: opacity);

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  List<CutFrameCompositeEntryNode> treeOf(Cut source) =>
      resolveCutFrameCompositeTree(cut: source, frameIndex: 0);

  /// The layer ids under a node, depth-first bottom → top.
  List<String> idsUnder(CutFrameCompositeEntryNode node) {
    switch (node) {
      case CutFrameCompositeEntryLeaf(:final entry):
        return [entry.layer.id.value];
      case CutFrameCompositeEntryGroup(:final children):
      case CutFrameCompositeEntryAdjustment(:final children):
        return [for (final child in children) ...idsUnder(child)];
    }
  }

  group('the predicates', () {
    test('an adjustment composites but paints nothing of its own', () {
      expect(layerKindComposites(LayerKind.adjustment), isTrue);
      expect(layerKindFiltersBelow(LayerKind.adjustment), isTrue);
      expect(layerKindPaintsArtwork(LayerKind.adjustment), isFalse);
      expect(layerKindGroupsLayers(LayerKind.adjustment), isFalse);
      expect(layerKindHoldsDrawings(LayerKind.adjustment), isFalse);
      expect(layerKindAcceptsBrushInput(LayerKind.adjustment), isFalse);
    });

    test('it carries EFFECTS and no transform — the one kind that splits', () {
      expect(layerKindHasLayerEffects(LayerKind.adjustment), isTrue);
      expect(layerKindHasLayerTransform(LayerKind.adjustment), isFalse);
      // …and every other kind still answers both the same way.
      for (final kind in LayerKind.values) {
        if (kind == LayerKind.adjustment) {
          continue;
        }
        expect(
          layerKindHasLayerEffects(kind),
          layerKindHasLayerTransform(kind),
          reason: kind.name,
        );
      }
    });

    test('no cel column, no cel export, and the kind is fixed', () {
      expect(layerKindTakesTimesheetColumn(LayerKind.adjustment), isFalse);
      expect(layerKindExportsCels(LayerKind.adjustment), isFalse);
      expect(layerKindIsFixed(LayerKind.adjustment), isTrue);
      expect(layerKindIsClipboardCopyable(LayerKind.adjustment), isFalse);
    });
  });

  group('the scope', () {
    test('wraps everything BELOW it, and nothing above', () {
      final tree = treeOf(
        cut([drawing('a'), drawing('b'), adjustment('fx'), drawing('c')]),
      );
      expect(tree, hasLength(2));
      final scope = tree.first as CutFrameCompositeEntryAdjustment;
      expect(idsUnder(scope), ['a', 'b']);
      expect(idsUnder(tree.last), ['c']);
    });

    test('an adjustment at the BOTTOM filters nothing and leaves no node', () {
      final tree = treeOf(cut([adjustment('fx'), drawing('a')]));
      expect(tree.single, isA<CutFrameCompositeEntryLeaf>());
    });

    test('two adjustments nest: the upper one includes the lower scope', () {
      final tree = treeOf(
        cut([
          drawing('a'),
          adjustment('fx1'),
          drawing('b'),
          adjustment('fx2', amount: 40),
        ]),
      );
      final outer = tree.single as CutFrameCompositeEntryAdjustment;
      expect(outer.effects.single.parameter('brightness'), 40);
      expect(idsUnder(outer), ['a', 'b']);
      final inner = outer.children.first as CutFrameCompositeEntryAdjustment;
      expect(inner.effects.single.parameter('brightness'), 20);
      expect(idsUnder(inner), ['a']);
    });
  });

  group('folder boundaries (§6-z3)', () {
    test('a PASS-THROUGH folder leaks: the scope reaches below the folder', () {
      // Stack bottom→top: A (top level), M1 (in F), FX (in F), M2 (in F),
      // F's row. F passes through, so FX filters A and M1 both.
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('m1', folder: 'f'),
          adjustment('fx', folder: 'f'),
          drawing('m2', folder: 'f'),
          folderRow('f'),
        ]),
      );
      expect(tree, hasLength(2));
      final scope = tree.first as CutFrameCompositeEntryAdjustment;
      expect(idsUnder(scope), [
        'a',
        'm1',
      ], reason: 'the row OUTSIDE the folder is filtered too — 통과');
      expect(idsUnder(tree.last), ['m2']);
    });

    test('a BUFFERING folder stops the leak at its own edge', () {
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('m1', folder: 'f'),
          adjustment('fx', folder: 'f'),
          drawing('m2', folder: 'f'),
          folderRow('f', blendMode: LayerBlendMode.multiply),
        ]),
      );
      // [A, group(F)] — the adjustment lives INSIDE the group.
      expect(tree, hasLength(2));
      expect(tree.first, isA<CutFrameCompositeEntryLeaf>());
      final group = tree.last as CutFrameCompositeEntryGroup;
      final scope = group.children.first as CutFrameCompositeEntryAdjustment;
      expect(idsUnder(scope), [
        'm1',
      ], reason: 'A is outside the buffer and out of reach');
      expect(idsUnder(group), ['m1', 'm2']);
    });

    test('a translucent folder buffers, so it stops the leak too', () {
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('m1', folder: 'f'),
          adjustment('fx', folder: 'f'),
          folderRow('f', opacity: 0.5),
        ]),
      );
      final group = tree.last as CutFrameCompositeEntryGroup;
      expect(idsUnder(group.children.single), ['m1']);
    });

    test('nested pass-through folders leak all the way out', () {
      // A (top), then F2 { B, F1 { C, FX } } — both folders pass through,
      // so the scope is A + B + C in stack order.
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('b', folder: 'f2'),
          drawing('c', folder: 'f1'),
          adjustment('fx', folder: 'f1'),
          folderRow('f1', parent: 'f2'),
          folderRow('f2'),
        ]),
      );
      final scope = tree.single as CutFrameCompositeEntryAdjustment;
      expect(idsUnder(scope), ['a', 'b', 'c']);
    });

    test('the leak stops at the first BUFFERING ancestor, not the last', () {
      // F2 buffers, F1 passes: the scope covers F1's members and F2's, but
      // not the top-level row below F2.
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('b', folder: 'f2'),
          drawing('c', folder: 'f1'),
          adjustment('fx', folder: 'f1'),
          folderRow('f1', parent: 'f2'),
          folderRow('f2', blendMode: LayerBlendMode.multiply),
        ]),
      );
      expect(tree, hasLength(2));
      expect(idsUnder(tree.first), ['a']);
      final group = tree.last as CutFrameCompositeEntryGroup;
      final scope = group.children.single as CutFrameCompositeEntryAdjustment;
      expect(idsUnder(scope), ['b', 'c']);
    });
  });

  group('the gates', () {
    test('a hidden row filters nothing', () {
      final tree = treeOf(
        cut([drawing('a'), adjustment('fx', visible: false)]),
      );
      expect(tree.single, isA<CutFrameCompositeEntryLeaf>());
    });

    test('an empty or no-op chain leaves no node', () {
      expect(
        treeOf(cut([drawing('a'), adjustment('fx', amount: 0)])).single,
        isA<CutFrameCompositeEntryLeaf>(),
      );
    });

    test('a DISABLED effect bypasses it — the row switch writes that', () {
      // R8: the bypass lives on the effects themselves; the layer-label
      // master flips them, so "bypass this row" and "bypass this one
      // effect" are the same mechanism.
      final off = adjustment('fx');
      final tree = treeOf(
        cut([
          drawing('a'),
          off.copyWith(
            effects: [
              for (final effect in off.effects) effect.copyWith(enabled: false),
            ],
          ),
        ]),
      );
      expect(tree.single, isA<CutFrameCompositeEntryLeaf>());
    });

    test('opacity 0 filters nothing; below 1 it is the MIX', () {
      expect(
        treeOf(cut([drawing('a'), adjustment('fx', opacity: 0)])).single,
        isA<CutFrameCompositeEntryLeaf>(),
      );
      final scope =
          treeOf(cut([drawing('a'), adjustment('fx', opacity: 0.5)])).single
              as CutFrameCompositeEntryAdjustment;
      expect(scope.mix, 0.5);
    });

    test('a hidden ANCESTOR takes the adjustment down with the subtree', () {
      final tree = treeOf(
        cut([
          drawing('a'),
          drawing('m1', folder: 'f'),
          adjustment('fx', folder: 'f'),
          folderRow('f').copyWith(isVisible: false),
        ]),
      );
      expect(
        idsUnder(tree.single),
        ['a'],
        reason: 'the hidden folder hides its rows AND its adjustment',
      );
    });
  });

  group('the playback signature', () {
    CutFrameCompositeSignature signatureOf(Cut source) =>
        computeCutFrameCompositeSignature(
          cut: source,
          frameIndex: 0,
          quality: PlaybackQuality.full,
          revisionOf: (layerId, frameId) => 1,
        );

    test('the scope, the chain and the mix are all part of the identity', () {
      final base = cut([drawing('a'), drawing('b'), adjustment('fx')]);
      expect(signatureOf(base), signatureOf(base));
      // A different chain.
      expect(
        signatureOf(base),
        isNot(
          signatureOf(
            cut([drawing('a'), drawing('b'), adjustment('fx', amount: 40)]),
          ),
        ),
      );
      // A different mix.
      expect(
        signatureOf(base),
        isNot(
          signatureOf(
            cut([drawing('a'), drawing('b'), adjustment('fx', opacity: 0.5)]),
          ),
        ),
      );
      // A different SCOPE: the same chain, moved down one row.
      expect(
        signatureOf(base),
        isNot(signatureOf(cut([drawing('a'), adjustment('fx'), drawing('b')]))),
      );
    });

    test('the layers view still walks through an adjustment scope', () {
      final signature = signatureOf(
        cut([drawing('a'), drawing('b'), adjustment('fx')]),
      );
      expect(
        signature.layers.map((layer) => layer.layerId.value),
        ['a', 'b'],
        reason: 'the readers that ask "which cels" must see through it',
      );
    });
  });
}
