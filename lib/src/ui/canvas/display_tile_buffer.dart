import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';

/// 🚨★★★ (v) 2단계 마무리 — THE DISPLAY BUFFER IS TILED, AND A STROKE STEP
/// ONLY PAYS FOR THE TILES IT TOUCHED.
///
/// The single buffer that came before this rasterised the whole visible rect
/// every paint. That is already far cheaper than re-walking the layer tree,
/// but it is a FIXED cost: a two-pixel dab and a full-canvas fill paid the
/// same. Tiling turns it into a cost proportional to what actually changed
/// (유저 2026-08-15: 「1500컷이나 500개레이어같은 무거운상황도 생각하면서
/// 가볍게 하고싶다니까?」).
///
/// ★**Padding is what makes tiles legal here.** The whole point of the
/// buffer is that the display resamples ONCE, and a resample samples
/// NEIGHBOURS: at any non-integer scale a bilinear tap near a tile's edge
/// reaches for pixels that live in the next tile. Rasterise tiles edge to
/// edge and those taps find transparent black instead, which draws a seam
/// down every tile boundary. So each tile is rasterised [padding] pixels
/// larger on every side, holding the true neighbouring content, and drawn
/// from an inset source rect — the filter finds real pixels exactly where
/// it reaches.
///
/// 📐**Tile size is a dial, and it is the one to turn first.** A dirty tile
/// costs its own area times the layers crossing it, so the gap between this
/// and a native surface that could repaint the exact dab rect is an AREA
/// ratio. Smaller tiles close most of it: 64px with 2px padding carries 13%
/// overhead and quantises to a quarter of what 256px does. ⛔That is the
/// knob to turn before concluding anything about a native surface
/// ([[editing-canvas-composite-cache-program]] keeps that candidate open).
class DisplayTileBuffer {
  DisplayTileBuffer({this.tileSize = 128, this.padding = 2})
    : assert(tileSize > 0),
      assert(padding >= 0);

  /// Canvas-space edge length of one tile.
  final double tileSize;

  /// How much true neighbouring content each tile carries outside its own
  /// bounds, so a filtered tap at the edge lands on real pixels.
  final double padding;

  final Map<int, ui.Image> _tiles = {};
  Object? _key;

  /// Drops every tile.
  void invalidate() {
    _dropTiles();
    _lastCommitted = null;
    _lastOverlay = null;
    _key = null;
  }

  /// Keeps the tiles only while [key] is unchanged — the same contract the
  /// static bake has, and for the same reason: anything left out of the key
  /// is a tile that goes stale silently.
  void keepFor(Object key) {
    if (_key == key) {
      return;
    }
    invalidate();
    _key = key;
  }

  /// Drops the tiles that [canvasRegion] touches, in canvas space.
  ///
  /// This is the stroke's half of the invalidation. It is deliberately a
  /// REGION rather than a set of tile coordinates: the caller knows what
  /// changed in canvas pixels, and letting it do the arithmetic here is how
  /// the two stay in step when the tile size is tuned.
  void invalidateRegion(Rect canvasRegion) {
    if (canvasRegion.isEmpty) {
      return;
    }
    // The PADDED extent is what a tile holds, so a change just outside a
    // tile still invalidates it — its margin is showing that content.
    final grown = canvasRegion.inflate(padding);
    final fromX = (grown.left / tileSize).floor();
    final toX = (grown.right / tileSize).ceil();
    final fromY = (grown.top / tileSize).floor();
    final toY = (grown.bottom / tileSize).ceil();
    _tiles.removeWhere((packed, image) {
      final tx = _unpackX(packed);
      final ty = _unpackY(packed);
      final hit = tx >= fromX && tx < toX && ty >= fromY && ty < toY;
      if (hit) {
        image.dispose();
      }
      return hit;
    });
  }

  /// Draws every tile [bounds] covers, rasterising the ones that are missing.
  ///
  /// [paintContent] paints the whole composite in canvas space; each tile
  /// clips it to its own padded rect. Clipping is what keeps a tile cheap —
  /// the engine rejects the draws that fall outside before they cost
  /// anything.
  void draw(
    Canvas canvas, {
    required Rect bounds,
    required ui.FilterQuality quality,
    required void Function(Canvas into) paintContent,
  }) {
    final fromX = (bounds.left / tileSize).floor();
    final toX = (bounds.right / tileSize).ceil();
    final fromY = (bounds.top / tileSize).floor();
    final toY = (bounds.bottom / tileSize).ceil();
    final side = (tileSize + padding * 2).round();
    if (side <= 0) {
      return;
    }
    final paint = Paint()..filterQuality = quality;
    for (var ty = fromY; ty < toY; ty += 1) {
      for (var tx = fromX; tx < toX; tx += 1) {
        final packed = _pack(tx, ty);
        final rect = Rect.fromLTWH(
          tx * tileSize,
          ty * tileSize,
          tileSize,
          tileSize,
        );
        final padded = rect.inflate(padding);
        var image = _tiles[packed];
        if (image == null) {
          final recorder = ui.PictureRecorder();
          final into = Canvas(recorder);
          into.translate(-padded.left, -padded.top);
          into.clipRect(padded);
          paintContent(into);
          final picture = recorder.endRecording();
          try {
            image = picture.toImageSync(side, side);
          } finally {
            picture.dispose();
          }
          _tiles[packed] = image;
        }
        // ★The source rect is INSET by the padding: the margin exists to be
        // sampled, never to be shown. Drawing the padded image whole would
        // paint each tile's neighbours over the neighbours themselves.
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(padding, padding, tileSize, tileSize),
          rect,
          paint,
        );
      }
    }
  }

  /// Drops the tiles the live surface changed since the last paint, and
  /// remembers the new state.
  ///
  /// 🚨★★★THE CROSS-FRAME STATE LIVES HERE ON PURPOSE. A stroke step
  /// repaints WITHOUT a widget rebuild — that is the whole design of the
  /// stack painter's repaint Listenable — so `build` never sees it and the
  /// comparison cannot live there. The painter is a fresh object every
  /// frame, so it cannot hold it either. This object is owned by the State
  /// and handed to the painter, which makes it the only place a "since last
  /// paint" question can be asked at all.
  ///
  /// [committed] and [overlay] are read on the SURFACE's tile grid, which
  /// is not this buffer's: they are converted to canvas rects and the
  /// region arithmetic does the rest, so the two grids may be tuned apart.
  ///
  /// ⛔[spatiallyStable] false means a change to one surface tile can land
  /// anywhere on the canvas — a posed active layer, or a blur on it or on
  /// any folder enclosing it — and then no tile-local answer is correct.
  /// Everything is dropped. That is a real cost in exactly the documents
  /// that can afford it least, and it is still the only honest answer;
  /// narrowing it means mapping the pose and the spread, not guessing.
  void syncLiveSurface({
    required Map<Object, Object> committed,
    required Set<Object> overlay,
    required double surfaceTileSize,
    required Rect Function(Object coord) rectOf,
    required bool spatiallyStable,
  }) {
    if (!spatiallyStable) {
      _dropTiles();
      _lastCommitted = Map<Object, Object>.of(committed);
      _lastOverlay = Set<Object>.of(overlay);
      return;
    }
    final previousCommitted = _lastCommitted;
    final previousOverlay = _lastOverlay;
    if (previousCommitted != null) {
      for (final entry in committed.entries) {
        if (!identical(previousCommitted[entry.key], entry.value)) {
          invalidateRegion(rectOf(entry.key));
        }
      }
      for (final coord in previousCommitted.keys) {
        if (!committed.containsKey(coord)) {
          invalidateRegion(rectOf(coord));
        }
      }
    }
    if (previousOverlay != null) {
      // Both directions: a tile the overlay ARRIVED on has new pixels, and
      // one it LEFT has to lose them. Only asking about the current set
      // leaves the last frame of a stroke painted after the stroke ends.
      for (final coord in overlay.difference(previousOverlay)) {
        invalidateRegion(rectOf(coord));
      }
      for (final coord in previousOverlay.difference(overlay)) {
        invalidateRegion(rectOf(coord));
      }
      // A tile the overlay is STILL on is being drawn into right now.
      for (final coord in overlay.intersection(previousOverlay)) {
        invalidateRegion(rectOf(coord));
      }
    } else {
      for (final coord in overlay) {
        invalidateRegion(rectOf(coord));
      }
    }
    _lastCommitted = Map<Object, Object>.of(committed);
    _lastOverlay = Set<Object>.of(overlay);
  }

  Map<Object, Object>? _lastCommitted;
  Set<Object>? _lastOverlay;

  void _dropTiles() {
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
  }

  void dispose() => invalidate();

  /// How many tiles are currently held — the seam a cost test reads to say
  /// "the untouched ones were not rasterised again".
  @visibleForTesting
  int get tileCount => _tiles.length;

  // Tile coordinates pack into one int so the map needs no allocation per
  // lookup. ±32767 tiles is 4M canvas pixels a side at 128px tiles.
  static int _pack(int x, int y) => ((x + 32768) << 16) | (y + 32768);
  static int _unpackX(int packed) => (packed >> 16) - 32768;
  static int _unpackY(int packed) => (packed & 0xFFFF) - 32768;
}
