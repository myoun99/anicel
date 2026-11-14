import 'dart:math' as math;
import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_texture_mode.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_share.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_stroke_blend.dart';
import 'brush_tip_mask_sampling.dart';

/// THE geometric dab kernel — the one both raster routes run.
///
/// A dab is rasterized in two places: the pen-up commit
/// (`materializeBrushDabSequenceOnBitmapSurface`) and the live stroke
/// overlay (`BrushLiveStrokeRasterizer`). They must agree BYTE FOR BYTE —
/// the live pixels are the committed pixels, so any drift shows up as the
/// stroke shifting under the pen at pen-up.
///
/// That agreement used to be maintained by hand: both files carried their
/// own copy of the hoists, the six axis lattices, the ~50-argument native
/// `prepareDab` call, the span-batch loop and the per-pixel coverage
/// cascade — about three hundred lines each, with comments telling the
/// next reader to "match the other one exactly". They never did drift,
/// because the parity suite pinned them; what the duplication actually
/// bought was that every brush feature had to be written twice.
///
/// Here it is written once. The two routes differ only in the three
/// places they ACTUALLY differ:
///
/// 1. where a tile's bytes come from ([BrushDabTileBuffers]),
/// 2. whether the dab erases ([BrushDabPlan.erase] — the live overlay
///    never erases; erase strokes composite at display time),
/// 3. what to do with the tiles that changed (a callback, or nothing).
///
/// Nothing in the per-pixel loop became indirect: [blendDabTilesDart] is
/// the commit's own loop, and the live route is that loop with
/// `erase: false` and no changed-tile sink. Both flags are hoisted out of
/// the pixel loop, so this costs nothing per pixel even in a debug build,
/// where nothing inlines.
///
/// The engine's kernel (`dab.wgsl`) is another transcription and stays one:
/// it is a different language and rounds apart — in integers, where this
/// one rounds doubles (`a_dab_reaches_the_engine_whole_test` holds the two
/// within that). ↩️Till 2026-11-12 the C engine held a third
/// (`qa_dab_blend_tile`), pinned to this one byte for byte; it went with
/// the C, and its laws' texts came to the Dart they were transcribed from.

/// One stroke tile as this kernel holds it: the RGBA [bytes] everything
/// downstream reads, and the [wide] plane — RGBA at 16 bits, alpha * 65535
/// and a channel * 257 — that its dabs pile up in.
///
/// 🚨The law and its reasons are written once, beside `StrokePixel` (ABI
/// 40, 유저 2026-10-01 「a는 제안한대로 16비트?」): a dab reads what is under
/// it from [wide] and writes both planes from the same double, so [bytes]
/// is [wide]'s view and nothing downstream changes. A stroke with a second
/// tip carries its [second] plane too, alpha * 65535, and [bytes] is then
/// the view of the two (`dualViewAlpha`, ABI 60).
typedef BrushDabTileBuffers = ({
  Uint8List bytes,
  Uint16List wide,
  Uint16List? second,
});

/// Everything one dab needs, resolved once: the clipped bounds, the tip
/// geometry, and the axis lattices the samplers read.
///
/// Pure value — no surface, no buffers, no engine. [of] returns null when
/// the dab contributes nothing (empty region, transparent colour, or a
/// clip that leaves no pixels), which is the "skip this dab" answer both
/// routes already gave.
class BrushDabPlan {
  BrushDabPlan._({
    required this.clip,
    required this.left,
    required this.top,
    required this.rightExclusive,
    required this.bottomExclusive,
    required this.tileXStart,
    required this.tileXEnd,
    required this.tileYStart,
    required this.tileYEnd,
    required this.sourceR,
    required this.sourceG,
    required this.sourceB,
    required this.sourceAlphaNorm,
    required this.centerX,
    required this.centerY,
    required this.tip,
    required this.aaThreshold,
    required this.aaContrast,
    required this.edgeHeld,
    required this.radiusSqSkip,
    required this.dabOpacity,
    required this.dabFlow,
    required this.unrotatedTip,
    required this.erase,
    required this.second,
    required this.dual,
    required this.textureMask,
    required this.textureDensity,
    required this.textureOneMinusDensity,
    required this.textureMode,
    required this.textureScale,
    required this.tipULattice,
    required this.tipVLattice,
    required this.textureULattice,
    required this.textureVLattice,
    required this.evening,
  });

  /// The dab's region after the PASTEBOARD clip (canvas + one canvas size
  /// in every direction — drawing off the stage is the point), and the
  /// same four edges as ints for the per-span and per-row reads.
  final DirtyRegion clip;
  final int left;
  final int top;
  final int rightExclusive;
  final int bottomExclusive;

  /// The tile range the clipped bounds cover, inclusive.
  final int tileXStart;
  final int tileXEnd;
  final int tileYStart;
  final int tileYEnd;

  final int sourceR;
  final int sourceG;
  final int sourceB;
  final double sourceAlphaNorm;

  final double centerX;
  final double centerY;

  /// The tip, as the coverage law reads it ([tipCoverageAt]) — the Dart
  /// loop hands it over whole, the engine's dab copies its numbers out
  /// (`GpuDab`).
  final BrushDabTipGeometry tip;

  /// The edge step, hoisted out of the pixel loop ([brushDabEdgeLaw]).
  /// [aaThreshold] is 없음 — a hard cut at half coverage; otherwise
  /// [aaContrast] scales the ramp about 0.5, and 1.0 leaves it alone.
  /// ⛔TWO FIELDS FOR ONE LAW ON PURPOSE: this is the per-pixel form of
  /// [brushEdgeApplied], derived once here so the loop needs no switch.
  /// ↩️It was the anti-alias step's own `applyTo` until I-50 made the answer
  /// depend on the tip as well as the step.
  final bool aaThreshold;
  final double aaContrast;

  /// Whether the tip holds an EDGE that does not pile ([tipHoldsAnEdge]):
  /// the pixel loop then asks what of the coverage piles ([tipPileAt]) and
  /// lets the rest set the level the stroke settles at.
  final bool edgeHeld;

  /// Conservative squared-distance cull for plain round tips: only pixels
  /// PROVABLY outside the radius skip the sqrt; anything within the float
  /// margin still runs the exact scalar test.
  final double radiusSqSkip;

  final double dabOpacity;
  final double dabFlow;

  final bool unrotatedTip;

  /// Destination-out instead of source-over. The commit passes
  /// `dab.erase`; the live overlay passes false always — it never carries
  /// the erase flag, because erase strokes composite at display time.
  final bool erase;

  /// Whether the dab is the second tip's ([BrushDab.second]): it piles on
  /// the tile's second plane and moves no byte — the view does.
  final bool second;

  /// The stroke's view of its two planes ([BrushDab.dual]), or null for a
  /// stroke with one tip.
  final BrushDualView? dual;

  BrushTipMask? get tipMask => tip.tipMask;
  final BrushTipMask? textureMask;
  final double textureDensity;
  final double textureOneMinusDensity;

  /// How the paper meets the coverage — see [BrushDab.textureMode].
  final BrushTextureMode textureMode;

  /// Canvas pixels a texel of the paper — see [BrushDab.textureScale].
  final double textureScale;

  final BrushTipMaskAxisLattice? tipULattice;
  final BrushTipMaskAxisLattice? tipVLattice;
  final TiledMaskAxisLattice? textureULattice;
  final TiledMaskAxisLattice? textureVLattice;

  /// The table the dab lays its share through ([evenedLaid]), or null where
  /// it lays whole — the law is beside [stampShareOf].
  final Float64List? evening;

  /// Resolves [dab] against the pasteboard, or null when it paints nothing.
  ///
  /// [erase] is the caller's, not the dab's, on purpose: the two routes
  /// disagree about it by design and the disagreement should be visible at
  /// the call site rather than buried here.
  static BrushDabPlan? of(
    BrushDab dab, {
    required PasteboardWall wall,
    required int tileSize,
    required bool erase,
  }) {
    assert(
      dab.stamp == null,
      'stamp dabs take the dedicated 1:1 stamp blend, not the tip kernel',
    );
    final region = dirtyRegionForBrushDab(dab);
    if (region == null) {
      return null;
    }
    final sourceArgb = dab.color;
    final sourceA = argbAlpha(sourceArgb);
    if (sourceA == 0 || dab.opacity == 0.0 || dab.flow == 0.0) {
      return null;
    }

    final tip = brushDabTipGeometry(dab);
    final radius = tip.radius;
    final tipMask = tip.tipMask;
    final edge = brushDabEdgeLaw(dab);
    final centerX = dab.center.x;
    final centerY = dab.center.y;

    final clip = region.intersection(wall.region);
    if (clip == null) {
      return null;
    }
    // The four edges as ints beside the region: the kernels read them per
    // span and per row, and a field read is cheaper than a getter chain.
    final left = clip.left;
    final top = clip.top;
    final rightExclusive = clip.rightExclusive;
    final bottomExclusive = clip.bottomExclusive;
    final columnCount = rightExclusive - left;
    final rowCount = bottomExclusive - top;

    // Per-dab hoists and axis lattices (see brush_tip_mask_sampling.dart):
    // unrotated tips and the never-rotating tiled masks sample through
    // per-axis precomputes with the scalar samplers' exact arithmetic, so
    // the resulting bytes are unchanged — the parity suites pin this.
    final textureMask = dab.textureMask;
    final textureDensity = dab.textureDensity;
    final unrotatedTip = tipMask != null && dab.angleDegrees == 0.0;
    final tiles = clip.tileRange(tileSize: tileSize);

    return BrushDabPlan._(
      clip: clip,
      left: left,
      top: top,
      rightExclusive: rightExclusive,
      bottomExclusive: bottomExclusive,
      tileXStart: tiles.firstX,
      tileXEnd: tiles.lastX,
      tileYStart: tiles.firstY,
      tileYEnd: tiles.lastY,
      sourceR: argbRed(sourceArgb),
      sourceG: argbGreen(sourceArgb),
      sourceB: argbBlue(sourceArgb),
      sourceAlphaNorm: sourceA / 255.0,
      centerX: centerX,
      centerY: centerY,
      tip: tip,
      aaThreshold: edge.threshold,
      aaContrast: edge.contrast,
      edgeHeld: tipHoldsAnEdge(tip, edge),
      radiusSqSkip: tip.reach * tip.reach * (1.0 + 1e-12),
      dabOpacity: dab.opacity,
      dabFlow: dab.flow,
      unrotatedTip: unrotatedTip,
      erase: erase,
      second: dab.second,
      dual: dab.dual,
      textureMask: textureMask,
      textureDensity: textureDensity,
      textureOneMinusDensity: 1.0 - textureDensity,
      textureMode: dab.textureMode,
      textureScale: dab.textureScale,
      tipULattice: unrotatedTip
          ? BrushTipMaskAxisLattice.compute(
              mask: tipMask,
              radius: radius,
              start: left,
              count: columnCount,
              center: centerX,
            )
          : null,
      tipVLattice: unrotatedTip
          ? BrushTipMaskAxisLattice.compute(
              mask: tipMask,
              radius: radius,
              start: top,
              count: rowCount,
              center: centerY,
              inverseRoundness: tip.inverseRoundness,
            )
          : null,
      textureULattice: textureMask == null
          ? null
          : TiledMaskAxisLattice.compute(
              mask: textureMask,
              start: left,
              count: columnCount,
              originOffset: 0.0,
              period: textureMask.size * dab.textureScale,
              offset: 0.0,
            ),
      textureVLattice: textureMask == null
          ? null
          : TiledMaskAxisLattice.compute(
              mask: textureMask,
              start: top,
              count: rowCount,
              originOffset: 0.0,
              period: textureMask.size * dab.textureScale,
              offset: 0.0,
            ),
      evening: eveningTableOf(dab),
    );
  }
}

/// The Dart tile blend: the per-pixel reference's pixel visits and float
/// math, straight into each tile's byte buffer.
///
/// This is what a stroke runs on any grid but the engine's, and the oracle
/// the engine's kernel is held to, so every expression below keeps its
/// exact grouping — the parity suites pin commit == live == the per-pixel
/// reference pipeline.
///
/// [bufferFor] returns the tile's two planes, creating them if needed;
/// it is called once per (row, tile), never per pixel. [onTileChanged]
/// fires for a tile whose BYTES actually moved — the commit needs that
/// set to know which tiles to adopt; the live overlay passes null and the
/// call disappears.
///
/// Writes are compare-and-swap for BOTH routes: a value that would not
/// change is not stored. That is what makes the changed set the true
/// change set, and it cannot alter the result — skipping a write of the
/// value already there is a no-op.
void blendDabTilesDart(
  BrushDabPlan plan, {
  required int tileSize,
  required BrushDabTileBuffers Function(int tileX, int tileY) bufferFor,
  void Function(int tileX, int tileY)? onTileChanged,
}) {
  // EVERY value the pixel loop reads is hoisted into a local first. The
  // two inline loops this replaced were written that way, and the bar is
  // a DEBUG build, where nothing is optimized and a field load really is
  // one more load per pixel than a stack slot.
  final tipMask = plan.tipMask;
  final textureMask = plan.textureMask;
  final tipULattice = plan.tipULattice;
  final tipVLattice = plan.tipVLattice;
  final textureULattice = plan.textureULattice;
  final textureVLattice = plan.textureVLattice;
  final centerX = plan.centerX;
  final centerY = plan.centerY;
  final tip = plan.tip;
  final aaThreshold = plan.aaThreshold;
  final aaContrast = plan.aaContrast;
  final unrotatedTip = plan.unrotatedTip;
  final dabOpacity = plan.dabOpacity;
  final dabFlow = plan.dabFlow;
  final sourceAlphaNorm = plan.sourceAlphaNorm;
  final sourceR = plan.sourceR;
  final sourceG = plan.sourceG;
  final sourceB = plan.sourceB;
  final second = plan.second;
  final dual = plan.dual;
  final textureDensity = plan.textureDensity;
  final textureOneMinusDensity = plan.textureOneMinusDensity;
  final textureHeight = plan.textureMode == BrushTextureMode.height;
  final left = plan.left;
  final top = plan.top;
  final rightExclusive = plan.rightExclusive;
  final bottomExclusive = plan.bottomExclusive;
  final tileXStart = plan.tileXStart;
  final tileXEnd = plan.tileXEnd;
  // A second tip's dab piles on the second plane as any dab piles over its
  // alpha — over, never an erase — and the view shows it.
  final erase = plan.erase && !second;
  final evening = plan.evening;
  final edgeHeld = plan.edgeHeld;
  // The dab's colour on the 16-bit plane (`strokeSourceOverAt` has why).
  final ownR = sourceR * 257;
  final ownG = sourceG * 257;
  final ownB = sourceB * 257;

  for (var y = top; y < bottomExclusive; y += 1) {
    final dy = y + 0.5 - centerY;
    final vIndex = y - top;
    if (tipVLattice != null && tipVLattice.inRange[vIndex] == 0) {
      // Same effect as the scalar |tipV| > radius per-pixel cull.
      continue;
    }
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;

    for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
      final (:bytes, :wide, second: levels) = bufferFor(tileX, tileY);
      if (second && levels == null) {
        continue;
      }
      final tileLeft = tileX * tileSize;
      final spanLeft = math.max(left, tileLeft);
      final spanRightExclusive = math.min(rightExclusive, tileLeft + tileSize);
      var tileChanged = false;

      for (var x = spanLeft; x < spanRightExclusive; x += 1) {
        // An unrotated raster tip reads its two axis lattices — the one
        // road of its own; every other tip asks the coverage law, the same
        // body the coverage list and the stamp cache run ([tipCoverageAt]).
        double coverage;
        if (unrotatedTip) {
          final uIndex = x - left;
          if (tipULattice!.inRange[uIndex] == 0) {
            continue;
          }
          coverage = sampleBrushTipMaskCoverageLattice(
            mask: tipMask!,
            uAxis: tipULattice,
            uIndex: uIndex,
            vAxis: tipVLattice!,
            vIndex: vIndex,
          );
        } else {
          coverage = tipCoverageAt(tip, x + 0.5 - centerX, dy);
        }
        if (coverage <= 0.0) {
          continue;
        }

        // The brush's own EDGE, before anything tiles over it (유저 확정).
        //
        // ⚠️Placed HERE and nowhere else: ahead of the dual tip and the
        // paper texture, so tightening the edge hardens the SILHOUETTE and
        // leaves the texture inside it soft. Behind them it would binarize
        // a textured brush whole, which is a different brush.
        if (aaThreshold) {
          coverage = coverage >= 0.5 ? 1.0 : 0.0;
          if (coverage <= 0.0) {
            continue;
          }
        } else if (aaContrast != 1.0) {
          coverage = ((coverage - 0.5) * aaContrast + 0.5).clamp(0.0, 1.0);
          if (coverage <= 0.0) {
            continue;
          }
        }

        // 🚨★★★THE EDGE DOES NOT PILE (board a-one-pixel-dab-drops-out-by-
        // where-it-lies Q4, 유저 2026-10-25 「AA 가장자리는 쌓이지 않는다」):
        // of what the tip covers here only its PILE adds up where dabs
        // overlap ([tipPileAt]); the rest is its edge, and sets how high the
        // stroke may come here — this share of the dab's opacity. Over
        // nothing a dab lays its coverage, as it always did; a line's
        // cross-section is one dab's. 1 where all of it piles.
        final ceiling = edgeHeld
            ? edgeCeiling(coverage, tipPileAt(tip, x + 0.5 - centerX, dy))
            : 1.0;

        // Paper texture: canvas-anchored tiled mask, blended in by density.
        if (textureMask != null) {
          final textureSample = sampleBrushTipMaskTiledCoverageLattice(
            mask: textureMask,
            uAxis: textureULattice!,
            uIndex: x - left,
            vAxis: textureVLattice!,
            vIndex: vIndex,
          );
          if (textureHeight) {
            coverage = paperHeightCoverage(
              coverage,
              textureSample,
              textureDensity,
            );
          } else {
            coverage *= textureOneMinusDensity + textureDensity * textureSample;
          }
          if (coverage <= 0.0) {
            continue;
          }
        }

        final effectiveOpacity = dabOpacity * coverage;
        if (effectiveOpacity == 0.0) {
          continue;
        }

        final pixel = localRowOffset + (x - tileLeft);
        final offset = pixel * 4;
        // What is under the dab comes off the 16-bit plane (ABI 40) — a
        // second tip's dab's, off the second plane (ABI 60).
        final destinationAlpha = second
            ? levels![pixel] / 65535.0
            : wide[offset + 3] / 65535.0;
        // 🚨★★★A DAB SETTLES AT ITS OPACITY (F-205) — the law and its
        // reasons are written once, beside `settledDabAlpha`
        // (brush_pixel_blend.dart); this is its arithmetic, written inline.
        // Opacity 1 (or an erase) is the old grouping,
        // ((a/255) * (dab.opacity * coverage)) * flow. What the dab would
        // lay whole goes through its share first (`stampShareOf`).
        // Its edge's [ceiling] scales the level it settles at, and what it
        // lays toward it is the share that piles; at a ceiling of 1 both
        // are F-205's numbers to the bit.
        final double sourceAlpha;
        if (erase || (dabOpacity >= 1.0 && ceiling >= 1.0)) {
          final whole = sourceAlphaNorm * effectiveOpacity * dabFlow;
          sourceAlpha = evening == null ? whole : evenedLaid(evening, whole);
        } else {
          final settle = dabOpacity * ceiling;
          if (destinationAlpha >= settle) {
            continue;
          }
          final whole =
              sourceAlphaNorm * edgePiledShare(coverage, ceiling) * dabFlow;
          sourceAlpha =
              (evening == null ? whole : evenedLaid(evening, whole)) *
              (settle - destinationAlpha) /
              (1.0 - destinationAlpha);
        }

        var outR = 0;
        var outG = 0;
        var outB = 0;
        var outA = 0;
        if (second) {
          // The second plane piles as any dab piles over its alpha —
          // `StrokePixel.rounded`'s alpha, the same grouping.
          final piled = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
          final stored = (piled * 65535.0).round().clamp(0, 65535);
          if (stored != levels![pixel]) {
            levels[pixel] = stored;
          }
        } else {
          // Destination-out for an erase (the grouping of the reference
          // strokeDestinationOut), source-over otherwise, keeping the exact
          // floating-point grouping of the reference strokeSourceOverAt:
          // (dest * destinationAlpha) * inverseSourceAlpha.
          final inverseSourceAlpha = 1.0 - sourceAlpha;
          final double outAlpha;
          var red = 0.0;
          var green = 0.0;
          var blue = 0.0;
          if (erase) {
            outAlpha = destinationAlpha * inverseSourceAlpha;
          } else {
            outAlpha = sourceAlpha + destinationAlpha * inverseSourceAlpha;
            // Over nothing or over its own colour the dab lands its own
            // colour exactly (`strokeSourceOverAt` has the law).
            if (outAlpha != 0.0 &&
                (wide[offset + 3] == 0 ||
                    (wide[offset] == ownR &&
                        wide[offset + 1] == ownG &&
                        wide[offset + 2] == ownB))) {
              red = sourceR.toDouble();
              green = sourceG.toDouble();
              blue = sourceB.toDouble();
            } else if (outAlpha != 0.0) {
              red =
                  (sourceR * sourceAlpha +
                      wide[offset] / 257.0 *
                          destinationAlpha *
                          inverseSourceAlpha) /
                  outAlpha;
              green =
                  (sourceG * sourceAlpha +
                      wide[offset + 1] / 257.0 *
                          destinationAlpha *
                          inverseSourceAlpha) /
                  outAlpha;
              blue =
                  (sourceB * sourceAlpha +
                      wide[offset + 2] / 257.0 *
                          destinationAlpha *
                          inverseSourceAlpha) /
                  outAlpha;
            }
          }
          // Both planes from the same doubles, each written only where it
          // moves — `StrokePixel.rounded`'s arithmetic, as the tile holds
          // it: the view rounded from the double, never from the plane, and
          // the change set the view's.
          var wideR = 0;
          var wideG = 0;
          var wideB = 0;
          var wideA = 0;
          if (outAlpha != 0.0) {
            if (erase) {
              outR = bytes[offset];
              outG = bytes[offset + 1];
              outB = bytes[offset + 2];
              wideR = wide[offset];
              wideG = wide[offset + 1];
              wideB = wide[offset + 2];
            } else {
              outR = red.round().clamp(0, 255);
              outG = green.round().clamp(0, 255);
              outB = blue.round().clamp(0, 255);
              wideR = (red * 257.0).round().clamp(0, 65535);
              wideG = (green * 257.0).round().clamp(0, 65535);
              wideB = (blue * 257.0).round().clamp(0, 65535);
            }
            outA = (outAlpha * 255.0).round().clamp(0, 255);
            wideA = (outAlpha * 65535.0).round().clamp(0, 65535);
            if (outA == 0) {
              // No colour under a zero alpha in the view
              // (`StrokePixel.rounded`).
              outR = 0;
              outG = 0;
              outB = 0;
            }
          }
          if (wideR != wide[offset] ||
              wideG != wide[offset + 1] ||
              wideB != wide[offset + 2] ||
              wideA != wide[offset + 3]) {
            wide[offset] = wideR;
            wide[offset + 1] = wideG;
            wide[offset + 2] = wideB;
            wide[offset + 3] = wideA;
          }
        }
        if (levels != null) {
          // A tile with a second plane shows its view of the two planes as
          // they stand after the dab ([dualViewAlpha] has the law). Every
          // tile of such a stroke has had its
          // second plane from the first, so only a pixel whose planes the
          // dab moved can show anything new: the view is rebuilt here, the
          // reference's own road, pixel by pixel.
          outA = dualViewAlpha(wide[offset + 3], levels[pixel], dual!);
          outR = outA == 0 ? 0 : (wide[offset] / 257.0).round();
          outG = outA == 0 ? 0 : (wide[offset + 1] / 257.0).round();
          outB = outA == 0 ? 0 : (wide[offset + 2] / 257.0).round();
        }
        if (outR != bytes[offset] ||
            outG != bytes[offset + 1] ||
            outB != bytes[offset + 2] ||
            outA != bytes[offset + 3]) {
          bytes[offset] = outR;
          bytes[offset + 1] = outG;
          bytes[offset + 2] = outB;
          bytes[offset + 3] = outA;
          tileChanged = true;
        }
      }

      if (tileChanged && onTileChanged != null) {
        onTileChanged(tileX, tileY);
      }
    }
  }
}
