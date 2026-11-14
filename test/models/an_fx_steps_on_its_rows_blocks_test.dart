import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show resolveLayerPoseAt;
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';

/// 🗣️AN FX READS ITS KEYS BY THE FRAME, OR BY THE BLOCK (backlog-21-Q4 ·
/// I-120-Q10): on 「블록」 a bundle's keys are read at the head of the block
/// a frame shows, so a move keyed across `1--2--3--` steps on the drawings
/// instead of swimming through the holds. A row with no blocks of its own
/// reads every frame whatever it says (I-120-Q9).
void main() {
  // A 0..3 · B 4..7 · an empty cell at 8 · C 9..12.
  final blocks = SplayTreeMap<int, TimelineExposure>.of({
    0: const TimelineExposure.drawing(FrameId('a'), length: 4),
    4: const TimelineExposure.drawing(FrameId('b'), length: 4),
    9: const TimelineExposure.drawing(FrameId('c'), length: 4),
  });

  LayerEffect rampedBlur({FxBasis basis = FxBasis.frame}) => LayerEffect(
    id: const EffectId('e-blur'),
    kind: EffectKind.blur,
    basis: basis,
    parameters: {
      'blurriness': EffectParameter(
        track: PropertyTrack<double>(
          keys: {
            0: const PropertyKey<double>(0),
            12: const PropertyKey<double>(12),
          },
        ),
      ),
    },
  );

  double? blurAt(LayerEffect effect, int frame, {bool hasBlocks = true}) =>
      resolveLayerEffectsAt(
        effects: [effect],
        frameIndex: frame,
        blocks: hasBlocks ? blocks : null,
        worn: null,
      ).firstOrNull?.parameter('blurriness');

  group('where a bundle reads its keys', () {
    test('by the frame, every frame is its own', () {
      for (final frame in [0, 3, 5, 8, 11]) {
        expect(fxReadFrame(FxBasis.frame, blocks, frame), frame);
      }
    });

    test('by the block, at the head of the block the frame shows — an '
        'empty cell being a block of its own', () {
      expect(fxReadFrame(FxBasis.block, blocks, 3), 0);
      expect(fxReadFrame(FxBasis.block, blocks, 4), 4);
      expect(fxReadFrame(FxBasis.block, blocks, 7), 4);
      expect(fxReadFrame(FxBasis.block, blocks, 8), 8);
      expect(fxReadFrame(FxBasis.block, blocks, 12), 9);
      expect(
        fxReadFrame(FxBasis.block, blocks, 20),
        20,
        reason: 'past the last drawing every cell is empty, each its own',
      );
    });

    test('a row with no blocks to step on reads every frame', () {
      expect(fxReadFrame(FxBasis.block, null, 7), 7);
    });
  });

  group('an effect', () {
    test('on the frame swims through a hold', () {
      expect(blurAt(rampedBlur(), 5), _near(5));
      expect(blurAt(rampedBlur(), 7), _near(7));
    });

    test('on the block holds its head\'s value through it', () {
      final stepped = rampedBlur(basis: FxBasis.block);
      expect(blurAt(stepped, 5), _near(4));
      expect(blurAt(stepped, 7), _near(4));
      expect(blurAt(stepped, 8), _near(8), reason: 'an empty cell: its own');
      expect(blurAt(stepped, 11), _near(9));
      expect(
        blurAt(stepped, 2),
        isNull,
        reason: 'block A reads frame 0, where the blur is at its default',
      );
    });

    test('on the block, on a row with none, reads every frame', () {
      final stepped = rampedBlur(basis: FxBasis.block);
      expect(blurAt(stepped, 7, hasBlocks: false), _near(7));
    });
  });

  group('a transform', () {
    Layer row({
      LayerKind kind = LayerKind.animation,
      FxBasis basis = FxBasis.frame,
    }) => Layer(
      id: const LayerId('row'),
      name: 'row',
      kind: kind,
      frames: const [],
      timeline: blocks,
      transformBasis: basis,
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>(
          keys: {
            0: PropertyKey<CanvasPoint>(CanvasPoint(x: 0, y: 0)),
            12: PropertyKey<CanvasPoint>(CanvasPoint(x: 120, y: 0)),
          },
        ),
      ),
    );

    double xAt(Layer layer, int frame) => resolveLayerPoseAt(
      layer: layer,
      canvasSize: const CanvasSize(width: 200, height: 100),
      frameIndex: frame,
    )!.center.x;

    test('on the frame moves through a hold; on the block steps on the '
        'drawings', () {
      expect(xAt(row(), 6), _near(60));
      final stepped = row(basis: FxBasis.block);
      expect(xAt(stepped, 6), _near(40));
      expect(xAt(stepped, 8), _near(80), reason: 'an empty cell: its own');
    });

    test('a folder has no blocks of its own: it reads every frame', () {
      final folder = row(kind: LayerKind.folder, basis: FxBasis.block);
      expect(folder.fxBlocks, isNull);
      expect(folder.transformReadFrame(6), 6);
    });
  });

  group('JSON', () {
    test('an effect on the block round-trips; on the frame it writes '
        'nothing, so an old file reads back equal', () {
      final stepped = rampedBlur(basis: FxBasis.block);
      expect(LayerEffect.fromJson(stepped.toJson()), stepped);
      expect(rampedBlur().toJson().containsKey('basis'), isFalse);
      expect(LayerEffect.fromJson(rampedBlur().toJson()).basis, FxBasis.frame);
    });

    test('a transform on the block round-trips; on the frame it writes '
        'nothing', () {
      final stepped = Layer(
        id: const LayerId('row'),
        name: 'row',
        frames: const [],
        transformBasis: FxBasis.block,
      );
      expect(Layer.fromJson(stepped.toJson()).transformBasis, FxBasis.block);
      final plain = Layer(id: const LayerId('p'), name: 'p', frames: const []);
      expect(plain.toJson().containsKey('transformBasis'), isFalse);
    });
  });

  group('the basis is the chain\'s SHAPE, as its switch is', () {
    test('a link\'s chain takes it, and keeps its own numbers', () {
      final here = rampedBlur();
      final shared = effectChainWithSharedShape(
        [rampedBlur(basis: FxBasis.block)],
        onto: [here],
      ).single;
      expect(shared.basis, FxBasis.block);
      expect(shared.parameters, here.parameters);
    });

    test('two chains that differ only by it are not one shape', () {
      expect(
        sameEffectChainShape(
          [rampedBlur()],
          [rampedBlur(basis: FxBasis.block)],
        ),
        isFalse,
      );
    });
  });

  test('🚨a copied row keeps its transform\'s switch and basis — the copy '
      'helper lists its fields by hand, and had left the switch out', () {
    final source = Layer(
      id: const LayerId('row'),
      name: 'row',
      frames: const [],
      transformEnabled: false,
      transformBasis: FxBasis.block,
    );
    final copy = duplicateLayerAsIndependentCopy(
      source: source,
      newLayerId: const LayerId('row·2'),
      newName: 'row',
      frameIdMap: const {},
    );
    expect(copy.transformEnabled, isFalse);
    expect(copy.transformBasis, FxBasis.block);
  });
}

Matcher _near(num value) => closeTo(value, 1e-9);
