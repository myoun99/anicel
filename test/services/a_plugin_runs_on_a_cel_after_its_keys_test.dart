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
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cel_plugin_pass.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// 🗣️I-132-Q32 b (유저 2026-10-30 「b 로 첫 판」): a plugin runs at the head
/// of a cel row's chain — after nothing but colour keys — over the whole
/// cel, at the seam every route shows a cel through, its run bound where
/// the cut is known: its build, the frame, and the rows it reads as their
/// own cels hold them.
void main() {
  const tileSize = 4;
  const paper = CanvasSize(width: 8, height: 4);

  final description = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'test.shift',
    'name': 'Shift',
    'vendor': 'Test',
    'version': '1',
    'can': ['cpu'],
    'params': [
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
  })!;

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

  List<int> pixelOf(BitmapSurface surface, int x, int y) {
    final tile = surface.tileAt(TileCoord(x: x ~/ tileSize, y: y ~/ tileSize));
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final at = ((y % tileSize) * tileSize + x % tileSize) * 4;
    return tile.pixels.sublist(at, at + 4);
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

  ResolvedLayerEffect blur() => ResolvedLayerEffect(
    kind: EffectKind.blur,
    values: [
      for (final spec in EffectKind.blur.parameters)
        if (spec.id == 'blurriness') 3 else spec.defaultValue,
    ],
  );

  const red = [200, 10, 20, 255];
  const green = [0, 255, 0, 255];

  group('the source run', () {
    test('ends at a plugin right after its keys — one, and only there', () {
      final a = key();
      final p = plugin();
      final q = plugin(by: 2);
      final b = blur();

      List<List<ResolvedLayerEffect>> split(List<ResolvedLayerEffect> of) {
        final (:source, :paint) = splitSourceEffects(of);
        return [source, paint];
      }

      expect(split([a, p, b]), [[a, p], [b]]);
      expect(split([p, a]), [[p], [a]]);
      expect(split([p, q]), [[p], [q]]);
      expect(split([b, p]), [<ResolvedLayerEffect>[], [b, p]]);
    });
  });

  group('the pass', () {
    test('moves a pixel across a tile\'s edge — the cel is one picture', () {
      final runner = ShiftingFxPlugin();
      final cel = celWith({(3, 1): red});

      final shown = celSurfaceAsShown(cel, [
        plugin(run: fxPluginRunOf(runner)),
      ]);

      expect(pixelOf(shown, 4, 1), red);
      expect(pixelOf(shown, 3, 1), [0, 0, 0, 0]);
      expect(shown.tileAt(TileCoord(x: 0, y: 0)), isNull,
          reason: 'a tile left clear is dropped, as a commit drops one');
      // The paper, wider by the reach the plugin named, at its place.
      expect(runner.inputs.single, (left: -1, top: -1, width: 10, height: 6));
    });

    test('takes in the ink past the paper too, and reaches no further than '
        'the cel can hold — keeping no tile past its wall', () {
      final runner = ShiftingFxPlugin(by: 0);
      final past = BitmapSurface(
        canvasSize: paper,
        pasteboardReach: PasteboardReach.whole,
        tileSize: tileSize,
        tiles: {
          // (-2, 1): on the pasteboard, left of the paper.
          TileCoord(x: -1, y: 0): BitmapTile(
            size: tileSize,
            pixels: Uint8List(tileSize * tileSize * 4)..setAll(24, red),
          ),
        },
      );

      final shown = celSurfaceAsShown(past, [
        plugin(run: fxPluginRunOf(runner)),
      ]);

      expect(runner.inputs.single, (left: -4, top: 0, width: 12, height: 4));
      expect(shown.tileAt(TileCoord(x: -1, y: 0))!.pixels.sublist(24, 28), red);

      final far = ShiftingFxPlugin(by: 1000);
      celSurfaceAsShown(celWith({(1, 1): red}), [
        plugin(run: fxPluginRunOf(far)),
      ]);
      expect(
        far.inputs.single,
        (left: -8, top: -8, width: 24, height: 20),
        reason: 'as far as the cel is long, and no further',
      );

      final edge = celSurfaceAsShown(celWith({(7, 1): red}), [
        plugin(run: fxPluginRunOf(ShiftingFxPlugin())),
      ]);
      expect(
        edge.tiles.keys,
        isEmpty,
        reason: 'moved past the wall it is gone, as a stroke past it is',
      );
    });

    test('a pixel the plugin leaves without cover is clear, whatever colour '
        'it gives it', () {
      final shown = celSurfaceAsShown(celWith({(1, 1): red}), [
        plugin(run: fxPluginRunOf(_ColourWithoutCover())),
      ]);

      expect(pixelOf(shown, 1, 1), red);
      expect(pixelOf(shown, 0, 0), [0, 0, 0, 0]);
    });

    test('lays what the plugin draws round the cel where it drew it — in '
        'its reach past the paper too', () {
      final cel = BitmapSurface(
        canvasSize: paper,
        pasteboardReach: PasteboardReach.whole,
        tileSize: tileSize,
      );

      final shown = celSurfaceAsShown(cel, [
        plugin(run: fxPluginRunOf(_Fill(by: 1))),
      ]);

      // Row 1 of the tile left of the paper: its last pixel is x -1, in the
      // plugin's reach; its first is x -4, past it.
      final row = shown
          .tileAt(TileCoord(x: -1, y: 0))!
          .pixels
          .sublist(tileSize * 4, tileSize * 8);
      expect(
        [row.sublist(12, 16), row.sublist(0, 4)],
        [green, [0, 0, 0, 0]],
      );
    });

    test('runs after the keys, over what they left', () {
      final cel = celWith({(1, 1): red, (2, 1): green});

      final shown = celSurfaceAsShown(cel, [
        key(),
        plugin(run: fxPluginRunOf(ShiftingFxPlugin())),
      ]);

      expect(pixelOf(shown, 2, 1), red);
      expect(pixelOf(shown, 3, 1), [0, 0, 0, 0], reason: 'keyed away first');
    });

    test('hands the plugin premultiplied pixels and reads its back '
        'straight', () {
      final runner = ShiftingFxPlugin(by: 0);
      final cel = celWith({(5, 2): [200, 100, 50, 128]});

      final shown = celSurfaceAsShown(cel, [
        plugin(run: fxPluginRunOf(runner)),
      ]);

      // No reach: the paper itself.
      const at = (2 * 8 + 5) * 4;
      expect(runner.lastInput.sublist(at, at + 4), [100, 50, 25, 128]);
      expect(pixelOf(shown, 5, 2), [199, 100, 50, 128]);
    });

    test('a layer parameter reads its row\'s own picture where the canvas '
        'puts it, its place in the frame\'s values', () {
      final runner = ShiftingFxPlugin(by: 0);
      final map = celWith({(6, 0): green});
      final run = fxPluginRunOf(runner, rows: {const LayerId('m'): map});

      celSurfaceAsShown(celWith({(0, 0): red}), [
        plugin(by: 0, map: const LayerId('m'), run: run),
      ]);

      expect(runner.lastValues, [0, 0, 0, 0, 0, 0, 0, 0]);
      final layer = runner.lastLayers.single;
      expect((layer.left, layer.top, layer.width), (0, 0, 8));
      const at = 6 * 4;
      expect(layer.pixels.sublist(at, at + 4), green);
    });

    test('a row it names with no cel there is a clear picture; one not in '
        'its cut is none', () {
      final runner = ShiftingFxPlugin(by: 0);

      celSurfaceAsShown(celWith({(0, 0): red}), [
        plugin(
          by: 0,
          map: const LayerId('m'),
          run: fxPluginRunOf(runner, rows: {const LayerId('m'): null}),
        ),
      ]);
      expect(runner.lastValues[4], 0);
      expect(
        runner.lastLayers.single.pixels.every((byte) => byte == 0),
        isTrue,
      );

      celSurfaceAsShown(celWith({(1, 0): red}), [
        plugin(by: 0, map: const LayerId('gone'), run: fxPluginRunOf(runner)),
      ]);
      expect(runner.lastValues[4], -1);
      expect(runner.lastLayers, isEmpty);
    });

    test('runs once a picture and sample — again for another frame, value '
        'or row', () {
      final runner = ShiftingFxPlugin();
      final cel = celWith({(1, 1): red});
      final map = celWith({(2, 2): red});
      final run = fxPluginRunOf(runner, rows: {const LayerId('m'): map});

      celSurfaceAsShown(cel, [plugin(map: const LayerId('m'), run: run)]);
      celSurfaceAsShown(cel, [
        plugin(
          map: const LayerId('m'),
          run: fxPluginRunOf(runner, rows: {const LayerId('m'): map}),
        ),
      ]);
      expect(runner.renders, 1, reason: 'an equal run is the same sample');

      celSurfaceAsShown(cel, [
        plugin(map: const LayerId('m'), run: fxPluginRunOf(runner, frame: 1)),
      ]);
      celSurfaceAsShown(cel, [
        plugin(by: 2, map: const LayerId('m'), run: run),
      ]);
      celSurfaceAsShown(cel, [
        plugin(
          map: const LayerId('m'),
          run: fxPluginRunOf(runner, rows: {const LayerId('m'): celWith({})}),
        ),
      ]);
      expect(runner.renders, 4);
    });

    test('a plugin with no run, or one that fails, leaves the cel as it is',
        () {
      final cel = celWith({(1, 1): red});
      expect(identical(celSurfaceAsShown(cel, [plugin()]), cel), isTrue);
      expect(
        identical(
          celSurfaceAsShown(cel, [
            plugin(run: fxPluginRunOf(ShiftingFxPlugin(fails: true))),
          ]),
          cel,
        ),
        isTrue,
      );
      expect(
        identical(
          celSurfaceAsShown(cel, [
            plugin(run: fxPluginRunOf(ShiftingFxPlugin(reachFails: true))),
          ]),
          cel,
        ),
        isTrue,
      );
    });

    test('is never asked of a tile', () {
      final tile = BitmapTile.blank(size: tileSize);
      final effects = [plugin(run: fxPluginRunOf(ShiftingFxPlugin()))];
      expect(
        () => celTileAsShown(tile, null, effects, tileSize),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => celStraightTileAsShown(Uint8List(64), null, effects, tileSize),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  test('a frame hands every kind of value as the spec says', () {
    final values = fxPluginValuesOf(
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: FxPluginDescription.fromJson({
          'spec': 1,
          'id': 'test.all',
          'name': 'All',
          'vendor': 'Test',
          'version': '1',
          'can': ['cpu'],
          'params': [
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
        }),
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
      4, 2, 0, 0, // at rest: the paper's middle
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
          resolveLayerEffectsAt(effects: a.effects, frameIndex: at),
          cut: cutOf([...others, a]),
          row: a,
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

    test('runs none after an app effect, on an image row, or where the '
        'device has not the plugin', () {
      final blurred = row('a', effects: [
        LayerEffect.defaults(id: const EffectId('b'), kind: EffectKind.blur)
            .withParameter('blurriness', EffectParameter(value: 3)),
        pluginOn(),
      ]);
      expect(
        [for (final e in bound(blurred, const [], 0)) e.run],
        [null, null],
      );

      final image = row('a', kind: LayerKind.image, effects: [pluginOn()]);
      expect(bound(image, const [], 0).single.run, isNull);

      final elsewhere = deviceFxPluginBinding(
        runnerFor: (_) => null,
        frameRate: ProjectFrameRate.fps24,
        surfaceOf: (layer, frame) => null,
      );
      final a = row('a', effects: [pluginOn()]);
      expect(
        elsewhere(
          resolveLayerEffectsAt(effects: a.effects, frameIndex: 0),
          cut: cutOf([a]),
          row: a,
          frameIndex: 0,
        ).single.run,
        isNull,
      );
    });

    test('runs none on a chain of keys alone', () {
      final a = row('a');
      final keys = [key()];
      expect(binding(keys, cut: cutOf([a]), row: a, frameIndex: 0), keys);
    });

    test('the plan runs it on every row it lays — and a plugin\'s sample '
        'knows its frame where nothing binds it', () {
      final a = row('a', effects: [pluginOn()]);
      final cel = celWith({(3, 0): red});
      final nodes = planCutFrameCompositeTree(
        cut: cutOf([a]),
        frameIndex: 0,
        reading: (surfaces: (layer, frame) => cel, plugins: binding),
      );
      final layer = (nodes.single as CompositeLeaf<CutFrameCompositeLayer>)
          .payload;
      expect(pixelOf(layer.surface, 4, 0), red);
      expect(layer.effects, isEmpty);

      expect(
        resolveLayerEffectsAt(effects: a.effects, frameIndex: 3).single.frame,
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
        ).single.frame,
        isNull,
      );
    });
  });
}

/// Reaches [by] past what it is handed and covers all of it in green.
final class _Fill implements FxPluginRunner {
  _Fill({required this.by});

  final int by;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => by;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    final out = Uint8List(input.pixels.length);
    for (var at = 0; at < out.length; at += 4) {
      out.setAll(at, const [0, 255, 0, 255]);
    }
    return out;
  }

  @override
  void close() {}
}

/// Hands every pixel back as it came, but gives the ones without cover a
/// colour — as a plugin told nothing of how a clear pixel is kept may.
final class _ColourWithoutCover implements FxPluginRunner {
  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    final out = Uint8List.fromList(input.pixels);
    for (var at = 0; at < out.length; at += 4) {
      if (out[at + 3] == 0) {
        out.fillRange(at, at + 3, 9);
      }
    }
    return out;
  }

  @override
  void close() {}
}
