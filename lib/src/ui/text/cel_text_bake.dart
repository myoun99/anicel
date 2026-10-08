import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/canvas_size.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../../services/import/raster_cel_import.dart';
import '../canvas/raster_picture.dart';
import 'cel_text_layout.dart';

/// How a set text is turned into its plate — [bakeCelTextPlate]'s shape.
typedef CelTextBaker =
    Future<Map<TileCoord, BitmapTile>> Function(
      CelTextLayout layout, {
      required CanvasSize canvasSize,
      required int tileSize,
      Map<TileCoord, BitmapTile> previous,
    });

/// Stands in for the ENGINE behind [bakeCelTextPlate] in a test.
///
/// 🚨Not a convenience. Under a widget test's clock the engine's raster
/// never answers, so a test that drives the real app could type a text and
/// never see it shown, let alone land — every road the text tool has would
/// go untravelled. ⚠️IT DOES NOT REPLACE THE ENGINE'S OWN PINS: that the
/// plate is what the engine draws is measured against the engine
/// (`cel_text_bake_test.dart`); what the tool does with a plate is measured
/// through here. Neither can do the other's job
/// (`debugRawRgbaUploader`'s reasoning, one seam over).
@visibleForTesting
CelTextBaker? debugCelTextBaker;

/// [layout]'s text as the PLATE a cel keeps for it (`CelText.plate`): what
/// the engine draws for it at canvas resolution, cut into the cel's tiles.
///
/// 🚨★★★THE ONE PLACE A TEXT'S PIXELS COME FROM (R9-rest, the text tool).
/// Whoever changes what a text says or how it is set asks here FIRST and
/// installs the content and its plate together, so nothing that draws a cel
/// ever meets a text without its pixels — and what the person sees while
/// they type is, tile for tile, what is kept (유저 절대규칙 2026-09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The pixels take the pass an imported picture's take
/// ([rasterizeImageToSurface]: one raster over the tiles covered, read back
/// as straight RGBA, the empty tiles dropped), and are cut at the same
/// pasteboard wall. A text set wholly beyond it has no plate.
///
/// [previous] is the plate this text had before the edit. A tile that came
/// out the same IS that plate's tile, the very object: the laid tiles and
/// their uploaded pictures are remembered by it (`celTileWithPlatesLaid`,
/// the tile image cache), so a letter typed at the end of a line lays and
/// uploads the tiles it changed and no others, and an undo step keeps one
/// copy of the rest.
///
/// ⚠️Throws what the engine throws — a raster it refuses, a readback that
/// comes back empty. The plate asked for was not made; the caller still
/// holds the last one that was.
Future<Map<TileCoord, BitmapTile>> bakeCelTextPlate(
  CelTextLayout layout, {
  required CanvasSize canvasSize,
  required int tileSize,
  Map<TileCoord, BitmapTile> previous = const {},
}) async {
  final standIn = debugCelTextBaker;
  if (standIn != null) {
    return standIn(
      layout,
      canvasSize: canvasSize,
      tileSize: tileSize,
      previous: previous,
    );
  }
  final window = celTextBakeWindow(layout, canvasSize);
  if (window.isEmpty) {
    return const {};
  }
  final recorder = ui.PictureRecorder();
  layout.paint(ui.Canvas(recorder)..translate(-window.left, -window.top));
  // A DEFERRED raster ([rasterPicture]): it is rastered by the pass that
  // draws it, so the bake waits on the engine for the tiles' pixels and not
  // once more for this. It is drawn 1:1 on whole pixels, which copies.
  final set = rasterPicture(
    recorder,
    window.width.round(),
    window.height.round(),
  );
  final BitmapSurface cut;
  try {
    cut = await rasterizeImageToSurface(
      image: set,
      canvas: canvasSize,
      fit: MediaFitMode.none,
      placement: window,
      tileSize: tileSize,
    );
  } finally {
    set.dispose();
  }
  return {
    for (final entry in cut.tiles.entries)
      entry.key: _keptIfUnchanged(previous[entry.key], entry.value),
  };
}

/// The part of the canvas a bake of [layout] rasters: everything the text
/// can draw ([CelTextLayout.inkBounds]) that the pasteboard can keep.
///
/// ⚠️CUT AT THE WALL BEFORE THE RASTER, and not only by the pass that
/// slices it. That pass drops what lies beyond the wall either way, so the
/// tiles come out the same — but a text set large and far off would raster
/// the whole of itself to keep a corner of it, or to keep nothing. Its own
/// function so that a test can ask it: no picture shows the difference.
@visibleForTesting
ui.Rect celTextBakeWindow(CelTextLayout layout, CanvasSize canvasSize) =>
    layout.inkBounds.intersect(canvasSize.pasteboardRect);

/// [before] where it already holds [now]'s pixels, else [now].
BitmapTile _keptIfUnchanged(BitmapTile? before, BitmapTile now) =>
    before != null && before == now ? before : now;
