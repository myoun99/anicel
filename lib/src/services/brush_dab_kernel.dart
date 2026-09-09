import 'dart:ffi' show Pointer, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_tip_mask_sampling.dart';
import 'native_tile_span_batch.dart';

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
/// The C kernel (`qa_dab_blend_tile`) is a THIRD transcription and stays
/// one: it is a different language, gated behind the ABI version, and
/// pinned byte-exact by its own parity suite.

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
    required this.radius,
    required this.hardRadius,
    required this.edgeSpan,
    required this.aaThreshold,
    required this.aaContrast,
    required this.minorRadius,
    required this.radiusSqSkip,
    required this.tipCos,
    required this.tipSin,
    required this.inverseRoundness,
    required this.dabOpacity,
    required this.dabFlow,
    required this.isRound,
    required this.isEllipse,
    required this.unrotatedTip,
    required this.erase,
    required this.tipMask,
    required this.dualMask,
    required this.textureMask,
    required this.dualDensity,
    required this.dualOneMinusDensity,
    required this.textureDensity,
    required this.textureOneMinusDensity,
    required this.tipULattice,
    required this.tipVLattice,
    required this.dualULattice,
    required this.dualVLattice,
    required this.textureULattice,
    required this.textureVLattice,
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

  /// The edge step, hoisted out of the pixel loop (see [BrushAntiAlias]).
  /// [aaThreshold] is 없음 — a hard cut at half coverage; otherwise
  /// [aaContrast] scales the ramp about 0.5, and 1.0 leaves it alone.
  /// ⛔TWO FIELDS FOR ONE ENUM ON PURPOSE: this is the per-pixel form of
  /// [BrushAntiAlias.applyTo], derived once here so the loop needs no
  /// switch. The enum stays the definition.
  final bool aaThreshold;
  final double aaContrast;
  final double radius;
  final double hardRadius;
  final double edgeSpan;
  final double minorRadius;

  /// Conservative squared-distance cull for plain round tips: only pixels
  /// PROVABLY outside the radius skip the sqrt; anything within the float
  /// margin still runs the exact scalar test.
  final double radiusSqSkip;

  final double tipCos;
  final double tipSin;
  final double inverseRoundness;
  final double dabOpacity;
  final double dabFlow;

  final bool isRound;
  final bool isEllipse;
  final bool unrotatedTip;

  /// Destination-out instead of source-over. The commit passes
  /// `dab.erase`; the live overlay passes false always — it never carries
  /// the erase flag, because erase strokes composite at display time.
  final bool erase;

  final BrushTipMask? tipMask;
  final BrushTipMask? dualMask;
  final BrushTipMask? textureMask;
  final double dualDensity;
  final double dualOneMinusDensity;
  final double textureDensity;
  final double textureOneMinusDensity;

  final BrushTipMaskAxisLattice? tipULattice;
  final BrushTipMaskAxisLattice? tipVLattice;
  final TiledMaskAxisLattice? dualULattice;
  final TiledMaskAxisLattice? dualVLattice;
  final TiledMaskAxisLattice? textureULattice;
  final TiledMaskAxisLattice? textureVLattice;

  /// Resolves [dab] against the pasteboard, or null when it paints nothing.
  ///
  /// [erase] is the caller's, not the dab's, on purpose: the two routes
  /// disagree about it by design and the disagreement should be visible at
  /// the call site rather than buried here.
  static BrushDabPlan? of(
    BrushDab dab, {
    required CanvasSize canvasSize,
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

    final (
      :radius,
      :minorRadius,
      :hardRadius,
      :isRound,
      :tipMask,
      :isEllipse,
      :tipCos,
      :tipSin,
      :inverseRoundness,
    ) = brushDabTipGeometry(dab);
    final centerX = dab.center.x;
    final centerY = dab.center.y;

    final clip = region.intersection(canvasSize.pasteboardRegion);
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
    final dualMask = dab.dualMask;
    final textureMask = dab.textureMask;
    final dualDensity = dab.dualDensity;
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
      radius: radius,
      hardRadius: hardRadius,
      edgeSpan: radius - hardRadius,
      aaThreshold: dab.antiAlias == BrushAntiAlias.none,
      aaContrast: dab.antiAlias.contrast ?? 1.0,
      minorRadius: minorRadius,
      radiusSqSkip: radius * radius * (1.0 + 1e-12),
      tipCos: tipCos,
      tipSin: tipSin,
      inverseRoundness: inverseRoundness,
      dabOpacity: dab.opacity,
      dabFlow: dab.flow,
      isRound: isRound,
      isEllipse: isEllipse,
      unrotatedTip: unrotatedTip,
      erase: erase,
      tipMask: tipMask,
      dualMask: dualMask,
      textureMask: textureMask,
      dualDensity: dualDensity,
      dualOneMinusDensity: 1.0 - dualDensity,
      textureDensity: textureDensity,
      textureOneMinusDensity: 1.0 - textureDensity,
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
              inverseRoundness: inverseRoundness,
            )
          : null,
      dualULattice: dualMask == null
          ? null
          : TiledMaskAxisLattice.compute(
              mask: dualMask,
              start: left,
              count: columnCount,
              originOffset: -centerX,
              period: dab.size * dab.dualMaskScale,
              offset: dab.dualOffsetU,
            ),
      dualVLattice: dualMask == null
          ? null
          : TiledMaskAxisLattice.compute(
              mask: dualMask,
              start: top,
              count: rowCount,
              originOffset: -centerY,
              period: dab.size * dab.dualMaskScale,
              offset: dab.dualOffsetV,
            ),
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
    );
  }
}

/// Hands the plan to the C kernel: one `prepareDab`, one staged span per
/// covered tile ([stageTileSpans]), one pooled batch call.
///
/// [pointerFor] returns the tile's native scratch pointer, CREATING the
/// buffer if this dab is the first to touch the tile.
///
/// Returns the per-tile changed flags the kernel wrote (valid until the
/// next batch) beside the coordinates they index, in span order.
({Uint8List changed, List<TileCoord> coords}) blendDabTilesNative(
  BrushDabPlan plan,
  QaNativeEngine native, {
  required int tileSize,
  required Pointer<Uint8> Function(TileCoord coord) pointerFor,
}) {
  native.prepareDab(
    centerX: plan.centerX,
    centerY: plan.centerY,
    radius: plan.radius,
    hardRadius: plan.hardRadius,
    edgeSpan: plan.edgeSpan,
    minorRadius: plan.minorRadius,
    tipCos: plan.tipCos,
    tipSin: plan.tipSin,
    inverseRoundness: plan.inverseRoundness,
    dabOpacity: plan.dabOpacity,
    dabFlow: plan.dabFlow,
    sourceAlphaNorm: plan.sourceAlphaNorm,
    radiusSqSkip: plan.radiusSqSkip,
    dualDensity: plan.dualDensity,
    dualOneMinusDensity: plan.dualOneMinusDensity,
    textureDensity: plan.textureDensity,
    textureOneMinusDensity: plan.textureOneMinusDensity,
    aaContrast: plan.aaContrast,
    sourceR: plan.sourceR,
    sourceG: plan.sourceG,
    sourceB: plan.sourceB,
    flags:
        (plan.erase ? QaNativeEngine.dabFlagErase : 0) |
        (plan.isRound ? QaNativeEngine.dabFlagRound : 0) |
        (plan.isEllipse ? QaNativeEngine.dabFlagEllipse : 0) |
        (plan.unrotatedTip ? QaNativeEngine.dabFlagTipUnrotated : 0) |
        (plan.aaThreshold ? QaNativeEngine.dabFlagAaThreshold : 0),
    regionLeft: plan.left,
    regionTop: plan.top,
    tipAlpha: plan.tipMask?.alphaNormalized,
    tipSize: plan.tipMask?.size ?? 0,
    tipUTexel0: plan.tipULattice?.texel0,
    tipUFraction: plan.tipULattice?.fraction,
    tipUOneMinus: plan.tipULattice?.oneMinusFraction,
    tipUInRange: plan.tipULattice?.inRange,
    tipVTexel0: plan.tipVLattice?.texel0,
    tipVFraction: plan.tipVLattice?.fraction,
    tipVOneMinus: plan.tipVLattice?.oneMinusFraction,
    tipVInRange: plan.tipVLattice?.inRange,
    dualAlpha: plan.dualMask?.alphaNormalized,
    dualSize: plan.dualMask?.size ?? 0,
    dualUTexel0: plan.dualULattice?.texel0,
    dualUTexel1: plan.dualULattice?.texel1,
    dualUFraction: plan.dualULattice?.fraction,
    dualUOneMinus: plan.dualULattice?.oneMinusFraction,
    dualVTexel0: plan.dualVLattice?.texel0,
    dualVTexel1: plan.dualVLattice?.texel1,
    dualVFraction: plan.dualVLattice?.fraction,
    dualVOneMinus: plan.dualVLattice?.oneMinusFraction,
    texAlpha: plan.textureMask?.alphaNormalized,
    texSize: plan.textureMask?.size ?? 0,
    texUTexel0: plan.textureULattice?.texel0,
    texUTexel1: plan.textureULattice?.texel1,
    texUFraction: plan.textureULattice?.fraction,
    texUOneMinus: plan.textureULattice?.oneMinusFraction,
    texVTexel0: plan.textureVLattice?.texel0,
    texVTexel1: plan.textureVLattice?.texel1,
    texVFraction: plan.textureVLattice?.fraction,
    texVOneMinus: plan.textureVLattice?.oneMinusFraction,
  );

  // The plan's clip is never empty (BrushDabPlan.of returns null for
  // that), so there is always at least one span.
  final coords = stageTileSpans(
    native,
    clip: plan.clip,
    tileSize: tileSize,
    pointerFor: pointerFor,
  );
  return (
    changed: native.dabBlendTiles(count: coords.length, tileSize: tileSize),
    coords: coords,
  );
}

/// The Dart reference blend: the same pixel visits and the same float
/// math the C kernel runs, straight into each tile's byte buffer.
///
/// This is the oracle AND the no-engine fallback, so every expression
/// below keeps its exact grouping — the parity suites pin commit == live
/// == native == the per-pixel reference pipeline.
///
/// [bufferFor] returns the tile's scratch bytes, creating them if needed;
/// it is called once per (row, tile), never per pixel. [onTileChanged]
/// fires for a tile whose bytes actually moved — the commit needs that
/// set to know which tiles to adopt; the live overlay passes null and the
/// call disappears.
///
/// Writes are compare-and-swap for BOTH routes: a byte that would not
/// change is not stored. That is what makes the changed set the true
/// change set, and it cannot alter the result — skipping a write of the
/// value already there is a no-op.
void blendDabTilesDart(
  BrushDabPlan plan, {
  required int tileSize,
  required Uint8List Function(int tileX, int tileY) bufferFor,
  void Function(int tileX, int tileY)? onTileChanged,
}) {
  // EVERY value the pixel loop reads is hoisted into a local first. The
  // two inline loops this replaced were written that way, and the bar is
  // a DEBUG build, where nothing is optimized and a field load really is
  // one more load per pixel than a stack slot.
  final tipMask = plan.tipMask;
  final dualMask = plan.dualMask;
  final textureMask = plan.textureMask;
  final tipULattice = plan.tipULattice;
  final tipVLattice = plan.tipVLattice;
  final dualULattice = plan.dualULattice;
  final dualVLattice = plan.dualVLattice;
  final textureULattice = plan.textureULattice;
  final textureVLattice = plan.textureVLattice;
  final centerX = plan.centerX;
  final centerY = plan.centerY;
  final radius = plan.radius;
  final hardRadius = plan.hardRadius;
  final edgeSpan = plan.edgeSpan;
  final aaThreshold = plan.aaThreshold;
  final aaContrast = plan.aaContrast;
  final radiusSqSkip = plan.radiusSqSkip;
  final tipCos = plan.tipCos;
  final tipSin = plan.tipSin;
  final inverseRoundness = plan.inverseRoundness;
  final isRound = plan.isRound;
  final isEllipse = plan.isEllipse;
  final unrotatedTip = plan.unrotatedTip;
  final dabOpacity = plan.dabOpacity;
  final dabFlow = plan.dabFlow;
  final sourceAlphaNorm = plan.sourceAlphaNorm;
  final sourceR = plan.sourceR;
  final sourceG = plan.sourceG;
  final sourceB = plan.sourceB;
  final dualDensity = plan.dualDensity;
  final dualOneMinusDensity = plan.dualOneMinusDensity;
  final textureDensity = plan.textureDensity;
  final textureOneMinusDensity = plan.textureOneMinusDensity;
  final left = plan.left;
  final top = plan.top;
  final rightExclusive = plan.rightExclusive;
  final bottomExclusive = plan.bottomExclusive;
  final tileXStart = plan.tileXStart;
  final tileXEnd = plan.tileXEnd;
  final erase = plan.erase;

  for (var y = top; y < bottomExclusive; y += 1) {
    final dy = y + 0.5 - centerY;
    final dySquared = dy * dy;
    final vIndex = y - top;
    if (tipVLattice != null && tipVLattice.inRange[vIndex] == 0) {
      // Same effect as the scalar |tipV| > radius per-pixel cull.
      continue;
    }
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;

    for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
      final buffer = bufferFor(tileX, tileY);
      final tileLeft = tileX * tileSize;
      final spanLeft = math.max(left, tileLeft);
      final spanRightExclusive = math.min(rightExclusive, tileLeft + tileSize);
      var tileChanged = false;

      for (var x = spanLeft; x < spanRightExclusive; x += 1) {
        double coverage;
        if (tipMask != null) {
          if (unrotatedTip) {
            final uIndex = x - left;
            if (tipULattice!.inRange[uIndex] == 0) {
              continue;
            }
            coverage = sampleBrushTipMaskCoverageLattice(
              mask: tipMask,
              uAxis: tipULattice,
              uIndex: uIndex,
              vAxis: tipVLattice!,
              vIndex: vIndex,
            );
          } else {
            final dx = x + 0.5 - centerX;
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
            if (tipU.abs() > radius || tipV.abs() > radius) {
              continue;
            }
            coverage = sampleBrushTipMaskCoverage(
              mask: tipMask,
              tipU: tipU,
              tipV: tipV,
              radius: radius,
            );
          }
          if (coverage <= 0.0) {
            continue;
          }
        } else if (isRound) {
          final dx = x + 0.5 - centerX;
          double distance;
          if (isEllipse) {
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
            distance = math.sqrt(tipU * tipU + tipV * tipV);
          } else {
            final dxSquared = dx * dx;
            if (dxSquared + dySquared > radiusSqSkip) {
              continue;
            }
            distance = math.sqrt(dxSquared + dySquared);
          }
          if (distance > radius) {
            continue;
          }
          if (distance <= hardRadius || edgeSpan <= 0.0) {
            coverage = 1.0;
          } else {
            coverage = (1.0 - ((distance - hardRadius) / edgeSpan)).clamp(
              0.0,
              1.0,
            );
          }
          if (coverage <= 0.0) {
            continue;
          }
        } else {
          // A square dab is axis-aligned by construction now, so there is no
          // rotated-rect case left to test for.
          coverage = 1.0;
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

        // Dual-brush texture: a second tiled mask multiplies the coverage.
        if (dualMask != null) {
          final dualSample = sampleBrushTipMaskTiledCoverageLattice(
            mask: dualMask,
            uAxis: dualULattice!,
            uIndex: x - left,
            vAxis: dualVLattice!,
            vIndex: vIndex,
          );
          // Same law as the texture blend below; density 1.0 is the plain
          // multiply this used to do unconditionally.
          coverage *= dualOneMinusDensity + dualDensity * dualSample;
          if (coverage <= 0.0) {
            continue;
          }
        }

        // Paper texture: canvas-anchored tiled mask, blended in by density.
        if (textureMask != null) {
          final textureSample = sampleBrushTipMaskTiledCoverageLattice(
            mask: textureMask,
            uAxis: textureULattice!,
            uIndex: x - left,
            vAxis: textureVLattice!,
            vIndex: vIndex,
          );
          coverage *= textureOneMinusDensity + textureDensity * textureSample;
          if (coverage <= 0.0) {
            continue;
          }
        }

        // Same grouping as the reference path:
        // effectiveOpacity = dab.opacity * coverage,
        // sourceAlpha = ((a/255) * effectiveOpacity) * flow.
        final effectiveOpacity = dabOpacity * coverage;
        if (effectiveOpacity == 0.0) {
          continue;
        }
        final sourceAlpha = sourceAlphaNorm * effectiveOpacity * dabFlow;

        final offset = (localRowOffset + (x - tileLeft)) * 4;
        final destR = buffer[offset];
        final destG = buffer[offset + 1];
        final destB = buffer[offset + 2];
        final destA = buffer[offset + 3];

        final destinationAlpha = destA / 255.0;

        int outRByte;
        int outGByte;
        int outBByte;
        int outAByte;
        if (erase) {
          // Destination-out (same grouping as the reference
          // rgbaDestinationOut): coverage removes destination alpha.
          final outAlpha = destinationAlpha * (1.0 - sourceAlpha);
          if (outAlpha == 0.0) {
            outRByte = 0;
            outGByte = 0;
            outBByte = 0;
            outAByte = 0;
          } else {
            outRByte = destR;
            outGByte = destG;
            outBByte = destB;
            outAByte = (outAlpha * 255.0).round().clamp(0, 255);
          }
        } else {
          final outAlpha = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
          if (outAlpha == 0.0) {
            outRByte = 0;
            outGByte = 0;
            outBByte = 0;
            outAByte = 0;
          } else {
            // Keep the exact floating-point grouping of the reference
            // rgbaSourceOver: (dest * destinationAlpha) *
            // inverseSourceAlpha.
            final inverseSourceAlpha = 1.0 - sourceAlpha;
            outRByte =
                ((sourceR * sourceAlpha +
                            destR * destinationAlpha * inverseSourceAlpha) /
                        outAlpha)
                    .round()
                    .clamp(0, 255);
            outGByte =
                ((sourceG * sourceAlpha +
                            destG * destinationAlpha * inverseSourceAlpha) /
                        outAlpha)
                    .round()
                    .clamp(0, 255);
            outBByte =
                ((sourceB * sourceAlpha +
                            destB * destinationAlpha * inverseSourceAlpha) /
                        outAlpha)
                    .round()
                    .clamp(0, 255);
            outAByte = (outAlpha * 255.0).round().clamp(0, 255);
          }
        }

        if (outRByte != destR ||
            outGByte != destG ||
            outBByte != destB ||
            outAByte != destA) {
          buffer[offset] = outRByte;
          buffer[offset + 1] = outGByte;
          buffer[offset + 2] = outBByte;
          buffer[offset + 3] = outAByte;
          tileChanged = true;
        }
      }

      if (tileChanged && onTileChanged != null) {
        onTileChanged(tileX, tileY);
      }
    }
  }
}
