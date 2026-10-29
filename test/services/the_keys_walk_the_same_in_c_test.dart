import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/services/composite_effect_paint.dart'
    show pixelThroughChain;

import '../helpers/native_engine_path.dart';

/// 🚨★★★A ROW'S COLOUR KEYS WALK ONE WAY, IN C AND IN DART (ABI 49).
///
/// The keys' walk reads tables made from the one definition — a key's
/// `matches`, and what its erasing leaves of an alpha — in C
/// (`qa_key_rgba`) where the engine is loaded and in Dart where it is not.
/// Two walks of one table stay one walk only while something compares
/// them with each other AND with the definition, a pixel at a time
/// (`celSourceEffectAlphaFor`, the eyedropper's door), over every axis a
/// key has: its colour, its tolerance, its Amount, keeping instead of
/// erasing, several in their order — and more than one table holds.
///
/// ⚠️The native route asserts the engine actually LOADED: a path that
/// fails to load runs the Dart walk twice, and two identical routes
/// agreeing measures nothing (`cel_pixel_pass_parity_test`'s lesson).
void main() {
  /// A whole plane of red against green a tile.
  const tileSize = 256;
  final libraryPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// The alphas a key's Amount rounds differently at: 70 at 5% is the
  /// half a double and a float32 part over.
  const alphas = [1, 2, 66, 70, 127, 128, 200, 254, 255];

  /// The definition is asked of one pixel in this many.
  const sampled = 13;

  /// The colours the chains below name, laid where the definition is asked:
  /// a key of no tolerance takes nothing a spread of colours happens to miss.
  const named = [
    [64, 192, 96],
    [200, 40, 10],
    [0, 0, 0],
    [255, 255, 255],
    [128, 128, 128],
  ];

  Uint8List plane(int index, int alpha) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < tileSize * tileSize; i += 1) {
      final colour = i % sampled == 0 && i ~/ sampled < named.length
          ? named[i ~/ sampled]
          : [i % 256, i ~/ 256 % 256, (i * 7 + index * 29) % 256];
      pixels.setAll(i * 4, [...colour, alpha]);
    }
    return pixels;
  }

  /// Every red against every green, a spread of blue, and the [named]
  /// colours — one tile at each of [alphas], and one with no ink at all.
  Map<TileCoord, Uint8List> planes() => {
    for (final (index, alpha) in [...alphas, 0].indexed)
      TileCoord(x: index, y: 0): plane(index, alpha),
  };

  BitmapSurface surfaceOf(Map<TileCoord, Uint8List> bytes) => BitmapSurface(
    canvasSize: CanvasSize(width: tileSize * bytes.length, height: tileSize),
    tileSize: tileSize,
    tiles: {
      for (final MapEntry(key: coord, value: pixels) in bytes.entries)
        coord: BitmapTile(size: tileSize, pixels: pixels),
    },
  );

  // The Color Key after its Key Operation — Key Colors, or Keep Colors
  // (I-132-Q2 — it gives back what the keys before it took) — from its
  // colour's three bytes, its tolerance and its amount.
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

  final chains = <String, List<ResolvedLayerEffect>>{
    'the paper away, exactly': [
      keyOut(const [64, 192, 96, 0, 100]),
    ],
    'the paper away within 10, at 37%': [
      keyOut(const [64, 192, 96, 10, 37]),
    ],
    'the paper away, and 5% of it back': [
      keyOut(const [64, 192, 96, 10, 100]),
      keep(const [64, 192, 96, 10, 5]),
    ],
    'white within 40, at half': [
      keyOut(const [255, 255, 255, 40, 50]),
    ],
    'a chain: the paper, the closest of it back, then red away': [
      keyOut(const [64, 192, 96, 10, 37]),
      keep(const [64, 192, 96, 4, 60]),
      keyOut(const [200, 40, 10, 20, 100]),
    ],
    'longer than one table holds, the last giving back half of all': [
      for (var k = 0; k < 32; k += 1)
        keyOut([
          (k * 41 % 256).toDouble(),
          (k * 89 % 256).toDouble(),
          (k * 23 % 256).toDouble(),
          (k % 5 * 12).toDouble(),
          (30 + k * 3 % 71).toDouble(),
        ]),
      keep(const [128, 128, 128, 255, 50]),
    ],
    'longer than one table holds': [
      for (var k = 0; k < 40; k += 1)
        (k % 5 == 0 ? keep : keyOut)([
          (k * 53 % 256).toDouble(),
          (k * 97 % 256).toDouble(),
          (k * 31 % 256).toDouble(),
          // Keeps wide enough to reach what the keys before them took.
          (k % 7 * 9 + (k % 5 == 0 ? 128 : 0)).toDouble(),
          (20 + k * 2 % 81).toDouble(),
        ]),
    ],
  };

  /// The route the keys take — C or Dart — made sure of.
  void walkIn({required bool native}) {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = !native;
    debugQaEngineLibraryPathOverride = native ? libraryPath : null;
    expect(
      QaNativeEngine.instance,
      native ? isNotNull : isNull,
      reason: 'the native route must really load, or this compares the '
          'Dart walk with itself',
    );
  }

  List<int> bytesOf(BitmapTile tile) =>
      tile.readPixels((_, view) => List<int>.of(view));

  for (final MapEntry(key: name, value: chain) in chains.entries) {
    test('🚨$name: a cel\'s tiles keyed in C are the tiles keyed in Dart, and '
        'every alpha is what the keys leave that pixel one at a time', () {
      if (libraryPath == null) {
        if (nativeEngineRequired) {
          fail(nativeEngineMissingSkipReason);
        }
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      final bytes = planes();
      walkIn(native: false);
      final inDart = celSurfaceAsShown(surfaceOf(bytes), chain);
      walkIn(native: true);
      final inC = celSurfaceAsShown(surfaceOf(bytes), chain);

      var keyed = 0;
      var kept = 0;
      for (final MapEntry(key: coord, value: pixels) in bytes.entries) {
        final dart = bytesOf(inDart.tileAt(coord)!);
        expect(bytesOf(inC.tileAt(coord)!), dart, reason: '$coord');
        for (var o = 0; o < pixels.length; o += 4 * sampled) {
          final alpha = pixelThroughChain(
            chain,
            red: pixels[o],
            green: pixels[o + 1],
            blue: pixels[o + 2],
            alpha: pixels[o + 3],
          ).alpha;
          expect(dart[o + 3], alpha, reason: '$coord, byte $o');
          expect(dart.sublist(o, o + 3), pixels.sublist(o, o + 3));
          // The tile with no ink keeps every pixel whatever the keys say.
          if (pixels[o + 3] != 0) {
            alpha == pixels[o + 3] ? kept += 1 : keyed += 1;
          }
        }
      }
      expect(keyed, greaterThan(0), reason: '⛔liveness: the keys take ink');
      expect(kept, greaterThan(0), reason: '⛔liveness: and leave some');
    });

    test('$name: bytes keyed in place — a region\'s, a live tile\'s — the '
        'same in C and in Dart', () {
      if (libraryPath == null) {
        if (nativeEngineRequired) {
          fail(nativeEngineMissingSkipReason);
        }
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      for (final pixels in planes().values) {
        walkIn(native: false);
        final inDart = Uint8List.fromList(pixels);
        celStraightTileAsShown(inDart, null, chain, tileSize);
        walkIn(native: true);
        final inC = Uint8List.fromList(pixels);
        celStraightTileAsShown(inC, null, chain, tileSize);

        expect(inC, inDart);
      }
    });
  }
}
