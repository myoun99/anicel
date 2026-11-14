import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/fx_plugin_values.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_cut_as_surfaces.dart';
import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/fx_plugin_file.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고」 — a plugin runs
/// wherever it stands in a chain, after a cel's colour keys as after
/// anything else, its run bound where the cut is known: its build, the
/// frame, and the rows it reads as their own cels hold them. And a frame
/// hands its values as the spec says.
///
/// ↩️🗣️I-132-Q32 b (「b 로 첫 판」): a plugin at the head of a cel row's
/// chain — after nothing but colour keys — ran over the whole cel at the
/// seam every route showed a cel through, its keys walked before it on the
/// CPU, until it was a step of the chain like any other
/// (float-warp-resamples-in-the-c-engine (2), 2026-11-11). The engine's
/// steps are pinned where they run (`a_plugin_reads_its_chain_straight_test`,
/// `a_plugin_runs_over_what_its_chain_made_test`,
/// `the_engine_keys_a_row_as_each_pixel_is_keyed_test`).
void main() {
  const tileSize = defaultCelTileSize;
  const paper = CanvasSize(width: 2 * tileSize, height: tileSize);

  final description = fxPluginDescriptionOf(
    'test.shift',
    name: 'Shift',
    params: [
      {
        'id': 'by',
        'kind': 'number',
        'label': 'By',
        'default': 1,
        'min': 0,
        'max': 8,
      },
      {'id': 'map', 'kind': 'layer', 'label': 'Map'},
    ],
  );

  /// A cel of [paper] with [pixels] (x, y → straight rgba) on it.
  BitmapSurface celWith(Map<(int, int), List<int>> pixels) {
    final tiles = <TileCoord, Uint8List>{};
    for (final MapEntry(key: (x, y), value: rgba) in pixels.entries) {
      final coord = TileCoord(x: x ~/ tileSize, y: y ~/ tileSize);
      final bytes = tiles[coord] ??= Uint8List(tileSize * tileSize * 4);
      bytes.setAll(((y % tileSize) * tileSize + x % tileSize) * 4, rgba);
    }
    return BitmapSurface(
      canvasSize: paper,
      pasteboardReach: PasteboardReach.none,
      tileSize: tileSize,
      tiles: {
        for (final MapEntry(key: coord, value: bytes) in tiles.entries)
          coord: BitmapTile(size: tileSize, pixels: bytes),
      },
    );
  }


  ResolvedLayerEffect plugin({
    double by = 1,
    LayerId? map,
    FxPluginRun? run,
    int frame = 0,
  }) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: description,
    values: [by, 0],
    layers: {'map': map},
    frame: frame,
    run: run,
  );

  ResolvedLayerEffect key({int color = 0xFF00FF00}) => ResolvedLayerEffect(
    kind: EffectKind.colorKey,
    values: [
      for (final spec in EffectKind.colorKey.parameters)
        switch (spec.id) {
          'keyColor' => color.toDouble(),
          'amount' => 100,
          _ => spec.defaultValue,
        },
    ],
  );


  const red = [200, 10, 20, 255];
  const green = [0, 255, 0, 255];

  test('a plugin at the head of a cel row\'s chain is a step of the chain, '
      'as one anywhere else is — the row lays its cel', () {
    final cel = celWith({(3, 0): green});
    final runner = ShiftingFxPlugin(by: 1);
    final chain = [key(), plugin(run: fxPluginRunOf(runner)), key()];

    final row = CutFrameCompositeLayer(
      surface: cel,
      opacity: 1,
      effects: chain,
    );

    expect(identical(row.surface, cel), isTrue);
    expect(row.effects, chain);
    expect(runner.renders, 0, reason: 'the engine runs it, as a step');
  });

  test('a frame hands every kind of value as the spec says', () {
    final values = fxPluginValuesOf(
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: fxPluginDescriptionOf(
          'test.all',
          name: 'All',
          params: [
            {
              'id': 'n',
              'kind': 'angle',
              'label': 'N',
              'default': 0,
              'min': -90,
              'max': 90,
            },
            {'id': 'c', 'kind': 'color', 'label': 'C', 'default': [1, 0, 0, 1]},
            {'id': 'p', 'kind': 'point', 'label': 'P'},
            {'id': 'q', 'kind': 'point', 'label': 'Q'},
            {'id': 'f', 'kind': 'checkbox', 'label': 'F', 'default': false},
            {'id': 'l', 'kind': 'layer', 'label': 'L'},
            {'id': 'k', 'kind': 'layer', 'label': 'K'},
          ],
        ),
        values: [-30, 0x80336699, 0, 0, 0.7, 0, 0],
        points: {'p': CanvasPoint(x: 3, y: 1)},
        layers: {'l': const LayerId('b'), 'k': null},
      ),
      paper: paper,
      rows: const [LayerId('a'), LayerId('b')],
    );

    expect(values, [
      -30, 0, 0, 0, //
      0x33 / 255, 0x66 / 255, 0x99 / 255, 0x80 / 255,
      3, 1, 0, 0,
      tileSize, tileSize / 2, 0, 0, // at rest: the paper's middle
      1, 0, 0, 0,
      1, 0, 0, 0,
      -1, 0, 0, 0,
    ]);
  });

  group('the binding', () {
    final shift = ShiftingFxPlugin();
    Layer row(
      String id, {
      List<LayerEffect> effects = const [],
      LayerKind kind = LayerKind.animation,
    }) => Layer(
      id: LayerId(id),
      name: id,
      kind: kind,
      frames: [
        for (final at in [0, 2])
          Frame(id: FrameId('$id$at'), duration: 2, strokes: const []),
      ],
      timeline: {
        for (final at in [0, 2])
          at: TimelineExposure.drawing(FrameId('$id$at'), length: 2),
      },
      effects: effects,
    );
    LayerEffect pluginOn({String? map}) => LayerEffect.defaults(
      id: const EffectId('fx'),
      kind: EffectKind.plugin,
      plugin: description,
    ).withLayer('map', map == null ? null : LayerId(map));
    final cels = <FrameId, BitmapSurface>{
      const FrameId('m0'): celWith({(1, 1): red}),
      const FrameId('m2'): celWith({(2, 2): red}),
    };
    final binding = deviceFxPluginBinding(
      runnerFor: (plugin) => plugin.id == description.id ? shift : null,
      frameRate: ProjectFrameRate.fps24,
      surfaceOf: (layer, frame) => cels[frame.id],
    );
    Cut cutOf(List<Layer> layers) => Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 4,
      canvasSize: paper,
      layers: layers,
    );
    List<ResolvedLayerEffect> bound(Layer a, List<Layer> others, int at) =>
        binding(
          resolveLayerEffectsAt(
            effects: a.effects,
            frameIndex: at,
            blocks: null,
            worn: null,
          ),
          cut: cutOf([...others, a]),
          frameIndex: at,
        );

    test('runs a plugin at its frame, reading its row\'s own cel there', () {
      final a = row('a', effects: [pluginOn(map: 'm')]);
      final run = bound(a, [row('m')], 3).single.run!;

      expect(identical(run.runner, shift), isTrue);
      expect(run.moment, (
        frameIndex: 3,
        time: 3 / 24,
        frameRate: 24.0,
        scale: 1.0,
      ));
      expect(run.rows.keys, [const LayerId('m')]);
      expect(identical(run.rows[const LayerId('m')], cels[const FrameId('m2')]),
          isTrue);
    });

    test('a row the cut has not is not read', () {
      final a = row('a', effects: [pluginOn(map: 'gone')]);
      expect(bound(a, const [], 0).single.run!.rows, isEmpty);
    });

    test('runs one after an app effect and on an image row too (🗣️I-132-Q34 '
        'a 「어디에 걸어도 돌고」) — none where the device has not the plugin', () {
      final blurred = row('a', effects: [
        LayerEffect.defaults(id: const EffectId('b'), kind: EffectKind.blur)
            .withParameter('blurriness', EffectParameter(value: 3)),
        pluginOn(),
      ]);
      expect(
        [for (final e in bound(blurred, const [], 0)) e.run != null],
        [false, true],
      );

      final image = row('a', kind: LayerKind.image, effects: [pluginOn()]);
      expect(bound(image, const [], 0).single.run, isNotNull);

      final elsewhere = deviceFxPluginBinding(
        runnerFor: (_) => null,
        frameRate: ProjectFrameRate.fps24,
        surfaceOf: (layer, frame) => null,
      );
      final a = row('a', effects: [pluginOn()]);
      expect(
        elsewhere(
          resolveLayerEffectsAt(
            effects: a.effects,
            frameIndex: 0,
            blocks: null,
            worn: null,
          ),
          cut: cutOf([a]),
          frameIndex: 0,
        ).single.run,
        isNull,
      );
    });

    test('runs none on a chain of keys alone', () {
      final a = row('a');
      final keys = [key()];
      expect(binding(keys, cut: cutOf([a]), frameIndex: 0), keys);
    });

    test('the plan binds it on every row it lays, in the chain it hands on '
        '— and a plugin\'s sample knows its frame where nothing binds it', () {
      final a = row('a', effects: [pluginOn()]);
      final cel = celWith({(3, 0): red});
      final nodes = planCutFrameCompositeTree(
        cut: cutOf([a]),
        frameIndex: 0,
        reading: (surfaces: (layer, frame) => cel, plugins: binding),
      );
      final layer = (nodes.single as CompositeLeaf<CutFrameCompositeLayer>)
          .payload;
      expect(identical(layer.surface, cel), isTrue);
      expect(identical(layer.effects.single.run?.runner, shift), isTrue);

      expect(
        resolveLayerEffectsAt(
          effects: a.effects,
          frameIndex: 3,
          blocks: null,
          worn: null,
        ).single.frame,
        3,
      );
      expect(
        resolveLayerEffectsAt(
          effects: [
            LayerEffect.defaults(
              id: const EffectId('b'),
              kind: EffectKind.blur,
            ).withParameter('blurriness', EffectParameter(value: 3)),
          ],
          frameIndex: 3,
          blocks: null,
          worn: null,
        ).single.frame,
        isNull,
      );
    });
  });
}
