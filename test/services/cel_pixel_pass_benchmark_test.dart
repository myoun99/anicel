@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';

import '../helpers/native_engine_path.dart';

/// The PRE-MEASUREMENT `pixel-pass-native` asks for before a line of C is
/// written (card: 「착수 전에 확인할 것 셋」, ② 언두 레시피가 경계를 넘어야
/// 한다).
///
/// PR 1269 left 73ms on a 1920x1080 whole-picture recolour and named 51ms
/// of it as "the Dart pixel loop". That number is not actionable yet,
/// because the loop does THREE things per pixel and only two of them are
/// obviously native work:
///
///   1. the participation test (`celPixelParticipates`)
///   2. the blend/write into the tile copy
///   3. the undo recipe — BUILT on the forward pass (`_RestoreBuilder`),
///      READ on the undo pass (`CelPixelRestore.readInto`)
///
/// (3) is the design fork. If it is most of the 51ms, sending (1) and (2)
/// to C buys little and the recipe has to cross the boundary too; if it is
/// a sliver, the boundary can stay exactly where it is — native speaks flat
/// bytes, Dart owns the compression — and no compression algorithm gets
/// written twice (⛔사본 금지).
///
/// ⚠️THE SPLIT IS MEASURED WITH THE PRODUCT'S OWN TWO PATHS, not with an
/// instrumented copy of the loop. The forward pass builds a recipe; the
/// undo pass reads one and builds nothing. Same participation, same write,
/// same traversal — so `forward - undo` is (3)'s build cost minus its read
/// cost. A copy of the loop with a stopwatch in it would have measured the
/// copy.
///
/// 📏WHAT IT ANSWERED (2026-09-10): **the fork splits by CONTENT.**
///   * flat line art — recipe build is 3-16% of the forward pass. The
///     boundary can stay where it is.
///   * a cel the recipe cannot compress — 55-71%. There, `_RestoreBuilder`
///     IS the pass, and moving the write to C would buy almost nothing.
/// The card names line art as the case that matters (「a recolour makes the
/// region flat by definition」), so the first row governs — but the second
/// is why this file measures both, and why a shaded cel is not the same
/// question wearing different numbers.
///
/// 🚨READ RATIOS, NOT MILLISECONDS. This machine runs other lanes' gates:
/// the same code measured 23 and 39 ns/px an hour apart, and an early draft
/// of this file "found" a recipe build that cost MINUS 24 ms. Only
/// `undo / forward` inside ONE run compares two things measured under the
/// same load.
///
/// Prints; asserts only that the work happened.
void main() {
  const tileSize = defaultCelTileSize;
  final libraryPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A cel whose every tile is allocated, at one of the recipe's two ends.
  ///
  /// * `noisy: false` — flat opaque black, the line-art shape the card's
  ///   371ms→73ms measurement used, and the one that makes the recipe
  ///   UNIFORM (the case that matters: 「line art is flat black; a recolour
  ///   makes the region flat by definition」).
  /// * `noisy: true` — a different value at almost every pixel, so the
  ///   recipe falls all the way to [RawCelPixelRestore]. ⚠️Both ends are
  ///   measured because they read the recipe through DIFFERENT `readInto`
  ///   implementations, and measuring one of four would have been a claim
  ///   about the other three.
  BitmapSurface celOf(CanvasSize canvas, {required bool noisy}) {
    final columns = (canvas.width + tileSize - 1) ~/ tileSize;
    final rows = (canvas.height + tileSize - 1) ~/ tileSize;
    final tiles = <TileCoord, BitmapTile>{};
    for (var y = 0; y < rows; y += 1) {
      for (var x = 0; x < columns; x += 1) {
        final bytes = Uint8List(tileSize * tileSize * 4);
        var seed = (y * columns + x) * 2654435761 & 0xffffff;
        for (var offset = 0; offset < bytes.length; offset += 4) {
          if (noisy) {
            // A cheap deterministic churn — enough distinct values that
            // the recipe cannot be uniform, a palette or runs.
            seed = (seed * 1103515245 + 12345) & 0xffffff;
            bytes[offset] = seed & 0xff;
            bytes[offset + 1] = (seed >> 8) & 0xff;
            bytes[offset + 2] = (seed >> 16) & 0xff;
          }
          bytes[offset + 3] = 255;
        }
        tiles[TileCoord(x: x, y: y)] = BitmapTile(
          size: tileSize,
          pixels: bytes,
        );
      }
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// Every allocated tile, at full coverage — `mask: null` is the pass's
  /// own "all 255" shortcut, so this is the cheapest possible walk and the
  /// remaining cost is the per-pixel work itself.
  CelPixelWalk wholeCel(BitmapSurface surface) => (visit) {
    for (final coord in surface.tiles.keys) {
      visit(coord, null);
    }
  };

  ({Duration forward, Duration undo, int tiles, String recipe}) timeOnePass(
    CanvasSize canvas,
    CelPixelChannel channel,
    Uint8List value, {
    required bool noisy,
  }) {
    final surface = celOf(canvas, noisy: noisy);

    final forwardWatch = Stopwatch()..start();
    final forward = overwriteCelPixels(
      surface: surface,
      channel: channel,
      walk: wholeCel(surface),
      value: value,
    );
    forwardWatch.stop();

    final restore = forward.restore!;
    final undoWatch = Stopwatch()..start();
    overwriteCelPixels(
      surface: forward.surface,
      channel: channel,
      walk: wholeCel(forward.surface),
      restore: restore,
    );
    undoWatch.stop();

    return (
      forward: forwardWatch.elapsed,
      undo: undoWatch.elapsed,
      tiles: surface.tiles.length,
      recipe: restore.runtimeType.toString(),
    );
  }

  void report(
    String label,
    CanvasSize canvas,
    CelPixelChannel channel, {
    bool noisy = false,
  }) {
    final value = Uint8List.fromList(
      channel == CelPixelChannel.colour ? [10, 120, 220] : [0],
    );
    // One untimed pass first: the JIT has to see this code before the
    // number means anything.
    final warm = timeOnePass(canvas, channel, value, noisy: noisy);

    // ⚠️MIN, NOT MEAN — the first draft averaged three runs and reported a
    // recipe build costing MINUS 24 ms, which is not a thing. Another
    // session's gate was on the machine; the mean was measuring that. The
    // minimum of N is the run that got the least interference, and it is
    // the only summary of a loaded machine worth reading.
    var forwardUs = 1 << 30;
    var undoUs = 1 << 30;
    var tiles = 0;
    const runs = 5;
    for (var run = 0; run < runs; run += 1) {
      final one = timeOnePass(canvas, channel, value, noisy: noisy);
      forwardUs = one.forward.inMicroseconds < forwardUs
          ? one.forward.inMicroseconds
          : forwardUs;
      undoUs = one.undo.inMicroseconds < undoUs
          ? one.undo.inMicroseconds
          : undoUs;
      tiles = one.tiles;
    }
    final forward = forwardUs / 1000;
    final undo = undoUs / 1000;
    final pixels = tiles * tileSize * tileSize;
    // ignore: avoid_print
    print(
      '[pixel-pass] $label  tiles=$tiles  pixels=$pixels  (best of $runs)\n'
      '             recipe = ${warm.recipe}\n'
      '             forward (participate+write+recipe BUILD) = '
      '${forward.toStringAsFixed(1)} ms  '
      '= ${(forwardUs * 1000 / pixels).toStringAsFixed(1)} ns/px\n'
      '             undo    (participate+write+recipe READ)  = '
      '${undo.toStringAsFixed(1)} ms  '
      '= ${(undoUs * 1000 / pixels).toStringAsFixed(1)} ns/px\n'
      '             recipe BUILD minus READ = '
      '${(forward - undo).toStringAsFixed(1)} ms '
      '(${((forward - undo) / forward * 100).toStringAsFixed(0)}% of forward)',
    );
    expect(tiles, greaterThan(0));
  }

  /// Both passes over ONE fixture, in ONE process: the Dart loop and the C
  /// kernel (ABI 34), each proven to be the one that ran.
  ///
  /// 🚨Inside one run, because that is the only comparison this machine can
  /// make honestly (the ratio note above). And the engine is ASSERTED, not
  /// assumed: a first A/B set `QA_ENGINE_PATH` on the command line, read two
  /// near-identical columns, and had nothing to say whether the second one
  /// had loaded anything at all.
  void compare(
    String label,
    CanvasSize canvas,
    CelPixelChannel channel, {
    bool noisy = false,
  }) {
    for (final native in [false, true]) {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = !native;
      debugQaEngineLibraryPathOverride = native ? libraryPath : null;
      if (native && libraryPath == null) {
        // ignore: avoid_print
        print('[pixel-pass] $label  C: no engine binary here — Dart only');
        continue;
      }
      expect(
        QaNativeEngine.instance,
        native ? isNotNull : isNull,
        reason: 'the ${native ? 'C' : 'Dart'} arm must be the one that runs',
      );
      report(
        '$label  [${native ? 'C' : 'Dart'}]',
        canvas,
        channel,
        noisy: noisy,
      );
    }
  }

  test('whole-picture colour pass, by canvas size', () {
    compare('1920x1080 colour', const CanvasSize(width: 1920, height: 1080),
        CelPixelChannel.colour);
    compare('3840x2160 colour', const CanvasSize(width: 3840, height: 2160),
        CelPixelChannel.colour);
  });

  test('whole-picture alpha pass — one byte per pixel instead of three', () {
    // ⚠️Not the same shape halved: the alpha channel's participation rule
    // takes EVERY masked pixel (it must, or undo could not tell an
    // already-empty pixel from one this pass emptied), so it walks the same
    // pixels with a third of the recipe.
    compare('1920x1080 alpha', const CanvasSize(width: 1920, height: 1080),
        CelPixelChannel.alpha);
  });

  test('a cel the recipe cannot compress — the RAW read, not the uniform one',
      () {
    compare('1920x1080 colour NOISY', const CanvasSize(width: 1920, height: 1080),
        CelPixelChannel.colour, noisy: true);
  });
}
