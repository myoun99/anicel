import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_layer_flat_projection.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// ⓔ 4단계 — THE FLAT ACTIVE IMAGE IS THE TILE WALK, BYTE FOR BYTE.
///
/// The projection assembles finished per-coordinate images; the painter
/// walks the same images. The oracle is therefore the REAL painter
/// rendered over the same world rect — two paths, one truth, compared at
/// the byte level. ⛔Uniform content cannot anchor a pixel test (the
/// bake-extent lesson): every committed tile here carries its own
/// distinct ink, and one tile hangs off the canvas onto the pasteboard.
void main() {
  const canvasSize = CanvasSize(width: 24, height: 8);
  final cache = BitmapTileImageCache.instance;

  BitmapTile inked(TileCoord coord, int color, {int at = 2}) {
    var tile = BitmapTile.blank(coord: coord, size: 8);
    final rgba = RgbaColor(
      r: (color >> 16) & 0xFF,
      g: (color >> 8) & 0xFF,
      b: color & 0xFF,
      a: 255,
    );
    tile = writeRgbaColorToBitmapTile(tile: tile, x: at, y: 3, color: rgba);
    return writeRgbaColorToBitmapTile(tile: tile, x: at + 2, y: 5, color: rgba);
  }

  /// Three on-canvas tiles plus one hanging off the LEFT edge onto the
  /// pasteboard — parked ink the flat must carry (canvas-rect extents
  /// drop it, which is the risk the world rect exists to close).
  BitmapSurface committedSurface() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: 8,
    tiles: {
      TileCoord(x: -1, y: 0): inked(TileCoord(x: -1, y: 0), 0xFF8800FF),
      TileCoord(x: 0, y: 0): inked(TileCoord(x: 0, y: 0), 0xFFFF0000),
      TileCoord(x: 1, y: 0): inked(TileCoord(x: 1, y: 0), 0xFF00AA00),
      TileCoord(x: 2, y: 0): inked(TileCoord(x: 2, y: 0), 0xFF0000FF),
    },
  );

  Future<void> decodeAll(BitmapSurface surface) async {
    for (final tile in surface.tiles.values) {
      cache.ensureDecoded(tile);
    }
    while (surface.tiles.values.any((tile) => cache.imageFor(tile) == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  BrushDab dabAt(double x, {int sequence = 0, bool erase = false}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    erase: erase,
  );

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  /// The oracle: the REAL painter, rendered over [worldRect].
  Future<Uint8List> walkBytes(
    BitmapSurface surface,
    ActiveStrokeOverlayModel? overlay,
    ui.Rect worldRect,
  ) async {
    final painter = BitmapSurfacePainter(
      surface: surface,
      overlayModel: overlay,
      showTransparentBackground: false,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(-worldRect.left, -worldRect.top);
    canvas.clipRect(worldRect);
    painter.paintContentInto(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      worldRect.width.round(),
      worldRect.height.round(),
    );
    picture.dispose();
    final bytes = await bytesOf(image);
    image.dispose();
    return bytes;
  }

  test('committed-only: the flat equals the walk, pasteboard ink included',
      () async {
    final surface = committedSurface();
    await decodeAll(surface);

    final flat = ActiveLayerFlatProjection.buildOrNull(
      surface: surface,
      tileImages: cache,
    );
    expect(flat, isNotNull);
    expect(
      flat!.worldRect,
      const ui.Rect.fromLTRB(-8, 0, 24, 8),
      reason: 'the ink bounds reach one tile onto the pasteboard — a '
          'canvas-rect flat would drop the parked ink',
    );
    expect(await bytesOf(flat.image), await walkBytes(surface, null, flat.worldRect));
    flat.image.dispose();
  });

  test('mid-stroke: a colour stroke flattens to the walk\'s bytes — '
      'assembly, never re-blending', () async {
    final surface = committedSurface();
    await decodeAll(surface);
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    overlay.preBlendBase = surface;
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);

    rasterizer.blendFrom([dabAt(2)], from: 0);
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
    );
    await overlay.waitForPendingDecodes();
    rasterizer.blendFrom([dabAt(2), dabAt(12, sequence: 1)], from: 1);
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 10, y: 2, width: 5, height: 5),
    );
    await overlay.waitForPendingDecodes();

    final flat = ActiveLayerFlatProjection.buildOrNull(
      surface: surface,
      tileImages: cache,
      overlay: overlay,
    );
    expect(flat, isNotNull);
    expect(
      await bytesOf(flat!.image),
      await walkBytes(surface, overlay, flat.worldRect),
    );
    flat.image.dispose();
  });

  test('an ERASE stroke patches as replacement — the hole lands, and '
      'yesterday\'s ink dies under it', () async {
    final surface = committedSurface();
    await decodeAll(surface);

    final before = ActiveLayerFlatProjection.buildOrNull(
      surface: surface,
      tileImages: cache,
    )!;

    // ⚠️Erase is a STROKE property (the overlay model's field), not just
    // a dab flag — leaving it false silently paints instead of erasing,
    // and this file's first erase fixture did exactly that (the src →
    // srcOver mutation stayed green because nothing ever vanished).
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    overlay.preBlendBase = surface;
    overlay.erase = true;
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    // Centered ON tile 1's committed dot at (10, 3).
    rasterizer.blendFrom(
      [
        BrushDab(
          center: CanvasPoint(x: 10, y: 3),
          color: 0xFF000000,
          size: 3,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
          erase: true,
        ),
      ],
      from: 0,
    );
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 8, y: 1, width: 5, height: 5),
    );
    await overlay.waitForPendingDecodes();

    final patched = ActiveLayerFlatProjection.patchOrNull(
      previous: before,
      changedCoords: {TileCoord(x: 1, y: 0)},
      surface: surface,
      tileImages: cache,
      overlay: overlay,
    );
    expect(patched, isNotNull);
    final patchedBytes = await bytesOf(patched!.image);

    // Non-vacuity anchor FIRST: the dot really vanished. Without this,
    // an erase that silently paints keeps every parity equality green.
    final localX = (10 - patched.worldRect.left).round();
    final localY = (3 - patched.worldRect.top).round();
    final alphaAt =
        ((localY * patched.worldRect.width.round()) + localX) * 4 + 3;
    expect(
      patchedBytes[alphaAt],
      0,
      reason: 'the committed dot under the eraser is GONE in the flat — '
          'only BlendMode.src can land that hole over previous ink',
    );
    expect(
      patchedBytes,
      await walkBytes(surface, overlay, patched.worldRect),
    );
    before.image.dispose();
    patched.image.dispose();
  });

  test('the patch equals the full build equals the walk — and a removed '
      'coordinate is CLEARED, not remembered', () async {
    final surface = committedSurface();
    await decodeAll(surface);
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    overlay.preBlendBase = surface;
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);

    rasterizer.blendFrom([dabAt(2)], from: 0);
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
    );
    await overlay.waitForPendingDecodes();
    final first = ActiveLayerFlatProjection.buildOrNull(
      surface: surface,
      tileImages: cache,
      overlay: overlay,
    )!;

    // Step: the second dab touches only tile 2.
    rasterizer.blendFrom([dabAt(2), dabAt(21, sequence: 1)], from: 1);
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 19, y: 2, width: 5, height: 5),
    );
    await overlay.waitForPendingDecodes();

    final patched = ActiveLayerFlatProjection.patchOrNull(
      previous: first,
      changedCoords: {TileCoord(x: 2, y: 0)},
      surface: surface,
      tileImages: cache,
      overlay: overlay,
    );
    final rebuilt = ActiveLayerFlatProjection.buildOrNull(
      surface: surface,
      tileImages: cache,
      overlay: overlay,
    )!;
    expect(patched, isNotNull);
    expect(patched!.worldRect, rebuilt.worldRect);
    final patchedBytes = await bytesOf(patched.image);
    expect(patchedBytes, await bytesOf(rebuilt.image));
    expect(
      patchedBytes,
      await walkBytes(surface, overlay, patched.worldRect),
    );

    // A coordinate whose tile is GONE (undo) must clear in the patch.
    // ⚠️Patched from the LATEST flat — a patch always rides the current
    // generation; riding an older one leaves every later step stale
    // (this test's own first red was exactly that sequencing).
    final shrunk = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: Map.of(surface.tiles)..remove(TileCoord(x: -1, y: 0)),
    );
    final cleared = ActiveLayerFlatProjection.patchOrNull(
      previous: patched,
      changedCoords: {TileCoord(x: -1, y: 0)},
      surface: shrunk,
      tileImages: cache,
      overlay: overlay,
    );
    expect(cleared, isNotNull);
    expect(
      await bytesOf(cleared!.image),
      await walkBytes(shrunk, overlay, cleared.worldRect),
      reason: 'yesterday\'s pasteboard ink must not survive in the flat',
    );
    first.image.dispose();
    patched.image.dispose();
    rebuilt.image.dispose();
    cleared.image.dispose();
  });

  test('null is the answer whenever the strict subset breaks', () async {
    final surface = committedSurface();
    await decodeAll(surface);

    // (a) A committed tile without its truth image: a fresh tile object
    // the shared cache has never decoded.
    final cold = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        ...surface.tiles,
        TileCoord(x: 2, y: 1): BitmapTile.blank(
          coord: TileCoord(x: 2, y: 1),
          size: 8,
        ),
      },
    );
    expect(
      ActiveLayerFlatProjection.buildOrNull(surface: cold, tileImages: cache),
      isNull,
      reason: 'flattening around a missing truth bakes a hole in '
          'permanently — refusing is the coverage-never-trades invariant',
    );

    // (b) Mismatched overlay grid.
    final mismatched = ActiveStrokeOverlayModel(tileSize: 4);
    addTearDown(mismatched.dispose);
    mismatched.preBlendBase = surface;
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    rasterizer.blendFrom([dabAt(2)], from: 0);
    mismatched.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
    );
    await mismatched.waitForPendingDecodes();
    expect(
      ActiveLayerFlatProjection.buildOrNull(
        surface: surface,
        tileImages: cache,
        overlay: mismatched,
      ),
      isNull,
    );

    // (c) Settling: the arbitration is per-coordinate out there, which a
    // single image cannot express.
    final settling = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(settling.dispose);
    settling.preBlendBase = surface;
    final rasterizer2 = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    rasterizer2.blendFrom([dabAt(2)], from: 0);
    settling.updateRegion(
      source: rasterizer2,
      region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
    );
    await settling.waitForPendingDecodes();
    settling.settling = true;
    expect(
      ActiveLayerFlatProjection.buildOrNull(
        surface: surface,
        tileImages: cache,
        overlay: settling,
      ),
      isNull,
    );
  });
}
