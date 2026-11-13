import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/composite_effect_paint.dart'
    show pixelThroughChain;
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_on_the_engine.dart';
import '../helpers/an_effect_sampled.dart';

/// 🚨★★★A ROW'S LEADING COLOUR KEYS ARE THE ENGINE'S, AND IT KEYS EACH
/// PIXEL AS THE KEYS' OWN DEFINITION DOES (float-warp-resamples-in-the-c-
/// engine (1), 관제 2026-11-11).
///
/// Keys at a chain's head are no CPU pass (`celSourceKeys`): a row hands
/// its cel's bytes to the engine with the keys in its chain, and the engine
/// keys its stored bytes — as the row's own keys where the chain is that
/// run and colour after it, as its chain's first op where more follows — a
/// plug-in among it, which reads what they keyed — or a hand holds pixels
/// over the row. ↩️A plug-in after them read them keyed on the CPU, by a
/// walk of its own, until it was a step of the chain
/// (float-warp-resamples-in-the-c-engine (2), 2026-11-11). Each lays what
/// the row of the cel keyed by the definition a pixel at a time lays
/// (`pixelThroughChain`, the eyedropper's door) — to the byte, the keys'
/// axes each: a colour, a tolerance, an Amount, keeping instead of
/// erasing, a run longer than one set of tables.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  const canvas = CanvasSize(width: 2 * side, height: side);
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  /// The colours the keys below name, laid among a spread of others: a key
  /// of no tolerance takes nothing a spread happens to miss.
  const named = [
    [64, 192, 96],
    [255, 255, 255],
    [200, 40, 10],
  ];

  /// The alphas a key's Amount rounds differently at, a band each.
  const alphas = [255, 1, 70, 128, 200, 254, 66, 0];

  /// A tile at [column] of colours every red against every green, the
  /// [named] ones every seventh pixel, in bands of [alphas].
  BitmapTile tileAt(int column) {
    final pixels = Uint8List(side * side * 4);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final at = (y * side + x) * 4;
        final i = y * side + x + column * 7;
        final colour = i % 7 == 0
            ? named[i ~/ 7 % named.length]
            : [(x * 2 + column) & 255, (y * 2) & 255, (i * 5) & 255];
        pixels.setAll(at, [
          ...colour,
          alphas[(y ~/ 16 + column) % alphas.length],
        ]);
      }
    }
    return BitmapTile(size: side, pixels: pixels);
  }

  BitmapSurface celOf(Iterable<int> columns) => BitmapSurface(
    canvasSize: canvas,
    tileSize: side,
    tiles: {
      for (final column in columns) TileCoord(x: column, y: 0): tileAt(column),
    },
  );

  /// [cel] with each pixel's alpha what [keys] leave it, one at a time.
  BitmapSurface keyedByDefinition(
    BitmapSurface cel,
    List<ResolvedLayerEffect> keys,
  ) => BitmapSurface(
    canvasSize: cel.canvasSize,
    tileSize: cel.tileSize,
    tiles: {
      for (final MapEntry(key: coord, value: tile) in cel.tiles.entries)
        coord: tile.readPixels((_, view) {
          final pixels = Uint8List.fromList(view);
          for (var at = 0; at < pixels.length; at += 4) {
            pixels[at + 3] = pixelThroughChain(
              keys,
              red: pixels[at],
              green: pixels[at + 1],
              blue: pixels[at + 2],
              alpha: pixels[at + 3],
            ).alpha;
          }
          return BitmapTile(size: side, pixels: pixels);
        }),
    },
  );

  /// The straight pixels of [row] laid on the engine.
  Uint8List laid(EngineRow row) {
    final ledger = EngineTileLedger(appGpuEngine);
    addTearDown(ledger.pool.free);
    final tiles = ledger.held((hold) {
      final plan = GpuPlan(appGpuEngine);
      addTearDown(plan.free);
      planCompositeTree(
        plan,
        [CompositeLeaf<EngineRow>(row)],
        hold: hold,
        paper: canvas.canvasRect,
        letters: letters,
      );
      final out = composite.run(
        ledger.pool,
        plan,
        const [(0, 0), (1, 0)],
        (0, 0, canvas.width, canvas.height),
      );
      addTearDown(out.free);
      return out.read();
    });
    return tiles;
  }

  /// How many chains the plan of [row] runs: the index the next would take.
  int chainsOf(EngineRow row) {
    final ledger = EngineTileLedger(appGpuEngine);
    addTearDown(ledger.pool.free);
    return ledger.held((hold) {
      final plan = GpuPlan(appGpuEngine);
      addTearDown(plan.free);
      planCompositeTree(
        plan,
        [CompositeLeaf<EngineRow>(row)],
        hold: hold,
        paper: canvas.canvasRect,
        letters: letters,
      );
      return plan.chain(0, 0, 1, 1);
    });
  }

  /// [cel] through [effects] as a route lays a cel's row
  /// ([CutFrameCompositeLayer]).
  EngineTiles rowOf(BitmapSurface cel, List<ResolvedLayerEffect> effects) {
    final layer = CutFrameCompositeLayer(
      surface: cel,
      opacity: 1,
      effects: effects,
    );
    return EngineTiles(
      lineage: layer,
      surface: layer.surface,
      effects: layer.effects,
    );
  }

  // The Color Key — Key Colors, or Keep Colors — from its colour's three
  // bytes, its tolerance and its Amount.
  ResolvedLayerEffect colorKey(int operation, List<double> values) {
    final [red, green, blue, tolerance, amount] = values;
    return ResolvedLayerEffect(
      kind: EffectKind.colorKey,
      values: [
        operation.toDouble(),
        (0xFF000000 | red.toInt() << 16 | green.toInt() << 8 | blue.toInt())
            .toDouble(),
        tolerance,
        amount,
      ],
    );
  }

  ResolvedLayerEffect keyOut(List<double> values) => colorKey(0, values);
  ResolvedLayerEffect keep(List<double> values) => colorKey(1, values);

  final runs = <String, List<ResolvedLayerEffect>>{
    'the paper away, exactly': [
      keyOut(const [64, 192, 96, 0, 100]),
    ],
    'white within 40, at 37%': [
      keyOut(const [255, 255, 255, 40, 37]),
    ],
    'the paper away, the closest of it back, then red away': [
      keyOut(const [64, 192, 96, 10, 100]),
      keep(const [64, 192, 96, 4, 60]),
      keyOut(const [200, 40, 10, 20, 100]),
    ],
    'longer than one set of tables, the last giving back half of all': [
      for (var k = 0; k < 32; k += 1)
        keyOut([
          (k * 41 % 256).toDouble(),
          (k * 89 % 256).toDouble(),
          (k * 23 % 256).toDouble(),
          (k % 5 * 12 + 30).toDouble(),
          (30 + k * 3 % 71).toDouble(),
        ]),
      keep(const [128, 128, 128, 255, 50]),
    ],
  };

  final colour = fx(EffectKind.hueSaturation, {
    'hue': 40,
    'saturation': 30,
    'lightness': -10,
  });
  final blur = fx(EffectKind.blur, {'blurriness': 6});

  // 🗣️I-132-Q2: a keep gives back what ITS run took; a colour between ends
  // the run before it, so a keep past one gives back to a run of its own.
  // ↩️Held on the Flutter chain (order_is_free_test) till it went
  // (the-flutter-fx-chain-is-a-second-chain).
  test('a keep past a colour gives back to its own run — nothing, where '
      'that run took nothing', () {
    final cel = celOf(const [0, 1]);
    final away = keyOut(const [64, 192, 96, 10, 100]);
    final back = keep(const [64, 192, 96, 10, 100]);
    expect(
      laid(rowOf(cel, [away, colour, back])),
      laid(rowOf(cel, [away, colour])),
    );
    // ⛔liveness: with nothing between, the keep gives the paper back.
    expect(laid(rowOf(cel, [away, back])), isNot(laid(rowOf(cel, [away]))));
  });

  // No picture of the row is made to key it where its own keys can: the
  // chain's op is that row laid over nothing (kernels/chain).
  test("keys alone, or before a colour, are the row's own — a chain only "
      'where more follows or a hand holds pixels over the row', () {
    final keys = runs.values.last;
    final cel = celOf(const [0]);
    expect(chainsOf(rowOf(cel, keys)), 0);
    expect(chainsOf(rowOf(cel, [...keys, colour])), 0);
    expect(chainsOf(rowOf(cel, [...keys, blur])), 1);
    final row = rowOf(cel, keys);
    final held = celOf(const [1]);
    expect(
      chainsOf(
        EngineTiles(
          lineage: row.lineage,
          surface: row.surface,
          effects: row.effects,
          held: [EngineHeld(lineage: held, tiles: held.tiles)],
        ),
      ),
      1,
    );
  });

  for (final MapEntry(key: name, value: keys) in runs.entries) {
    // The row's own keys, its colour after them its matrix.
    for (final (after, rest) in [
      ('alone', <ResolvedLayerEffect>[]),
      ('and a colour after', [colour]),
      ('and a blur after', [blur]),
    ]) {
      test('$name, $after: laid as each pixel is keyed', () {
        final cel = celOf(const [0, 1]);
        final reference = laid(rowOf(keyedByDefinition(cel, keys), rest));
        final engine = laid(rowOf(cel, [...keys, ...rest]));
        expect(engine, reference);
        // ⛔liveness: the keys took some of what the row lays.
        expect(laid(rowOf(cel, rest)), isNot(reference));
      });
    }

    // A plug-in after the keys reads the row as they keyed it: what it
    // hands back unchanged is what the row keyed by the definition lays.
    test('$name, and a plug-in after: the plug-in reads the row as each '
        'pixel is keyed', () async {
      final cel = celOf(const [0]);
      final plugin = ShiftingFxPlugin(by: 0);
      final through = ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: shiftingFxPluginDescription,
        values: const [],
        run: fxPluginRunOf(plugin),
      );
      final engine = await aRowLaidOnTheEngine(
        composite,
        letters,
        cel,
        [...keys, through],
      );
      expect(plugin.renders, 1, reason: '⛔fixture: the plug-in ran');
      final reference = await aRowLaidOnTheEngine(
        composite,
        letters,
        keyedByDefinition(cel, keys),
        const [],
      );
      expect(engine, reference);
      expect(
        await aRowLaidOnTheEngine(composite, letters, cel, const []),
        isNot(reference),
        reason: '⛔liveness: the keys took some of what the row lays',
      );
    });

    // What a hand holds over the row is keyed with it, as it is once it
    // lands: laid over the row's own tiles before its chain.
    test('$name, under what a hand holds: laid as each pixel is keyed', () {
      final cel = celOf(const [0]);
      final held = celOf(const [1]);
      final row = rowOf(cel, keys);
      final engine = laid(
        EngineTiles(
          lineage: row.lineage,
          surface: row.surface,
          effects: row.effects,
          held: [EngineHeld(lineage: held, tiles: held.tiles)],
        ),
      );
      final both = keyedByDefinition(celOf(const [0, 1]), keys);
      expect(engine, laid(EngineTiles(lineage: both, surface: both)));
      expect(
        laid(EngineTiles(lineage: both, surface: celOf(const [0, 1]))),
        isNot(engine),
        reason: '⛔liveness: the keys took some of what is held',
      );
    });
  }
}
