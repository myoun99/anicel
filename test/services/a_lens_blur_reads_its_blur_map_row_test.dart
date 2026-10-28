import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// 🗣️I-132-Q16 a (유저 2026-10-28): a camera lens blur's Blur Map Layer is a
/// row of its cut, and the tree lays that row beside the node whose chain
/// reads it ([CompositeReadsRows]) — as it draws by itself there: where it
/// lies (Q21 a), its eye not asked (Q23 a 「꺼도 맵으로 읽는다」), at its own
/// strength (Q24 b 「화면에 보이는 그대로」), on nothing, so in no blend — and
/// reading no map of its own (Q22 a, one level).
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  /// A camera lens blur whose blur map is [map], none for null.
  LayerEffect lens({String id = 'lens', String? map}) =>
      LayerEffect.defaults(id: EffectId(id), kind: EffectKind.cameraLensBlur)
          .withParameter('blurRadius', EffectParameter(value: 6))
          .withLayer('blurMapLayer', map == null ? null : LayerId(map));

  /// Row [id], showing cel `<id>0` from frame 0 and cel `<id>2` from frame 2
  /// — none past [until].
  Layer row(
    String id, {
    List<LayerEffect> effects = const [],
    double opacity = 1,
    bool visible = true,
    bool clips = false,
    LayerBlendMode blend = LayerBlendMode.normal,
    String? folder,
    int until = 4,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [
      for (final at in [0, 2])
        Frame(id: FrameId('$id$at'), duration: 2, strokes: const []),
    ],
    timeline: {
      for (final at in [0, 2])
        if (at < until)
          at: TimelineExposure.drawing(FrameId('$id$at'), length: 2),
    },
    effects: effects,
    opacity: opacity,
    isVisible: visible,
    clipsToBelow: clips,
    blendMode: blend,
    folderId: folder == null ? null : LayerId(folder),
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 4,
    canvasSize: canvasSize,
  );

  List<CompositeNode<CutFrameCompositeRow>> treeOf(
    List<Layer> layers, {
    int frameIndex = 0,
    String? live,
    List<CutFrameCompositeGhost> Function(Layer row)? ghostsOf,
  }) => resolveCutFrameCompositeTree(
    cut: cutOf(layers),
    frameIndex: frameIndex,
    liveLayerId: live == null ? null : LayerId(live),
    ghostsOf: ghostsOf,
  );

  /// The one node of [nodes] that reads rows.
  CompositeReadsRows<CutFrameCompositeRow> readerIn(
    List<CompositeNode<CutFrameCompositeRow>> nodes,
  ) => nodes.whereType<CompositeReadsRows<CutFrameCompositeRow>>().single;

  /// The row [id] as [reader] reads it, where it is one leaf.
  CutFrameCompositeRow readOf(
    CompositeReadsRows<CutFrameCompositeRow> reader,
    String id,
  ) => switch (reader.rows[LayerId(id)]) {
    [CompositeLeaf(:final payload)] => payload,
    final drawn => throw StateError('$id is drawn as $drawn'),
  };

  test('a row whose chain names another stands beside that row as it '
      'draws there, the row in its own place as well', () {
    final tree = treeOf([
      row('b'),
      row('a', effects: [lens(map: 'b')]),
    ]);
    expect(tree, hasLength(2));
    expect(
      (tree.first as CompositeLeaf<CutFrameCompositeRow>).payload,
      isA<CutFrameCompositeEntry>(),
    );
    final reader = readerIn(tree);
    final a = (reader.node as CompositeLeaf<CutFrameCompositeRow>).payload;
    expect((a as CutFrameCompositeEntry).layer.id, const LayerId('a'));
    final b = readOf(reader, 'b') as CutFrameCompositeEntry;
    expect((b.layer.id, b.frame.id), (const LayerId('b'), const FrameId('b0')));
  });

  test('its eye is not asked (Q23 a): a hidden row stands nowhere but '
      'where it is read', () {
    final tree = treeOf([
      row('b', visible: false),
      row('a', effects: [lens(map: 'b')]),
    ]);
    expect(tree, hasLength(1));
    expect(readOf(readerIn(tree), 'b'), isA<CutFrameCompositeEntry>());
  });

  test('at its own strength (Q24 b) — not its folder\'s — in no blend, and '
      'where it lies', () {
    final tree = treeOf([
      row('b', opacity: 0.4, blend: LayerBlendMode.multiply, folder: 'f'),
      createFolderLayer(
        id: const LayerId('f'),
        name: 'F',
      ).copyWith(opacity: 0.5),
      row('a', effects: [lens(map: 'b')]),
    ]);
    final b = readOf(readerIn(tree), 'b');
    expect(b.opacity, 0.4);
    expect(b.blendMode, LayerBlendMode.normal);
  });

  test('a map\'s own chain reads no map (Q22 a): it names none there, and '
      'reads its own where it stands', () {
    final tree = treeOf([
      row('c'),
      row('b', effects: [lens(id: 'own', map: 'c')]),
      row('a', effects: [lens(map: 'b')]),
    ]);
    final readers = tree.whereType<CompositeReadsRows<CutFrameCompositeRow>>();
    expect(readers, hasLength(2), reason: 'b reads c where it stands');
    final b = readOf(readers.last, 'b');
    expect(b.effects.single.kind, EffectKind.cameraLensBlur);
    expect(b.effects.single.layers, {'blurMapLayer': null});
    expect(
      readOf(readers.first, 'c'),
      isA<CutFrameCompositeEntry>(),
      reason: 'fixture: b\'s own lens reads c',
    );
  });

  test('a row that is not the cut\'s is none: nothing stands beside it', () {
    final tree = treeOf([
      row('a', effects: [lens(map: 'gone')]),
    ]);
    expect(tree.single, isA<CompositeLeaf<CutFrameCompositeRow>>());
  });

  test('a row that exposes no cel there is read as nothing drawn — the '
      'row drawn on as its live surface', () {
    final layers = [
      row('b', until: 2),
      row('a', effects: [lens(map: 'b')]),
    ];
    expect(readerIn(treeOf(layers, frameIndex: 3)).rows, {
      const LayerId('b'): isEmpty,
    });
    final live = readOf(readerIn(treeOf(layers, frameIndex: 3, live: 'b')), 'b');
    expect(live, isA<CutFrameCompositeLiveRow>());
    expect(live.blendMode, LayerBlendMode.normal);
  });

  test('a folder\'s chain reads as a row\'s does', () {
    final tree = treeOf([
      row('b'),
      row('a', folder: 'f'),
      createFolderLayer(
        id: const LayerId('f'),
        name: 'F',
      ).copyWith(effects: [lens(map: 'b')]),
    ]);
    final reader = readerIn(tree);
    expect(reader.node, isA<CompositeGroup<CutFrameCompositeRow>>());
    expect(readOf(reader, 'b'), isA<CutFrameCompositeEntry>());
  });

  test('a clip\'s base that reads is the node its opaque copy points at', () {
    final tree = treeOf([
      row('b'),
      row('a', effects: [lens(map: 'b')]),
      row('c', clips: true, blend: LayerBlendMode.multiply),
    ]);
    final clip = tree.whereType<CompositeClip<CutFrameCompositeRow>>().single;
    expect(clip.base, isA<CompositeReadsRows<CutFrameCompositeRow>>());
    final opaque = [
      for (final node in clip.scope)
        if (node case CompositeOpaque<CutFrameCompositeRow>(:final of)) of,
      for (final node in clip.scope)
        if (node case CompositeBackdropBlend<CutFrameCompositeRow>(
          :final backdrop,
        ))
          for (final under in backdrop)
            if (under case CompositeOpaque<CutFrameCompositeRow>(:final of))
              of,
    ];
    expect(opaque, isNotEmpty, reason: 'fixture: the multiply reads it');
    for (final of in opaque) {
      expect(identical(of, clip.base), isTrue);
    }
  });

  test('a ghost reads its map at the frame its peg reaches, as the screen '
      'shows it there (I-8-Q5)', () {
    final tree = treeOf(
      [
        row('b'),
        row('a', effects: [lens(map: 'b')]),
      ],
      ghostsOf: (layer) => [
        if (layer.id == const LayerId('a'))
          CutFrameCompositeGhost(
            layer: layer,
            frameId: const FrameId('a2'),
            frameIndex: 2,
            opacity: 0.4,
            effects: resolveLayerEffectsAt(
              effects: layer.effects,
              frameIndex: 2,
            ),
          ),
      ],
    );
    final readers = tree.whereType<CompositeReadsRows<CutFrameCompositeRow>>();
    expect(readers, hasLength(2));
    final [ghost, own] = [
      for (final reader in readers)
        (readOf(reader, 'b') as CutFrameCompositeEntry).frame.id,
    ];
    expect(ghost, const FrameId('b2'));
    expect(own, const FrameId('b0'));
  });

  test('what the map row draws signs the frame it is read in', () {
    CutFrameCompositeSignature signed(int revision) =>
        computeCutFrameCompositeSignature(
          cut: cutOf([
            row('b', visible: false),
            row('a', effects: [lens(map: 'b')]),
          ]),
          frameIndex: 0,
          revisionOf: (layer, _) => layer == const LayerId('b') ? revision : 1,
        );
    expect(signed(1), signed(1));
    expect(signed(2), isNot(signed(1)));
  });
}
