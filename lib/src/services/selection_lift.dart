import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart' show gpuTileSide;

import '../core/rgba_premultiply.dart' show copyRgb;
import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/brush_frame_key.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/dirty_region.dart';
import '../models/tiles_covering.dart';
import '../native/engine_cel_pixels.dart';
import '../native/engine_stamp_masks.dart';
import '../native/engine_tile_ledger.dart';
import 'canvas_selection.dart' show SelectionMaskOptions;
import 'canvas_selection_region.dart';
import 'selection_clip.dart';

/// The bitmap-lift pair (R14-④): an erase mask dab that cuts the
/// selection's pixels out of the layer at their origin, and a stamp dab
/// carrying those exact pixels — the Move tool commits the pair (origin
/// vanishes), then drags the STAMP dab alone. Both ride the ordinary
/// stroke funnel, so undo and .anicel serialization come free, and a
/// zero-move drop is byte-identical to the original by construction
/// (hard-edged mask: full erase + source-over of the same pixels).
class SelectionLiftDabs {
  const SelectionLiftDabs({required this.eraseDab, required this.stampDab});

  final BrushDab eraseDab;
  final BrushDab stampDab;
}

/// Copies the surface's pixels under [clip] — over its box
/// ([SelectionClip.box]) — into a straight-alpha RGBA buffer the box's size,
/// each pixel it covers at all whole where [takeWholePixels], else its
/// alpha scaled by the coverage. `liftedAnything` is false when the
/// selection found nothing. On the engine's grid the kernel gathers under
/// the mask the clip made there ([SelectionClip.maskOnEngine]); the walk
/// below is the reference those are held to, and the grid off the engine.
///
/// ↩️Till 2026-11-14 it was handed the mask's bytes, which the CPU made of
/// the selection at every lift and the engine was handed up again.
///
/// TILE-MAJOR, and the walk order is the whole cost of a lift. Going by
/// destination rows meant asking which tile every single pixel belonged
/// to: a [TileCoord] allocation and a map lookup per pixel of the bbox —
/// 3.9 million of them for a whole-picture lift on the shipping canvas —
/// and behind that map, `surface.tiles[coord]?.pixels`, which is a copy
/// of the cel's ENTIRE tile map followed by a 256 KB defensive copy of
/// the tile. Grabbing a handle to start a transform froze for 263-283 ms
/// on a realistic character cel and about 78% of it was here. Walking the
/// tiles, and the pixels inside them, makes the question free: measured
/// 251.9 ms -> 29.6 ms in canvas, 314.2 -> 49.9 with a pasteboard
/// overhang.
///
/// The result is byte-identical by construction rather than by hope:
/// every destination pixel belongs to exactly one tile, so this writes
/// the same bytes to the same places in a different order, and
/// `liftedAnything` is an OR. Pulled out of [buildSelectionLiftDabs] so a
/// test can hold it against a per-pixel reference across bboxes that
/// straddle tile edges — the axis the rewrite changed and the one the
/// lift's existing tests do not exercise.
({Uint8List rgba, bool liftedAnything}) gatherMaskedSurfacePixels({
  required BitmapSurface surface,
  required SelectionClip clip,
  /// Whether a partially-masked pixel travels ENTIRELY. See the branch it
  /// guards — ⛔required rather than defaulted, because either answer is
  /// wrong for half the callers and a default would pick one silently.
  required bool takeWholePixels,
}) {
  final box = clip.box;
  if (box == null) {
    throw StateError('a selection that selects no pixel takes none');
  }
  final (:left, :top, :width, :height) = box;
  if (surface.tileSize == gpuTileSide && !debugSelectionLiftInDart) {
    return _gatherOnEngine(
      surface: surface,
      clip: clip,
      box: box,
      takeWholePixels: takeWholePixels,
    );
  }
  final mask = clip.maskFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  final rgba = Uint8List(width * height * 4);
  final tileSize = surface.tileSize;
  final rightExclusive = left + width;
  final bottomExclusive = top + height;
  var liftedAnything = false;
  for (final covered in tilesCovering(
    surface,
    DirtyRegion(
      left: left,
      top: top,
      rightExclusive: rightExclusive,
      bottomExclusive: bottomExclusive,
    ),
  )) {
    final tileTop = covered.worldTop;
    final tileLeft = covered.worldLeft;
    final y0 = covered.top;
    final y1 = covered.bottomExclusive;
    final x0 = covered.left;
    final x1 = covered.rightExclusive;
    // `readPixels`, so the tile's bytes are read in place and the view
    // never leaves the callback — that is the lifetime rule, and the
    // `pixels` getter it replaces was the 256 KB copy.
    covered.tile.readPixels((_, pixels) {
        for (var y = y0; y < y1; y += 1) {
          final rowBase = (y - top) * width;
          final sourceRowBase = (y - tileTop) * tileSize;
          for (var x = x0; x < x1; x += 1) {
            final col = x - left;
            final maskValue = mask[rowBase + col];
            if (maskValue == 0) {
              continue;
            }
            final sourceOffset = (sourceRowBase + (x - tileLeft)) * 4;
            final sourceAlpha = pixels[sourceOffset + 3];
            if (sourceAlpha == 0) {
              continue;
            }
            final targetOffset = (rowBase + col) * 4;
            copyRgb(rgba, targetOffset, pixels, sourceOffset);
            // 🚨★★★A MOVE TAKES THE WHOLE PIXEL. The mask says WHICH pixels
            // travel, not how much of each one does.
            //
            // This used to scale alpha by coverage, and the erase removed
            // the matching fraction — arithmetically exact, and it left a
            // ghost of the drawing along the selection's edge every time
            // (유저 2026-08-27: 「aa적용 변형시, 선택의 외부에도 aa의 영향으로
            // 픽셀이 남는데, 그러지 않도록」).
            //
            // ⛔The three cannot all hold at once: leave nothing behind,
            // lose no ink, keep a soft edge on the moved copy. Scaling both
            // sides bought the last two and gave up the first. The user
            // chose to give up the third instead — a move that leaves half
            // of itself behind is not a move — and the softness comes back
            // on the PLACING side, which is carded separately.
            //
            // ⚠️FEATHER IS THE EXCEPTION, and it is not an invented one: a
            // feathered selection is softness the user ASKED for, and the
            // whole point of asking is that the edge fades. Anti-aliasing is
            // incidental — nobody feathers a selection by switching AA on —
            // so that is the one this straightens out.
            if (takeWholePixels) {
              rgba[targetOffset + 3] = sourceAlpha;
            } else {
              // Skia's mul-div-255 rounding, like the overlay pipeline.
              final product = sourceAlpha * maskValue + 128;
              rgba[targetOffset + 3] = (product + (product >> 8)) >> 8;
            }
            liftedAnything = true;
          }
        }
      });
  }
  return (rgba: rgba, liftedAnything: liftedAnything);
}

/// Test seam: the gather in Dart on the app's grid too — the reference
/// `a_selection_lifts_on_the_engine_test.dart` holds the engine's to.
@visibleForTesting
bool debugSelectionLiftInDart = false;

/// The gather on the engine (flip lane ⓒ): the law in the kernel
/// (rust/src/kernels/cel_pixel/lift.wgsl), under the mask [clip] made there
/// over [box] — asked for only where a tile lies under it —, over the tiles
/// where the pool has them, one read back of the box.
({Uint8List rgba, bool liftedAnything}) _gatherOnEngine({
  required BitmapSurface surface,
  required SelectionClip clip,
  required ({int left, int top, int width, int height}) box,
  required bool takeWholePixels,
}) {
  final (:left, :top, :width, :height) = box;
  final rgba = Uint8List(width * height * 4);
  final covered = tilesCovering(
    surface,
    DirtyRegion(
      left: left,
      top: top,
      rightExclusive: left + width,
      bottomExclusive: top + height,
    ),
  ).toList();
  if (covered.isEmpty) {
    return (rgba: rgba, liftedAnything: false);
  }
  final ledger = EngineTileLedger.instance;
  return ledger.held((hold) {
    final grid = hold.gridOf(BrushFrameKey.noCel, {
      for (final one in covered) one.coord: one.tile,
    });
    final liftedAnything = EngineCelPixels.pass.lift(
      ledger.pool,
      grid.x0,
      grid.y0,
      grid.columns,
      grid.rows,
      grid.tiles,
      mask: clip.maskOnEngine(),
      whole: takeWholePixels,
      into: rgba,
    );
    return (rgba: rgba, liftedAnything: liftedAnything);
  });
}

/// What a selection takes off a cel: the selection it read
/// ([SelectionClip.of]) and its box, the straight-alpha pixels under it, and
/// whether a partly-covered pixel travelled whole.
typedef SelectionPixels = ({
  SelectionClip clip,
  ({int left, int top, int width, int height}) box,
  Uint8List rgba,
  bool takeWholePixels,
});

/// The pixels [region] takes off [surface] at [options] — null when its box
/// is empty or nothing under the mask is painted.
///
/// ⛔ONE LIFT. The move's lift and the cut piece (the cut tool, 전체
/// 잘라내기, 픽셀 복사) each read the selection and gathered under it, the
/// piece citing the move's law in a comment — the same steps twice, which is
/// how one marquee comes to take two different sets of pixels.
SelectionPixels? liftSelectionPixels({
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
  required SelectionMaskOptions options,
}) {
  // Pasteboard clip, not canvas — off-canvas artwork is selectable and
  // liftable (the whole point of moving things on and off the stage).
  // R26: grow/feather/AA may write beyond the polygon's bbox — the clip's
  // box is padded for them.
  final clip = SelectionClip.of(
    region,
    wall: surface.pasteboard,
    options: options,
  );
  final box = clip.box;
  if (box == null) {
    return null;
  }

  // 🚨WHOLE PIXELS unless the softness was ASKED for. A feathered selection
  // is a soft edge on purpose; anti-aliasing is not, and splitting a pixel
  // between the moved copy and the old spot is what left a ghost along
  // every AA selection the user moved.
  final takeWholePixels = options.featherPx <= 0;

  // Lift the surface pixels under the mask (straight alpha, byte copies).
  final gathered = gatherMaskedSurfacePixels(
    surface: surface,
    clip: clip,
    takeWholePixels: takeWholePixels,
  );
  if (!gathered.liftedAnything) {
    return null;
  }
  return (
    clip: clip,
    box: box,
    rgba: gathered.rgba,
    takeWholePixels: takeWholePixels,
  );
}

/// The lift pair for [region] over [surface]: the erase that takes what
/// [liftSelectionPixels] took ([selectionEraseDab]), and the stamp carrying
/// it. Null when the selection takes nothing.
SelectionLiftDabs? buildSelectionLiftDabs({
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
  required String liftId,
  SelectionMaskOptions options = SelectionMaskOptions.none,
}) {
  final lifted = liftSelectionPixels(
    region: region,
    surface: surface,
    options: options,
  );
  if (lifted == null) {
    return null;
  }
  final (clip: _, :box, :rgba, takeWholePixels: _) = lifted;
  final (:left, :top, :width, :height) = box;
  final stampDab = BrushDab(
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: 0xFF000000,
    size: math.max(width, height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 1,
    stamp: BrushStampImage(
      id: 'lift-stamp-$liftId',
      width: width,
      height: height,
      rgba: rgba,
    ),
  );
  return SelectionLiftDabs(
    eraseDab: selectionEraseDab(lifted, id: 'lift-erase-$liftId'),
    stampDab: stampDab,
  );
}

/// The erase that takes [lifted] off the cel it was read from.
///
/// ⛔ONE ERASE. The move's lift leaves its spot through it, and a cut that
/// takes what it cuts (I-90) takes it through it — so what a piece took is
/// what leaves the cel, to the pixel.
///
/// A stamp made of the selection's own mask ([EngineStampMasks]): the
/// engine lays that mask by the eraser, taken whole where the gather took
/// whole — the twin of the gather, under the same mask on the engine's
/// grid. ↩️Till 2026-11-14 it was a picture the CPU built of the mask's
/// bytes at every lift and handed up (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move` — 「한쪽만 엔진
/// 마스크로 가면 가장자리 화소가 겹치거나 사라진다」, so the two moved
/// together).
BrushDab selectionEraseDab(SelectionPixels lifted, {required String id}) {
  final (:clip, :box, rgba: _, :takeWholePixels) = lifted;
  final (:left, :top, :width, :height) = box;
  return BrushDab(
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: 0xFF000000,
    size: math.max(width, height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: EngineStampMasks.made(
      id: id,
      width: width,
      height: height,
      coverage: clip.maskOnEngine,
      whole: takeWholePixels,
      rgba: () => _eraseAlpha(
        clip.maskFor(left: left, top: top, width: width, height: height),
        whole: takeWholePixels,
      ),
    ),
    erase: true,
  );
}

/// The erase's picture of [mask], for what reads its bytes off the engine.
///
/// The erase rides the STAMP path too (R15-④): destination-out from the
/// exact mask bytes — tip-mask erases resample bilinearly and left a
/// half-alpha ring at the silhouette (the fringe + origin remnant).
Uint8List _eraseAlpha(Uint8List mask, {required bool whole}) {
  final eraseAlpha = Uint8List(mask.length * 4);
  for (var index = 0; index < mask.length; index += 1) {
    // FULL removal wherever the mask touches at all — the twin of the
    // gather ([liftSelectionPixels]). The piece took the whole pixel, so
    // leaving any part of it here would be the ink appearing twice.
    eraseAlpha[index * 4 + 3] = whole
        ? (mask[index] == 0 ? 0 : 255)
        : mask[index];
  }
  return eraseAlpha;
}
