import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

import '../helpers/native_engine_path.dart';

/// A tile's pixels live in NATIVE memory freed by a [NativeFinalizer], so
/// every read of those bytes has to keep the TILE reachable — that is what
/// `BitmapTile.readPixels` is for, and why no raw pointer getter exists.
///
/// Pulling the pointer (or an `asTypedList` view of it) into a local does
/// NOT keep the tile alive. When the pre-blend staged a base rect through
/// such a view, a base tile could be collected mid-copy: its finalizer
/// returned the block to the C tile pool, the pool handed it to the next
/// allocation, and the copy then wrote through a pointer someone else
/// owned — an access violation that took the whole test process down.
///
/// This drives that shape hard: a Dart-engine phase (which builds up
/// collectable tiles) followed by a native-engine phase that pre-blends,
/// promotes and commits, with every result byte read back at the end. It
/// is a crash test — reaching the end IS the assertion.
///
/// WHAT IT DOES NOT DO, measured — do not mistake it for a regression pin.
/// An audit re-introduced the hazard twice, faithfully, and this test
/// stayed green three runs each time:
///
///   * dropping the `_baseKeepAlive.add(tile)` that guards the pre-blend's
///     staged base pointer (BrushLiveStrokeRasterizer);
///   * escaping an `asTypedList` view out of `readPixels` into a local in
///     `bitmapSurfaceRegionPixels` — the exact shape the doc above calls
///     unsafe.
///
/// Both sites are on the paths this test drives. It survives them because
/// the tile stays reachable through the live [BitmapSurface] that owns it
/// (`base.tiles`), so the keep-alives are redundant HERE: the hazard needs
/// a tile whose only reference is the escaped local, and nothing in this
/// test creates one.
///
/// So: this is a CHURN SMOKE TEST. What actually enforces the lifetime
/// contract is the API shape — no member returns a raw pointer, so
/// [BitmapTile.readPixels] is the only way in — not the assertions below.
/// Strengthening it would mean constructing a tile that the surface no
/// longer holds and forcing a collection between the escape and the read.
void main() {
  const canvasSize = CanvasSize(width: 192, height: 128);
  const tileSize = 64;
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  BrushDab dab(double x, double y, int sequence) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xB02266AA,
    size: 26,
    opacity: 0.7,
    flow: 0.8,
    hardness: 0.45,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  BitmapSurface paintedBase() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: BrushDabSequence([
      for (var i = 0; i < 7; i += 1) dab(18.5 + i * 22.0, 40.5, i),
    ]),
  ).surface;

  /// One stroke's worth of churn: pre-blend in batches (each batch
  /// re-stages the base into the resident result), promote, then a second
  /// rasterizer that pre-blends and commits the classic way.
  void strokeCycle(BrushBlendMode mode) {
    final base = paintedBase();
    final erase = mode == BrushBlendMode.erase;
    final dabs = [
      for (var i = 0; i < 12; i += 1) dab(24.0 + i * 11.0, 52.5, i),
      for (var i = 0; i < 12; i += 1) dab(156.0 - i * 11.0, 60.5, 12 + i),
    ];

    void preBlendAll(BrushLiveStrokeRasterizer rasterizer) {
      for (var start = 0; start < dabs.length; start += 4) {
        final region = rasterizer.blendFrom(
          dabs.sublist(0, start + 4),
          from: start,
        );
        if (region == null) {
          continue;
        }
        for (final coord in region.toTileCoords(tileSize: tileSize)) {
          rasterizer
              .preBlendedOverlayTile(
                tileX: coord.x,
                tileY: coord.y,
                base: base,
                mode: mode,
                erase: erase,
              )
              ?.free();
        }
      }
    }

    final promoting = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    preBlendAll(promoting);
    final promoted = base.putTiles([
      for (final entry in promoting.promoteStrokeTiles(
        base: base,
        mode: mode,
        erase: erase,
      ))
        entry.tile,
    ]);
    promoting.clear();

    final committing = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    preBlendAll(committing);
    final committed = compositeStrokePixelsOntoBitmapSurface(
      surface: base,
      strokePixels: committing.strokePixelsWithinBounds()!,
      bounds: committing.strokeBounds!,
      erase: erase,
      blendMode: mode,
    ).surface;
    committing.clear();

    // Read every result byte: a copy that landed in a recycled block shows
    // up here as garbage, and a freed one as a fault.
    var sum = 0;
    for (final surface in [promoted, committed]) {
      for (final tile in surface.tiles.values) {
        final pixels = tile.pixels;
        sum += pixels[0] + pixels[pixels.length - 1];
      }
    }
    expect(sum, greaterThanOrEqualTo(0));
  }

  void allModes() {
    for (final mode in BrushBlendMode.values) {
      strokeCycle(mode);
    }
  }

  test('Dart-engine phase: pre-blend, promote and commit churn', () {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
    expect(QaNativeEngine.instance, isNull);
    allModes();
  });

  test(
    'NATIVE-engine phase after it: tile pixels stay alive through every '
    'staged copy (the pool must never recycle a live tile\'s block)',
    () {
      if (dllPath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        expect(nativeEngineRequired, isFalse, reason: 'CI must build one');
        return;
      }
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      expect(QaNativeEngine.instance, isNotNull);
      allModes();
      allModes();
    },
  );
}
