import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';

void main() {
  const canvas = CanvasSize(width: 512, height: 512);
  final origin = TileCoord(x: 0, y: 0);
  final neighbour = TileCoord(x: 1, y: 0);

  BitmapTile tileWith(TileCoord coord, Map<(int, int), List<int>> pixels) {
    final bytes = Uint8List(256 * 256 * 4);
    for (final entry in pixels.entries) {
      final offset = ((entry.key.$2 * 256) + entry.key.$1) * 4;
      bytes.setRange(offset, offset + 4, entry.value);
    }
    return BitmapTile(coord: coord, size: 256, pixels: bytes);
  }

  BitmapSurface surfaceOf(Iterable<BitmapTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tiles: {for (final tile in tiles) tile.coord: tile},
  );

  List<int> pixelAt(BitmapSurface surface, TileCoord coord, int x, int y) {
    final tile = surface.tileAt(coord)!;
    final offset = ((y * 256) + x) * 4;
    return tile.readPixels(
      (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
    );
  }

  ResolvedLayerEffect key(
    EffectKind kind, {
    int red = 0,
    int green = 0,
    int blue = 0,
    double tolerance = 0,
    double amount = 100,
  }) => ResolvedLayerEffect(
    kind: kind,
    values: [
      red.toDouble(),
      green.toDouble(),
      blue.toDouble(),
      tolerance,
      amount,
    ],
  );

  group('CelColorKey', () {
    test('tolerance is the largest single-channel gap, not the distance', () {
      final erase = CelColorKey.fromResolved(
        key(EffectKind.deleteColor, red: 100, green: 100, blue: 100,
            tolerance: 10),
      )!;
      // Every channel 10 away: Chebyshev says 10, inside. A Euclidean
      // metric would call this 17.3 and let the pixel through — that
      // difference is the whole reason this test names the metric.
      expect(erase.matches(110, 110, 110), isTrue);
      expect(erase.matches(90, 90, 90), isTrue);
      // One channel 11 away is out, however close the other two are.
      expect(erase.matches(100, 100, 111), isFalse);
    });

    test('keep is the same comparison with the answer inverted', () {
      final erase = CelColorKey.fromResolved(
        key(EffectKind.deleteColor, red: 255),
      )!;
      final keep = CelColorKey.fromResolved(
        key(EffectKind.keepColor, red: 255),
      )!;
      expect(erase.alphaFor(255, 0, 0, 200), 0);
      expect(erase.alphaFor(0, 0, 0, 200), 200);
      expect(keep.alphaFor(255, 0, 0, 200), 200);
      expect(keep.alphaFor(0, 0, 0, 200), 0);
    });

    test('Amount folds into the one pass instead of a second draw', () {
      final half = CelColorKey.fromResolved(
        key(EffectKind.deleteColor, amount: 50),
      )!;
      // 🚨A two-pass mix would ACCUMULATE alpha here (the rule 6 bug):
      // 200 over 200 at half strength comes back ABOVE 200, not below it.
      expect(half.alphaFor(0, 0, 0, 200), 100);
      expect(half.alphaFor(0, 0, 0, 255), 128);
    });

    test('an already-empty pixel is never woken up', () {
      final keep = CelColorKey.fromResolved(
        key(EffectKind.keepColor, red: 255),
      )!;
      // Color bytes under a zero alpha are arbitrary; a keep must not read
      // them as ink and hand back an alpha.
      expect(keep.alphaFor(255, 0, 0, 0), 0);
    });

    test('Amount 0 is the no-op an added effect must be', () {
      final fresh = LayerEffect.defaults(
        id: const EffectId('fx'),
        kind: EffectKind.deleteColor,
      );
      final resolved = resolveLayerEffectsAt(effects: [fresh], frameIndex: 0);
      expect(
        resolved,
        isEmpty,
        reason: 'adding a color key must not erase the line art on sight',
      );
    });
  });

  group('celSurfaceWithSourceEffects', () {
    test('erases the key color and leaves every other pixel alone', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255], // paper white — keyed out
          (1, 0): [10, 20, 30, 255], // line art — stays
        }),
      ]);
      final keyed = celSurfaceWithSourceEffects(surface, [
        key(EffectKind.deleteColor, red: 255, green: 255, blue: 255),
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
      final keyed = celSurfaceWithSourceEffects(surface, [
        key(EffectKind.deleteColor, red: 255, green: 255, blue: 255),
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
      final keyed = celSurfaceWithSourceEffects(surface, [
        key(EffectKind.deleteColor, red: 255, green: 255, blue: 255),
      ]);
      expect(identical(keyed.tileAt(neighbour), untouched), isTrue);
      expect(identical(keyed.tileAt(origin), surface.tileAt(origin)), isFalse);
    });

    test('a chain with nothing to do hands back the very same surface', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [10, 20, 30, 255],
        }),
      ]);
      expect(identical(celSurfaceWithSourceEffects(surface, const []), surface),
          isTrue);
      expect(
        identical(
          celSurfaceWithSourceEffects(surface, [
            key(EffectKind.deleteColor, amount: 0),
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
        key(EffectKind.deleteColor, red: 255, green: 255, blue: 255),
      ];
      final first = celSurfaceWithSourceEffects(surface, effects);
      final second = celSurfaceWithSourceEffects(surface, effects);
      expect(identical(first, second), isTrue);
    });

    test('two keys in a chain both run, in order', () {
      final surface = surfaceOf([
        tileWith(origin, {
          (0, 0): [255, 255, 255, 255],
          (1, 0): [255, 0, 0, 255],
          (2, 0): [10, 20, 30, 255],
        }),
      ]);
      final keyed = celSurfaceWithSourceEffects(surface, [
        key(EffectKind.deleteColor, red: 255, green: 255, blue: 255),
        key(EffectKind.deleteColor, red: 255),
      ]);
      expect(pixelAt(keyed, origin, 0, 0)[3], 0);
      expect(pixelAt(keyed, origin, 1, 0)[3], 0);
      expect(pixelAt(keyed, origin, 2, 0)[3], 255);
    });
  });

  group('the chain the composite can honour', () {
    test('splitSourceEffects keeps each half in its own order', () {
      final effects = [
        key(EffectKind.deleteColor),
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [4, 4]),
      ];
      final split = splitSourceEffects(effects);
      expect(split.source.single.kind, EffectKind.deleteColor);
      expect(split.paint.single.kind, EffectKind.blur);
    });

    test('a chain with no keys is handed straight through', () {
      final effects = [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [4, 4]),
      ];
      expect(identical(splitSourceEffects(effects).paint, effects), isTrue);
    });

    test('effectKindsFor hides the keys where there are no cel bytes', () {
      expect(
        effectKindsFor(inputIsCelPixels: true),
        containsAll([EffectKind.deleteColor, EffectKind.keepColor]),
      );
      final onBuffer = effectKindsFor(inputIsCelPixels: false);
      expect(onBuffer, contains(EffectKind.blur));
      expect(onBuffer, isNot(contains(EffectKind.deleteColor)));
      expect(onBuffer, isNot(contains(EffectKind.keepColor)));
    });

    test('a row cannot HOLD a key below a paint effect', () {
      final blur = LayerEffect.defaults(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
      );
      final colorKey = LayerEffect.defaults(
        id: const EffectId('key'),
        kind: EffectKind.deleteColor,
      );
      // Written blur-then-key; the chain normalizes so the lane list and
      // the pixels cannot disagree about what the order means.
      expect(
        normalizedEffectChain([blur, colorKey]).map((e) => e.kind).toList(),
        [EffectKind.deleteColor, EffectKind.blur],
      );
    });

    test('an already-ordered chain is returned unchanged, not rebuilt', () {
      final effects = [
        LayerEffect.defaults(
          id: const EffectId('key'),
          kind: EffectKind.deleteColor,
        ),
        LayerEffect.defaults(id: const EffectId('blur'), kind: EffectKind.blur),
      ];
      expect(identical(normalizedEffectChain(effects), effects), isTrue);
    });
  });
}
