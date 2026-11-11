import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';

import '../helpers/a_plugin_that_shifts.dart';

void main() {
  const canvas = CanvasSize(width: 256, height: 128);
  final origin = TileCoord(x: 0, y: 0);
  final neighbour = TileCoord(x: 1, y: 0);

  PlacedTile tileWith(TileCoord coord, Map<(int, int), List<int>> pixels) {
    final bytes = Uint8List(128 * 128 * 4);
    for (final entry in pixels.entries) {
      final offset = ((entry.key.$2 * 128) + entry.key.$1) * 4;
      bytes.setRange(offset, offset + 4, entry.value);
    }
    return (coord: coord, tile: BitmapTile(size: 128, pixels: bytes));
  }

  BitmapSurface surfaceOf(Iterable<PlacedTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tileSize: 128,
    tiles: {for (final t in tiles) t.coord: t.tile},
  );

  List<int> pixelAt(BitmapSurface surface, TileCoord coord, int x, int y) {
    final tile = surface.tileAt(coord)!;
    final offset = ((y * 128) + x) * 4;
    return tile.readPixels(
      (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
    );
  }

  // The Color Key: Key Colors, or Keep Colors with [keep] (I-132-Q2).
  ResolvedLayerEffect key({
    bool keep = false,
    int red = 0,
    int green = 0,
    int blue = 0,
    double tolerance = 0,
    double amount = 100,
  }) => ResolvedLayerEffect(
    kind: EffectKind.colorKey,
    values: [
      if (keep) 1 else 0,
      (0xFF000000 | red << 16 | green << 8 | blue).toDouble(),
      tolerance,
      amount,
    ],
  );

  group('CelColorKey', () {
    test('tolerance is the largest single-channel gap, not the distance', () {
      final erase = CelColorKey.fromResolved(
        key(red: 100, green: 100, blue: 100, tolerance: 10),
      )!;
      // Every channel 10 away: Chebyshev says 10, inside. A Euclidean
      // metric would call this 17.3 and let the pixel through — that
      // difference is the whole reason this test names the metric.
      expect(erase.matches(110, 110, 110), isTrue);
      expect(erase.matches(90, 90, 90), isTrue);
      // One channel 11 away is out, however close the other two are.
      expect(erase.matches(100, 100, 111), isFalse);
    });

    test('keep gives back what its run took, by the same comparison', () {
      final erase = CelColorKey.fromResolved(key(red: 255))!;
      final keep = CelColorKey.fromResolved(key(keep: true, red: 255))!;
      expect(erase.alphaFor(255, 0, 0, 200, original: 200), 0);
      expect(erase.alphaFor(0, 0, 0, 200, original: 200), 200);
      // 🚨I-132-Q2 (유저 2026-10-27 「하나로 + AE 뜻」): a keep gives back,
      // and erases nothing — ↩️it erased every pixel its colour did not
      // name.
      expect(keep.alphaFor(255, 0, 0, 0, original: 200), 200);
      expect(keep.alphaFor(0, 0, 0, 0, original: 200), 0);
      expect(keep.alphaFor(0, 0, 0, 200, original: 200), 200);
      // Nothing taken before it: nothing to give back.
      expect(keep.alphaFor(255, 0, 0, 200, original: 200), 200);
    });

    test('Amount folds into the one pass instead of a second draw', () {
      final half = CelColorKey.fromResolved(key(amount: 50))!;
      // 🚨A two-pass mix would ACCUMULATE alpha here (the rule 6 bug):
      // 200 over 200 at half strength comes back ABOVE 200, not below it.
      expect(half.alphaFor(0, 0, 0, 200, original: 200), 100);
      expect(half.alphaFor(0, 0, 0, 255, original: 255), 128);
      // A keep at half gives back half of what was taken.
      final halfBack = CelColorKey.fromResolved(key(keep: true, amount: 50))!;
      expect(halfBack.alphaFor(0, 0, 0, 0, original: 200), 100);
      expect(halfBack.alphaFor(0, 0, 0, 100, original: 200), 150);
    });

    test('an already-empty pixel is never woken up', () {
      final keep = CelColorKey.fromResolved(key(keep: true, red: 255))!;
      // Color bytes under a zero alpha are arbitrary; a keep must not read
      // them as ink and hand back an alpha.
      expect(keep.alphaFor(255, 0, 0, 0, original: 0), 0);
    });

    test('Amount 0 is the no-op an added effect must be', () {
      final fresh = LayerEffect.defaults(
        id: const EffectId('fx'),
        kind: EffectKind.colorKey,
      );
      final resolved = resolveLayerEffectsAt(
        effects: [fresh],
        frameIndex: 0,
        blocks: null,
        worn: null,
      );
      expect(
        resolved,
        isEmpty,
        reason: 'adding a color key must not erase the line art on sight',
      );
    });
  });

  /// [surface] through [keys] as a plugin after them reads it.
  BitmapSurface keyedFor(
    BitmapSurface surface,
    List<ResolvedLayerEffect> keys,
  ) => celSurfaceWithSourceEffects(surface, [...keys, aPluginThatFails]);

  test('keys alone hand back the very surface: the engine keys it', () {
    final surface = surfaceOf([
      tileWith(origin, {
        (0, 0): [255, 255, 255, 255],
      }),
    ]);
    final white = key(red: 255, green: 255, blue: 255);
    expect(identical(celSurfaceWithSourceEffects(surface, [white]), surface),
        isTrue);
    expect(identical(keyedFor(surface, [white]), surface), isFalse,
        reason: '⛔fixture: a plugin after the key reads it keyed');
  });

  group('the keys a plugin after them reads', () {
    test('erases the key color and leaves every other pixel alone', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255], // paper white — keyed out
          (1, 0): [10, 20, 30, 255], // line art — stays
        }),
      ]);
      final keyed = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
      ]);
      expect(pixelAt(keyed, origin, 0, 0)[3], 0);
      expect(pixelAt(keyed, origin, 1, 0), [10, 20, 30, 255]);
    });

    test('RGB survives the pass — only alpha moves', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
        }),
      ]);
      final keyed = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
      ]);
      // ★The destructive verb's undo recipe depends on this: an RGB
      // comparison re-selects exactly the same pixels after the pass.
      expect(pixelAt(keyed, origin, 0, 0).sublist(0, 3), [255, 255, 255]);
    });

    test('an untouched tile keeps its identity, so its image stays decoded',
        () {
      final untouched = tileWith(neighbour, {
        (0, 0): [10, 20, 30, 255],
      });
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
        }),
        untouched,
      ]);
      final keyed = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
      ]);
      expect(identical(keyed.tileAt(neighbour), untouched.tile), isTrue);
      expect(identical(keyed.tileAt(origin), surface.tileAt(origin)), isFalse);
    });

    test('a chain with nothing to do hands back the very same surface', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 20, 30, 255],
        }),
      ]);
      expect(identical(keyedFor(surface, const []), surface), isTrue);
      expect(
        identical(
          keyedFor(surface, [
            key(amount: 0),
          ]),
          surface,
        ),
        isTrue,
        reason: 'Amount 0 must cost nothing, not a rebuilt surface',
      );
    });

    test('the same values twice answer from the cache', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
        }),
      ]);
      final effects = [
        key(red: 255, green: 255, blue: 255),
      ];
      final first = keyedFor(surface, effects);
      final second = keyedFor(surface, effects);
      expect(identical(first, second), isTrue);
    });

    test('a tile under the same values twice answers from its memo — by the '
        'values, not the list they come in', () {
      final keyedTile = tileWith(origin, {
        (0, 0): [255, 255, 255, 255],
      });
      ResolvedLayerEffect white() =>
          key(red: 255, green: 255, blue: 255);
      // Two cels holding the one tile, as a stroke's commits do.
      final first = keyedFor(surfaceOf([keyedTile]), [white()]);
      final second = keyedFor(
        surfaceOf([
          keyedTile,
          tileWith(neighbour, {
            (0, 0): [10, 20, 30, 255],
          }),
        ]),
        [white()],
      );

      expect(identical(first.tileAt(origin), keyedTile.tile), isFalse,
          reason: '⛔fixture: keyed');
      expect(identical(first.tileAt(origin), second.tileAt(origin)), isTrue);
    });

    test('a CHANGED value misses the cache, at the surface grain and at the '
        'tile grain', () {
      // The memo is keyed on identity and VALIDATED by the signature: a
      // revision moves when the drawing changes, and dragging Tolerance
      // changes no drawing. Both grains have to answer the new values.
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
          (1, 0): [250, 250, 250, 255],
        }),
      ]);
      final tight = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
      ]);
      final loose = keyedFor(surface, [
        key(
          red: 255,
          green: 255,
          blue: 255,
          tolerance: 10,
        ),
      ]);

      expect(identical(tight, loose), isFalse, reason: 'the surface memo');
      expect(pixelAt(tight, origin, 1, 0)[3], 255);
      expect(
        pixelAt(loose, origin, 1, 0)[3],
        0,
        reason: 'the TILE memo answered the old tolerance if this is 255',
      );

      // And back again: the first values are recomputed, not stale.
      final again = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
      ]);
      expect(pixelAt(again, origin, 1, 0)[3], 255);
    });

    test('two keys in a chain both run, in order', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
          (1, 0): [255, 0, 0, 255],
          (2, 0): [10, 20, 30, 255],
        }),
      ]);
      final keyed = keyedFor(surface, [
        key(red: 255, green: 255, blue: 255),
        key(red: 255),
      ]);
      expect(pixelAt(keyed, origin, 0, 0)[3], 0);
      expect(pixelAt(keyed, origin, 1, 0)[3], 0);
      expect(pixelAt(keyed, origin, 2, 0)[3], 255);
    });

    test('a keep gives back what the keys before it took — by Amount, and '
        'only of its colour (I-132-Q2)', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 0, 0, 200],
          (1, 0): [255, 255, 255, 255],
        }),
      ]);
      final keyed = keyedFor(surface, [
        // Everything away: tolerance 255 names every colour.
        key(tolerance: 255),
        key(keep: true, red: 255, amount: 50),
      ]);
      expect(pixelAt(keyed, origin, 0, 0), [255, 0, 0, 100]);
      expect(pixelAt(keyed, origin, 1, 0)[3], 0, reason: 'not its colour');
      // ⛔And a keep with nothing taken before it changes nothing.
      expect(
        pixelAt(
          keyedFor(surface, [key(keep: true, red: 255)]),
          origin,
          0,
          0,
        ),
        [255, 0, 0, 200],
      );
    });
  });

  group('the chain the composite can honour', () {
    test('splitSourceEffects keeps each half in its own order', () {
      final effects = [
        key(),
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [4, 0]),
      ];
      final split = splitSourceEffects(effects);
      expect(split.source.single.kind, EffectKind.colorKey);
      expect(split.paint.map((e) => e.kind), [
        EffectKind.colorKey,
        EffectKind.blur,
      ]);
    });

    test('keys alone are both halves, and a plugin after them takes them '
        'out of the paint', () {
      final blur = ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: const [4, 0],
      );
      final plugin = shiftingFxPluginEffect();
      final keys = [key(), key(keep: true)];
      final alone = splitSourceEffects([...keys, blur]);
      expect(alone.source, keys);
      expect(alone.paint, [...keys, blur]);
      final ran = splitSourceEffects([...keys, plugin, blur]);
      expect(ran.source, [...keys, plugin]);
      expect(ran.paint, [blur]);
      // A plugin with no run here keys nothing on the CPU: drawn as if off,
      // after the engine's keys.
      final off = ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: shiftingFxPluginDescription,
        values: const [],
      );
      expect(splitSourceEffects([...keys, off]).paint, [...keys, off]);
      final whole = [...keys, plugin];
      expect(identical(splitSourceEffects(whole).source, whole), isTrue);
      expect(splitSourceEffects(whole).paint, isEmpty);
    });

    test('a chain with no keys is handed straight through', () {
      final effects = [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [4, 0]),
      ];
      expect(identical(splitSourceEffects(effects).paint, effects), isTrue);
    });

    test('the split takes the LEADING run of keys, not every one of them', () {
      // 🚨ORDER IS FREE. A key UNDER a blur means "blur first, then key",
      // and there is no cel byte left to key by then — so only the leading
      // run can be the CPU pass. The rest are shader steps over what the
      // chain has painted so far.
      final blur = ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: const [4, 0],
      );
      final key = ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: const [0, 0xFF000000, 100],
      );
      final split = splitSourceEffects([key, blur, key]);
      expect(split.source.map((e) => e.kind), [EffectKind.colorKey]);
      expect(split.paint.map((e) => e.kind), [
        EffectKind.colorKey,
        EffectKind.blur,
        EffectKind.colorKey,
      ]);
    });

    test('a chain that opens with paint has no CPU half at all', () {
      final blur = ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: const [4, 0],
      );
      final key = ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: const [0, 0xFF000000, 100],
      );
      final split = splitSourceEffects([blur, key]);
      expect(split.source, isEmpty);
      expect(split.paint.map((e) => e.kind), [
        EffectKind.blur,
        EffectKind.colorKey,
      ]);
    });


    test('a row HOLDS the order it was given', () {
      // ⛔This used to assert the opposite — the chain normalized so a key
      // could never sit under a blur. 유저 2026-08-27: 「누가 트랜스폼fx처럼
      // 고정 fx가 아닌것에 순서를 고정하라했지? ae는 순서 자유잖아. …
      // 순서가 결과에 영향주는거고」.
      final blur = LayerEffect.defaults(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
      );
      final colorKey = LayerEffect.defaults(
        id: const EffectId('key'),
        kind: EffectKind.colorKey,
      );
      final row = Layer(
        id: const LayerId('row'),
        name: 'row',
        frames: const [],
        timeline: const {},
        effects: [blur, colorKey],
      );
      expect(row.effects.map((e) => e.kind).toList(), [
        EffectKind.blur,
        EffectKind.colorKey,
      ]);
    });
  });
}
