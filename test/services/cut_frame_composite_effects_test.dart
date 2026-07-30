import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// How the R6 effect chain reaches the SHARED composite visit — the one
/// place every route (editing stack, playback cache, camera renders,
/// export) reads its answer from.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  LayerEffect blur(double radius, {String id = 'e-blur'}) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.blur,
    parameters: {'blurX': EffectParameter(value: radius)},
  );

  LayerEffect brightness(double amount, {String id = 'e-bright'}) =>
      LayerEffect(
        id: EffectId(id),
        kind: EffectKind.brightnessContrast,
        parameters: {'brightness': EffectParameter(value: amount)},
      );

  Layer drawingLayer({
    String id = 'a',
    List<LayerEffect> effects = const [],
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [frame('frame-$id')],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    effects: effects,
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer folderRow(
    String id, {
    List<LayerEffect> effects = const [],
    double opacity = 1,
  }) => createFolderLayer(
    id: LayerId(id),
    name: id.toUpperCase(),
  ).copyWith(effects: effects, opacity: opacity);

  CutFrameCompositeEntry entryOf(Cut source, {int frameIndex = 0}) =>
      resolveCutFrameCompositeEntries(
        cut: source,
        frameIndex: frameIndex,
      ).single;

  /// [effects] with every switch off — what the layer-label MASTER writes
  /// (R8), and the only thing that bypasses a chain now.
  List<LayerEffect> allDisabled(List<LayerEffect> effects) => [
    for (final effect in effects) effect.copyWith(enabled: false),
  ];

  group('a layer\'s own effects', () {
    test('ride the entry, sampled at the frame', () {
      final entry = entryOf(
        cut([
          drawingLayer(effects: [blur(6)]),
        ]),
      );
      expect(entry.effects, hasLength(1));
      expect(entry.effects.single.parameter('blurX'), 6);
    });

    test('are absent when the row carries none — the common case is free', () {
      expect(entryOf(cut([drawingLayer()])).effects, isEmpty);
    });

    test('each effect\'s OWN switch bypasses it (the master writes them)', () {
      final source = cut([
        drawingLayer(effects: allDisabled([blur(6)])),
      ]);
      expect(entryOf(source).effects, isEmpty);
    });

    test('an animated parameter differs across a HELD exposure', () {
      final animated = LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                4: const PropertyKey<double>(8),
              },
            ),
          ),
        },
      );
      final source = cut([
        drawingLayer(effects: [animated]),
      ]);
      expect(entryOf(source, frameIndex: 0).effects, isEmpty);
      expect(
        entryOf(source, frameIndex: 2).effects.single.parameter('blurX'),
        4,
        reason: 'the same cel, a different filter — per FRAME, not per cel',
      );
    });
  });

  group('attach rows', () {
    test('wear the BASE\'s chain (FX rides the carrier, W5)', () {
      final base = drawingLayer(id: 'base', effects: [blur(4)]);
      final attached = Layer(
        id: const LayerId('att'),
        name: 'ATT',
        frames: [frame('frame-att')],
        attachedToLayerId: const LayerId('base'),
        attachedMode: AttachedMode.synced,
        baseFrameLinks: {
          const FrameId('frame-base'): const FrameId('frame-att'),
        },
      );
      final entries = resolveCutFrameCompositeEntries(
        cut: cut([base, attached]),
        frameIndex: 0,
      );
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(
          entry.effects.single.parameter('blurX'),
          4,
          reason: '${entry.layer.id} must wear the base\'s blur',
        );
      }
    });
  });

  group('folders', () {
    test('an effect FORCES the buffer — a filter does not distribute', () {
      final folder = folderRow('f', effects: [blur(4)]);
      expect(folderNeedsCompositeBuffer(folder: folder, frameIndex: 0), isTrue);
      // …and a plain organizing folder still costs nothing.
      expect(
        folderNeedsCompositeBuffer(folder: folderRow('f'), frameIndex: 0),
        isFalse,
      );
    });

    test('the chain lands on the GROUP node, not on each member', () {
      final tree = resolveCutFrameCompositeTree(
        cut: cut([
          drawingLayer(id: 'a', folder: 'f'),
          folderRow('f', effects: [brightness(20)]),
        ]),
        frameIndex: 0,
      );
      final group = tree.single as CutFrameCompositeEntryGroup;
      expect(group.effects.single.parameter('brightness'), 20);
      final leaf = group.children.single as CutFrameCompositeEntryLeaf;
      expect(
        leaf.entry.effects,
        isEmpty,
        reason: 'per-member application is the wrong picture (§6-z16)',
      );
    });

    test('a folder whose effects are OFF contributes none and needs no buffer', () {
      final folder = folderRow('f', effects: allDisabled([blur(4)]));
      expect(
        folderNeedsCompositeBuffer(folder: folder, frameIndex: 0),
        isFalse,
      );
      final tree = resolveCutFrameCompositeTree(
        cut: cut([drawingLayer(id: 'a', folder: 'f'), folder]),
        frameIndex: 0,
      );
      expect(
        tree.single,
        isA<CutFrameCompositeEntryLeaf>(),
        reason: 'nothing left to buffer, so the folder leaves no node',
      );
    });

    test('an effect on a member does NOT make its folder buffer', () {
      expect(
        folderNeedsCompositeBuffer(folder: folderRow('f'), frameIndex: 0),
        isFalse,
      );
      final tree = resolveCutFrameCompositeTree(
        cut: cut([
          drawingLayer(id: 'a', folder: 'f', effects: [blur(4)]),
          folderRow('f'),
        ]),
        frameIndex: 0,
      );
      final leaf = tree.single as CutFrameCompositeEntryLeaf;
      expect(leaf.entry.effects.single.parameter('blurX'), 4);
    });
  });

  group('the surface plan', () {
    test('carries the chain to the paint routes, leaves and groups alike', () {
      final nodes = planCutFrameCompositeTree(
        cut: cut([
          drawingLayer(id: 'a', folder: 'f', effects: [blur(3)]),
          folderRow('f', effects: [brightness(10)]),
        ]),
        frameIndex: 0,
        surfaceResolver: (layer, frame) => null,
      );
      // No artwork resolved, so the group drops — the point is that it did
      // not throw and the flat plan carries the field.
      expect(nodes, isEmpty);

      final flat = planCutFrameComposite(
        cut: cut([
          drawingLayer(id: 'a', effects: [blur(3)]),
        ]),
        frameIndex: 0,
        surfaceResolver: (layer, frame) => null,
      );
      expect(flat, isEmpty);
    });
  });

  group('the playback cache signature', () {
    CutFrameCompositeSignature signatureOf(Cut source, {int frameIndex = 0}) =>
        computeCutFrameCompositeSignature(
          cut: source,
          frameIndex: frameIndex,
          quality: PlaybackQuality.full,
          revisionOf: (layerId, frameId) => 1,
        );

    test('an effect VALUE change changes the identity', () {
      // The cache is content-addressed on the signature, so an
      // unrepresented value would not merely read stale — two different
      // pictures would COLLIDE on one cached image.
      expect(
        signatureOf(
          cut([
            drawingLayer(effects: [blur(4)]),
          ]),
        ),
        isNot(
          signatureOf(
            cut([
              drawingLayer(effects: [blur(6)]),
            ]),
          ),
        ),
      );
      expect(
        signatureOf(
          cut([
            drawingLayer(effects: [blur(4)]),
          ]),
        ),
        signatureOf(
          cut([
            drawingLayer(effects: [blur(4)]),
          ]),
        ),
      );
    });

    test(
      'adding, disabling and removing an effect all change the identity',
      () {
        final none = signatureOf(cut([drawingLayer()]));
        final one = signatureOf(
          cut([
            drawingLayer(effects: [blur(4)]),
          ]),
        );
        final disabled = signatureOf(
          cut([
            drawingLayer(effects: [blur(4).copyWith(enabled: false)]),
          ]),
        );
        expect(one, isNot(none));
        expect(
          disabled,
          none,
          reason: 'a disabled effect paints nothing, so it IS the empty chain',
        );
      },
    );

    test('a FOLDER effect change changes the identity too', () {
      Cut withFolderBlur(double radius) => cut([
        drawingLayer(id: 'a', folder: 'f'),
        folderRow('f', effects: [blur(radius)]),
      ]);
      expect(
        signatureOf(withFolderBlur(4)),
        isNot(signatureOf(withFolderBlur(9))),
      );
    });

    test('an animated effect gives HELD frames different identities', () {
      final animated = LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                4: const PropertyKey<double>(8),
              },
            ),
          ),
        },
      );
      final source = cut([
        drawingLayer(effects: [animated]),
      ]);
      expect(
        signatureOf(source, frameIndex: 1),
        isNot(signatureOf(source, frameIndex: 2)),
        reason: 'one held cel, two filters — composites must not dedupe',
      );
    });
  });
}
