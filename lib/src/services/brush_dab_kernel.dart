import 'dart:ffi' show Pointer, Uint16, Uint8;
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../core/floor_math.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_texture_mode.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_share.dart';
import 'brush_dab_tip_geometry.dart';
import 'brush_stroke_blend.dart';
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

/// One stroke tile as the Dart route holds it: the RGBA [bytes] everything
/// downstream reads, and the [wide] plane — RGBA at 16 bits, alpha * 65535
/// and a channel * 257 — that its dabs pile up in.
///
/// 🚨The law and its reasons are written once, beside `qa_dab_store` in
/// qa_engine.c (ABI 40, 유저 2026-10-01 「a는 제안한대로 16비트?」): a dab
/// reads what is under it from [wide] and writes both planes from the same
/// double, so [bytes] is [wide]'s view and nothing downstream changes. A
/// stroke with a second tip carries its [second] plane too, alpha * 65535,
/// and [bytes] is then the view of the two (`qa_dual_view_rows`, ABI 60).
typedef BrushDabTileBuffers = ({
  Uint8List bytes,
  Uint16List wide,
  Uint16List? second,
});

/// The same planes as the C route holds them.
typedef BrushDabTilePointers = ({
  Pointer<Uint8> pixels,
  Pointer<Uint16> wide,
  Pointer<Uint16>? second,
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
  /// loop hands it over whole, the native spec copies its numbers out.
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

/// Collects the dabs a route blends and hands them to the C kernel a batch
/// at a time — the one way both routes reach it.
///
/// 🚨A CALL IS A BATCH, NOT A DAB (ABI 38, 2026-09-24, board
/// `preset-spacing-minimum`). At the 1% spacing the presets moved to, a
/// stroke lays a dab about every pixel, and one pooled call per dab woke
/// the workers once a dab — ~0.2 ms each on a 20-thread desktop, as long
/// as a 100 px dab takes alone, so the pool bought nothing below 200 px
/// (`qa_dab_blend_batch` has the numbers). A batch is woken for once.
///
/// A batch ends where its masks would outgrow what the native mask cache
/// holds at once ([QaNativeEngine.batchMaskAllowance]) — every spec in the
/// batch points at an upload, and the cache only promises its newest — and
/// at [maxDabs], which bounds the lattice arena one call holds. ⛔NOT at
/// every change of mask: a pen stroke's dabs carry a tip resolved per
/// quantized size (`BrushTipStampCache`), so pressure changes the mask
/// every few dabs, and a cut there would bring back the call a dab. Either
/// cut leaves the bytes alone — the dabs still land in their order.
class NativeDabBatcher {
  NativeDabBatcher(
    this.native, {
    required this.tileSize,
    required this.planesFor,
    this.onTileChanged,
  });

  final QaNativeEngine native;
  final int tileSize;

  /// The tile's native planes, CREATED if this batch is the first to touch
  /// the tile.
  final BrushDabTilePointers Function(TileCoord coord) planesFor;

  /// Each tile a batch changed — the commit adopts exactly those; the live
  /// overlay passes null.
  final void Function(TileCoord coord)? onTileChanged;

  static const int maxDabs = 64;

  final List<BrushDabPlan> _pending = [];

  /// The distinct masks the pending batch uploads, and their bytes.
  final Set<BrushTipMask> _masks = Set<BrushTipMask>.identity();
  int _maskBytes = 0;

  /// Queues [plan] behind the dabs before it, first flushing the batch it
  /// cannot join.
  void add(BrushDabPlan plan) {
    var fresh = _freshMasks(plan);
    if (_pending.isNotEmpty && !_fits(fresh)) {
      flush();
      fresh = _freshMasks(plan);
    }
    _pending.add(plan);
    for (final mask in fresh) {
      _masks.add(mask);
      _maskBytes += _uploadBytes(mask);
    }
  }

  bool _fits(Set<BrushTipMask> fresh) {
    if (_pending.length == maxDabs) {
      return false;
    }
    final allowance = native.batchMaskAllowance;
    var bytes = _maskBytes;
    for (final mask in fresh) {
      bytes += _uploadBytes(mask);
    }
    return _masks.length + fresh.length <= allowance.count &&
        bytes <= allowance.bytes;
  }

  Set<BrushTipMask> _freshMasks(BrushDabPlan plan) => {
    for (final mask in [plan.tipMask, plan.textureMask])
      if (mask != null && !_masks.contains(mask)) mask,
  };

  /// The bytes the engine uploads for [mask] — its normalized alpha, a
  /// double a texel.
  static int _uploadBytes(BrushTipMask mask) => mask.size * mask.size * 8;

  /// Blends every queued dab — before anything reads the tiles, and before
  /// a dab of another kind (a stamp) lands on them.
  void flush() {
    if (_pending.isEmpty) {
      return;
    }
    final blended = blendDabBatchNative(
      _pending,
      native,
      tileSize: tileSize,
      planesFor: planesFor,
    );
    _pending.clear();
    _masks.clear();
    _maskBytes = 0;
    final sink = onTileChanged;
    if (sink == null) {
      return;
    }
    for (final coord in changedTileCoords(blended.changed, blended.coords)) {
      sink(coord);
    }
  }
}

/// Hands [plans] to the C kernel in ONE call: each dab staged at its index,
/// one span per tile the batch covers ([stageTileSpansCovering]), one
/// pooled call that applies them in order.
///
/// Returns the per-tile changed flags the kernel wrote (valid until the
/// next batch) beside the coordinates they index, in span order.
({Uint8List changed, List<TileCoord> coords}) blendDabBatchNative(
  List<BrushDabPlan> plans,
  QaNativeEngine native, {
  required int tileSize,
  required BrushDabTilePointers Function(TileCoord coord) planesFor,
}) {
  native.beginDabBatch(plans.length);
  for (var index = 0; index < plans.length; index += 1) {
    _prepareDab(native, index, plans[index]);
  }
  final coords = stageTileSpansCovering(
    native,
    clips: [for (final plan in plans) plan.clip],
    tileSize: tileSize,
    planesFor: planesFor,
  );
  // A stroke's view is one for all its dabs ([BrushDab.dual]).
  final dual = plans.first.dual;
  assert(
    plans.every((plan) => plan.dual == dual),
    'a batch is one stroke\'s, and a stroke has one view',
  );
  return (
    changed: native.dabBlendBatch(
      tileCount: coords.length,
      dabCount: plans.length,
      tileSize: tileSize,
      dualMode: dual == null
          ? 0
          : separableBlendModeNativeId(dual.compositeMode),
      dualDensity: dual?.density ?? 0.0,
    ),
    coords: coords,
  );
}

/// Stages [plan] alone as the engine's dab batch and returns its spec — how
/// a kernel other than the dab blend reads a dab (the blur's coverage,
/// I-75): the same fields, staged by the same call.
Pointer<QaDabSpecStruct> stageDabAlone(
  QaNativeEngine native,
  BrushDabPlan plan,
) {
  native.beginDabBatch(1);
  _prepareDab(native, 0, plan);
  return native.stagedDabSpecs;
}

void _prepareDab(QaNativeEngine native, int index, BrushDabPlan plan) {
  native.prepareDabAt(
    index,
    clipLeft: plan.left,
    clipTop: plan.top,
    clipRightExclusive: plan.rightExclusive,
    clipBottomExclusive: plan.bottomExclusive,
    centerX: plan.centerX,
    centerY: plan.centerY,
    radius: plan.tip.radius,
    roundScale: plan.tip.profile?.scale ?? 0.0,
    roundReach: plan.tip.reach,
    roundInner: plan.tip.profile?.inner ?? 0.0,
    roundRowLength: (plan.tip.profile?.rowLength ?? 0).toDouble(),
    minorRadius: plan.tip.minorRadius,
    tipCos: plan.tip.tipCos,
    tipSin: plan.tip.tipSin,
    inverseRoundness: plan.tip.inverseRoundness,
    dabOpacity: plan.dabOpacity,
    dabFlow: plan.dabFlow,
    sourceAlphaNorm: plan.sourceAlphaNorm,
    radiusSqSkip: plan.radiusSqSkip,
    textureDensity: plan.textureDensity,
    textureOneMinusDensity: plan.textureOneMinusDensity,
    aaContrast: plan.aaContrast,
    sourceR: plan.sourceR,
    sourceG: plan.sourceG,
    sourceB: plan.sourceB,
    flags:
        (plan.erase ? QaNativeEngine.dabFlagErase : 0) |
        (plan.tip.isRound ? QaNativeEngine.dabFlagRound : 0) |
        (plan.tip.isEllipse ? QaNativeEngine.dabFlagEllipse : 0) |
        (plan.unrotatedTip ? QaNativeEngine.dabFlagTipUnrotated : 0) |
        (plan.aaThreshold ? QaNativeEngine.dabFlagAaThreshold : 0) |
        (plan.edgeHeld ? QaNativeEngine.dabFlagEdgeHeld : 0) |
        (plan.second ? QaNativeEngine.dabFlagSecond : 0) |
        (plan.textureMode == BrushTextureMode.height
            ? QaNativeEngine.dabFlagTextureHeight
            : 0),
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
    // Only the lattice path narrows its rows by the ink (ABI 39).
    tipRowInk: plan.unrotatedTip ? plan.tipMask!.inkedColumns : null,
    evening: plan.evening,
    roundCoverage: plan.tip.profile?.coverage,
    roundPile: plan.edgeHeld ? plan.tip.profile?.pile : null,
  );
}

/// The Dart reference blend: the same pixel visits and the same float
/// math the C kernel runs, straight into each tile's byte buffer.
///
/// This is the oracle AND the no-engine fallback, so every expression
/// below keeps its exact grouping — the parity suites pin commit == live
/// == native == the per-pixel reference pipeline.
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
  final textureDensity = plan.textureDensity;
  final textureOneMinusDensity = plan.textureOneMinusDensity;
  final textureHeight = plan.textureMode == BrushTextureMode.height;
  final left = plan.left;
  final top = plan.top;
  final rightExclusive = plan.rightExclusive;
  final bottomExclusive = plan.bottomExclusive;
  final tileXStart = plan.tileXStart;
  final tileXEnd = plan.tileXEnd;
  // A second tip's dab piles over, never erases (`qa_dab_blend_tile`).
  final erase = plan.erase && !second;
  final evening = plan.evening;
  final edgeHeld = plan.edgeHeld;
  // The dab's colour on the 16-bit plane (`qa_dab_over_own_colour`).
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
        // reasons are written once, beside `qa_dab_source_alpha` in
        // qa_engine.c; this is its arithmetic, operation by operation.
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

        if (second) {
          // The second plane piles as any dab piles over its alpha; the view
          // shows it ([_viewDual]). `qa_dab_store`'s alpha, the same
          // grouping.
          final piled = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
          final stored = (piled * 65535.0).round().clamp(0, 65535);
          if (stored != levels![pixel]) {
            levels[pixel] = stored;
          }
          continue;
        }

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
          // colour exactly (`qa_dab_over_own_colour`).
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
        // moves — `qa_dab_store`'s arithmetic, operation by operation: the
        // view rounded from the double, never from the plane, and the
        // change set the view's.
        var outR = 0;
        var outG = 0;
        var outB = 0;
        var outA = 0;
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
            // No colour under a zero alpha in the view (`StrokePixel.rounded`).
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
        if (levels != null) {
          // A tile with a second plane shows its view ([_viewDual]): the
          // view writes the bytes, and says which moved.
          continue;
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
  if (plan.dual case final dual?) {
    _viewDual(
      plan,
      dual,
      tileSize: tileSize,
      bufferFor: bufferFor,
      onTileChanged: onTileChanged,
    );
  }
}

/// The bytes of a stroke with a second tip rebuilt from its two planes over
/// [plan]'s rect, once the dab has landed — `qa_dual_view_rows`, which has
/// the law, pixel for pixel ([dualViewAlpha]). The C batch rebuilds the
/// rect its dabs make together once they all have landed: a pure function
/// of the two planes, so the bytes are the same.
void _viewDual(
  BrushDabPlan plan,
  BrushDualView dual, {
  required int tileSize,
  required BrushDabTileBuffers Function(int tileX, int tileY) bufferFor,
  void Function(int tileX, int tileY)? onTileChanged,
}) {
  for (var y = plan.top; y < plan.bottomExclusive; y += 1) {
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;
    for (var tileX = plan.tileXStart; tileX <= plan.tileXEnd; tileX += 1) {
      final (:bytes, :wide, second: levels) = bufferFor(tileX, tileY);
      if (levels == null) {
        continue;
      }
      final tileLeft = tileX * tileSize;
      final spanLeft = math.max(plan.left, tileLeft);
      final spanRightExclusive = math.min(
        plan.rightExclusive,
        tileLeft + tileSize,
      );
      var tileChanged = false;
      for (var x = spanLeft; x < spanRightExclusive; x += 1) {
        final pixel = localRowOffset + (x - tileLeft);
        final offset = pixel * 4;
        final outA = dualViewAlpha(wide[offset + 3], levels[pixel], dual);
        final outR = outA == 0 ? 0 : (wide[offset] / 257.0).round();
        final outG = outA == 0 ? 0 : (wide[offset + 1] / 257.0).round();
        final outB = outA == 0 ? 0 : (wide[offset + 2] / 257.0).round();
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
