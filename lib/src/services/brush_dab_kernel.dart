import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_texture_mode.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_dab_share.dart';
import 'brush_dab_tip_geometry.dart';

/// THE dab's plan — the hoists and the clipped bounds, resolved once —
/// that the engine's dab is made of (`BrushLiveStrokeRasterizer`, which
/// piles every stroke and lands every commit's).
///
/// ↩️It was the geometric dab kernel both raster routes ran in Dart: the
/// pen-up commit and the live overlay, which had each carried their own
/// copy of the hoists, the lattices and the per-pixel cascade (about three
/// hundred lines each, pinned equal by the parity suite) until they were
/// written once here. Till 2026-11-14 its tile loop (`blendDabTilesDart`)
/// still ran off the engine's grid, the oracle the engine's kernel
/// (`dab.wgsl`) was held to; that grid is refused now (board
/// `the-off-engine-cpu-commit-lives-only-for-tests`), and the laws its loop
/// held stand beside the engine's kernel. The loop's own hoists went with
/// it — the tip's and the paper's axis lattices, the round tip's cull, the
/// paper's one-minus density — which every dab made and nothing read.

/// Everything one dab needs, resolved once: the clipped bounds and the tip
/// geometry.
///
/// Pure value — no surface, no buffers, no engine. [of] returns null when
/// the dab contributes nothing (empty region, transparent colour, or a
/// clip that leaves no pixels): skip this dab.
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
    required this.dabOpacity,
    required this.dabFlow,
    required this.erase,
    required this.second,
    required this.dual,
    required this.textureMask,
    required this.textureDensity,
    required this.textureMode,
    required this.textureScale,
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

  final double dabOpacity;
  final double dabFlow;

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

  /// How the paper meets the coverage — see [BrushDab.textureMode].
  final BrushTextureMode textureMode;

  /// Canvas pixels a texel of the paper — see [BrushDab.textureScale].
  final double textureScale;

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
    final edge = brushDabEdgeLaw(dab);

    final clip = region.intersection(wall.region);
    if (clip == null) {
      return null;
    }
    final tiles = clip.tileRange(tileSize: tileSize);

    return BrushDabPlan._(
      clip: clip,
      left: clip.left,
      top: clip.top,
      rightExclusive: clip.rightExclusive,
      bottomExclusive: clip.bottomExclusive,
      tileXStart: tiles.firstX,
      tileXEnd: tiles.lastX,
      tileYStart: tiles.firstY,
      tileYEnd: tiles.lastY,
      sourceR: argbRed(sourceArgb),
      sourceG: argbGreen(sourceArgb),
      sourceB: argbBlue(sourceArgb),
      sourceAlphaNorm: sourceA / 255.0,
      centerX: dab.center.x,
      centerY: dab.center.y,
      tip: tip,
      aaThreshold: edge.threshold,
      aaContrast: edge.contrast,
      edgeHeld: tipHoldsAnEdge(tip, edge),
      dabOpacity: dab.opacity,
      dabFlow: dab.flow,
      erase: erase,
      second: dab.second,
      dual: dab.dual,
      textureMask: dab.textureMask,
      textureDensity: dab.textureDensity,
      textureMode: dab.textureMode,
      textureScale: dab.textureScale,
      evening: eveningTableOf(dab),
    );
  }
}
