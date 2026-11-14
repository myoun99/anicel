import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
import '../core/lru.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_point.dart';
import '../models/cut.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/project_background.dart';
import '../models/tile_coord.dart';
import '../native/engine_tile_ledger.dart';
import 'composite_effect_paint.dart' show pixelThroughChain;
import 'layer_pose_matrix.dart' show canvasToArtwork;
import 'canvas_read_source.dart';
import 'cel_text_laying.dart';
import 'cut_frame_composite_plan.dart';

/// The default blend base when the caller does not thread the project
/// background (R10-⑥: production passes the project's paper; a
/// transparent background blends over its opaque export-fallback color).
///
/// R28 #9: aliases the ONE paper constant rather than repeating a
/// literal — the near-white the user caught was spelled out separately in
/// five files, so they could drift.
const int canvasPaperColor = ProjectBackground.defaultPaperArgb;

/// The straight-alpha RGBA of [surface] at integer canvas coords, or null
/// beyond the PASTEBOARD wall (missing tiles are fully transparent).
/// Off-canvas coordinates are real pixels — the eyedropper picks them
/// like Flash does; floorDiv keeps negative coords on the right tile.
int? surfacePixelRgba(BitmapSurface surface, int x, int y) {
  if (!surface.pasteboard.containsPixel(x: x, y: y)) {
    return null;
  }
  final tileSize = surface.tileSize;
  // 🚀`tileAt`, not `tiles[...]` — `BitmapSurface.tiles` is
  // `Map.unmodifiable(_tiles)`, so the subscript rebuilt the entire tile
  // map, per contributing layer, per POINTER EVENT, and Flutter delivers
  // every queued event: a 200Hz pen bills this a dozen-odd times a frame
  // (유저, R4 #3: 스포이드 커서).
  final tile = surface.tileAt(
    TileCoord(x: floorDiv(x, tileSize), y: floorDiv(y, tileSize)),
  );
  if (tile == null) {
    return 0;
  }
  final index = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
  final pixels = _tilesPicked.resolve(tile, () => _readBack(tile));
  return (pixels[index] << 24) |
      (pixels[index + 1] << 16) |
      (pixels[index + 2] << 8) |
      pixels[index + 3];
}

/// The bytes of the tiles a pick last read back: a read waits for the GPU,
/// [surfacePixelRgba] is asked a dozen times a frame for every layer under
/// the pointer, and a tile's bytes never change — so a pick waits only as
/// the pointer comes onto a tile. By the object: a tile's `==` reads every
/// byte.
///
/// 🔢64 tiles, 4 MiB: a stack of more than that under one pixel reads again
/// at every event (flip lane ⓓ-5, 브러시/렌더링's pick).
final Lru<BitmapTile, Uint8List> _tilesPicked = Lru(
  entryCap: () => 64,
  byIdentity: true,
);

Uint8List _readBack(BitmapTile tile) {
  late final Uint8List bytes;
  EngineTileLedger.instance.readEach(BrushFrameKey.noCel, [tile], (view) {
    bytes = Uint8List.fromList(view);
  });
  return bytes;
}

/// A stack laid up so far, PREMULTIPLIED: its colour and its coverage.
typedef _Stack = ({double r, double g, double b, double coverage});

/// What an ADJUSTMENT row makes of [stack] — everything laid up below it —
/// as the paint routes grade its scope: its chain run over the pixel in
/// the chain's order, as a row's own runs ([pixelThroughChain]), and that
/// crossfaded with the pixel by the row's MIX, as the engine lays it
/// (composite_tree_plan.dart).
/// Null when the row filters nothing this walk can answer (hidden, in a
/// hidden folder, mix 0, nothing laid up to grade).
///
/// ↩️It folded the chain's colour matrices alone, so a key on an adjustment
/// row picked as if it were not there — the row's own chain had been read
/// in its order since the keys became one (I-132 ⑥), the adjustment's not.
///
/// ⚠️ The row's SCOPE is approximated by "everything accumulated so far",
/// which is this sampler's existing flat-path fidelity: it already ignores
/// group buffers and blend modes. An adjustment inside a buffering folder
/// therefore reads as if it applied to the whole stack below.
_Stack? _throughAdjustment(
  _Stack stack, {
  required Layer adjustment,
  required Cut cut,
  required int frameIndex,
}) {
  final mix = adjustment.opacity.clamp(0.0, 1.0).toDouble();
  if (!adjustment.isVisible || mix <= 0 || stack.coverage <= 0) {
    return null;
  }
  if (!resolveFolderChainAt(
    cut: cut,
    layer: adjustment,
    frameIndex: frameIndex,
  ).visible) {
    return null;
  }
  final (:r, :g, :b, :coverage) = stack;
  final graded = pixelThroughChain(
    resolveLayerEffectsAt(
      effects: adjustment.effects,
      frameIndex: frameIndex,
      blocks: adjustment.fxBlocks,
      worn: (owner: adjustment.id, wearer: adjustment.id),
    ),
    red: r / coverage,
    green: g / coverage,
    blue: b / coverage,
    alpha: coverage * 255,
  );
  final gradedCoverage = graded.alpha / 255;
  double mixed(double from, double to) => from + (to - from) * mix;
  return (
    r: mixed(r, graded.red * gradedCoverage),
    g: mixed(g, graded.green * gradedCoverage),
    b: mixed(b, graded.blue * gradedCoverage),
    coverage: mixed(coverage, gradedCoverage),
  );
}

/// The canvas point mapped into [entry]'s ARTWORK space — the inverse of
/// the placement every composite route paints with ([canvasToArtwork], the
/// one inverse). Null when the placement is singular (a zero scale
/// collapses the layer to nothing, so there is no pixel under the pointer).
///
/// R28 #7: posed layers used to be SKIPPED here, which meant any layer
/// carrying a transform — or merely sitting inside a folder that did —
/// contributed nothing and the pick fell through to the paper. That is the
/// "그림이 있는 레이어인데도 뭐든 #EDEDED" report, and it came and went with
/// whether a transform key happened to exist at the time.
CanvasPoint? _artworkPointFor(
  CutFrameCompositeEntry entry,
  CanvasPoint point,
) {
  final placement = entry.placement;
  return placement == null ? point : canvasToArtwork(placement)?.apply(point);
}

/// [entry]'s pixel under [point] as it SHOWS — through its pose, with its
/// cel's letters laid (유저 2026-10-06: 「셀의 그림이랑 정확히 동일」) and
/// its own chain run over it in the chain's order ([pixelThroughChain]):
/// its straight colour, and its alpha byte. Null where it has none.
({double red, double green, double blue, int alpha})? _shownPixelAt(
  CutFrameCompositeEntry entry,
  CanvasPoint point,
  LayerFrameSurfaceResolver surfaceResolver,
) {
  final drawing = surfaceResolver(entry.layer, entry.frame);
  final artworkPoint = _artworkPointFor(entry, point);
  if (drawing == null || artworkPoint == null) {
    return null;
  }
  final rgba = surfacePixelRgba(
    celSurfaceWithTextsLaid(drawing),
    artworkPoint.x.floor(),
    artworkPoint.y.floor(),
  );
  if (rgba == null || rgba == 0) {
    return null;
  }
  return pixelThroughChain(
    entry.effects,
    red: (rgba >> 24) & 0xFF,
    green: (rgba >> 16) & 0xFF,
    blue: (rgba >> 8) & 0xFF,
    alpha: rgba & 0xFF,
  );
}

/// How much of [point] [cutBy] covers, 0…1 — their pixels' alpha laid
/// together: where a row clipped to them shows ([flatClipOf]).
double _coverageAt(
  List<CutFrameCompositeEntry> cutBy,
  CanvasPoint point,
  LayerFrameSurfaceResolver surfaceResolver,
) {
  var covered = 0.0;
  for (final entry in cutBy) {
    final alphaByte = _shownPixelAt(entry, point, surfaceResolver)?.alpha;
    if (alphaByte != null) {
      final alpha = alphaByte / 255.0;
      covered = alpha + covered * (1 - alpha);
    }
  }
  return covered;
}

/// Samples the color at [point] (P5 eyedropper); returns opaque ARGB, or
/// null where the visible picture has nothing to pick.
///
/// [source] picks the reference (R28 #6) — the layers [layersReadBy]
/// answers, the fill's answer too: `display` blends the shared composite
/// visit's entries bottom-up with each entry's effective opacity, with no
/// paper under them (I-163-Q6), `layer` reads [activeLayerId]'s FINISHED
/// pixels alone (its own chain applied; transparent artwork reads as the
/// paper beneath, which is what Photoshop's "current layer" does once there
/// is nothing to pick). Either way a POSED layer samples through the
/// inverse of its pose, so the pick matches what the screen shows.
///
/// Works in every section and on every layer kind by construction: a row
/// with no artwork simply contributes nothing (an SE row read alone picks
/// the canvas color, which is the behaviour the user described).
int? sampleCompositeColor({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
  required CanvasPoint point,
  int paperColor = canvasPaperColor,
  CanvasReadSource source = CanvasReadSource.display,
  LayerId? activeLayerId,
}) {
  final read = layersReadBy(source, activeLayerId);
  // The LAYER STACK accumulates on its own, PREMULTIPLIED, with its own
  // coverage — the paper, for a read that has one, joins once at the end.
  //
  // ★ It used to start at the paper, which made an adjustment row compute
  // `filter(stack over paper)` while every paint route computes
  // `filter(stack) over paper` (the adjustment's saveLayer wraps the scope;
  // the background is drawn outside it). The two agree only where the stack
  // is fully opaque, so a grade over a half-covered cel — or over nothing
  // at all — read a colour no route would ever paint.
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  var coverage = 0.0;

  final entries = resolveCutFrameCompositeEntries(
    cut: cut,
    frameIndex: frameIndex,
  );
  final entryByLayerId = {for (final entry in entries) entry.layer.id: entry};

  // Walked in STACK order so the R6 effects land where they do on screen:
  // a row's own chain filters its pixel before it blends, and an
  // ADJUSTMENT row (which resolves no entry of its own) filters everything
  // accumulated below it.
  //
  // COLOUR only. A blur is a spatial filter — it answers "what colour is
  // at this point" by reading its neighbours, which a one-pixel byte walk
  // cannot do — so a blurred picture samples as its unblurred self. Same
  // class of honest gap as this sampler's blend modes and group buffers,
  // and named here so it is not mistaken for a bug.
  for (final layer in cut.layers) {
    if (layer.kind.filtersBelow) {
      // "Pick from the current layer" is the what-ink-is-this mode: it
      // reads the row as DRAWN and no adjustment applies to it. Any read
      // narrower than everything visible is that: an adjustment is another
      // row, and only the whole picture has it.
      if (read != null) {
        continue;
      }
      // Nothing accumulated = nothing to grade, which is exactly when the
      // composite tree emits no adjustment node either.
      if (_throughAdjustment(
            (r: r, g: g, b: b, coverage: coverage),
            adjustment: layer,
            cut: cut,
            frameIndex: frameIndex,
          )
          case final graded?) {
        (:r, :g, :b, :coverage) = graded;
      }
      continue;
    }
    final entry = entryByLayerId[layer.id];
    if (entry == null) {
      continue;
    }
    if (read != null && !read.contains(entry.layer.id)) {
      continue;
    }
    // ★THE ROW'S OWN CHAIN APPLIES IN BOTH MODES — 유저 2026-08-27:
    // 「레이어의 완성본 픽셀을 스포이드 찍도록 하고싶어. 그러니 fx가 싫으면
    // fx끄고 스포이드 찍도록」. The layer mode used to read the ink AS DRAWN,
    // which meant the dropper could hand back a colour that is nowhere on
    // screen. What separates the two modes is WHOSE pixels are read, not
    // whether they are finished: an ADJUSTMENT row is a different row and
    // still stays out of the layer mode (above).
    //
    // The row's own chain filters its pixel BEFORE its opacity meets the
    // stack — the same order the paint routes use.
    final shown = _shownPixelAt(entry, point, surfaceResolver);
    if (shown == null) {
      continue;
    }
    final (red: sourceR, green: sourceG, blue: sourceB, alpha: alphaByte) =
        shown;
    // A row that clips to the layer below shows where its base is, at the
    // base's strength (I-92) — in the whole picture. The base is another
    // row, so a read of one row reads it as drawn, as with an adjustment.
    final clip = read != null
        ? null
        : flatClipOf(
            cut: cut,
            layer: layer,
            frameIndex: frameIndex,
            entries: entries,
          );
    final cutTo = clip == null
        ? 1.0
        : _coverageAt(clip.cutBy, point, surfaceResolver) * clip.strength;
    final alpha = alphaByte / 255.0 * entry.opacity * cutTo;
    if (alpha <= 0) {
      continue;
    }
    // Premultiplied src-over, coverage tracked alongside.
    r = sourceR * alpha + r * (1 - alpha);
    g = sourceG * alpha + g * (1 - alpha);
    b = sourceB * alpha + b * (1 - alpha);
    coverage = alpha + coverage * (1 - alpha);
  }
  // 🗣️I-163-Q6 (유저 2026-11-05): 「지금 합성에서 종이만 뺀다」 — the visible
  // picture is read as this composite with the paper left out: where nothing
  // is laid up there is no colour to pick, and a part-covered pixel picks
  // its ink's own colour. ⛔The question was the display read's alone
  // (I-163-Q4 · Q5 · Q6): the layer read keeps the paper under it.
  if (read == null) {
    return coverage <= 0
        ? null
        : _opaque(r / coverage, g / coverage, b / coverage);
  }
  // The paper joins LAST, under the graded stack — the order the routes
  // paint in.
  return _opaque(
    r + argbRed(paperColor) * (1 - coverage),
    g + argbGreen(paperColor) * (1 - coverage),
    b + argbBlue(paperColor) * (1 - coverage),
  );
}

/// The opaque ARGB of channels on the byte scale.
int _opaque(double red, double green, double blue) =>
    0xFF000000 |
    (red.round().clamp(0, 255) << 16) |
    (green.round().clamp(0, 255) << 8) |
    blue.round().clamp(0, 255);
