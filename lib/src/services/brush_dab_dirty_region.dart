import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_tip_shape.dart';
import '../models/dirty_region.dart';
import '../models/dirty_tile_set.dart';

DirtyRegion? dirtyRegionForBrushDab(BrushDab dab) {
  if (dab.size == 0 || dab.opacity == 0 || dab.flow == 0) {
    return null;
  }
  // A STAMP lands 1:1 on its own rect ([BrushStampImage.landingRect]), and
  // that rect is its reach. The square of its size only covers it — and a
  // fill's piece is a row of tiles, as wide as a page and a tile or less
  // high, so the square reached far above and below it: a stroke that
  // needs the whole stroke as one buffer (a blend, 뒤에 그리기, a stroke
  // opacity) rasterized and composited all of that for nothing
  // (an-area-dab-costs-its-box, 2026-10-09).
  final stamp = dab.stamp;
  if (stamp != null) {
    return stamp.landingRect(dab.center);
  }

  final radius = dab.size / 2.0;
  var halfExtentX = radius;
  var halfExtentY = radius;
  // A rotated rectangle tip extends past the radius box (its half-diagonal
  // reaches radius * sqrt(2) at 45 degrees), so its bounds come from the
  // rotated-rect projection. Sampled (bitmap) tips span the same rotated
  // rect: their mask maps onto the size box in tip space. Round parametric
  // tips never exceed the radius circle (roundness only shrinks them), and
  // the axis-aligned square IS the radius box — both keep the original
  // bounds so existing dabs produce identical regions.
  if (dab.tipMask != null ||
      (dab.tipShape == BrushTipShape.square &&
          (dab.angleDegrees != 0.0 || dab.roundness < 1.0))) {
    final angleRadians = dab.angleDegrees * (math.pi / 180.0);
    final cosAbs = math.cos(angleRadians).abs();
    final sinAbs = math.sin(angleRadians).abs();
    final minorRadius = radius * dab.roundness;
    halfExtentX = radius * cosAbs + minorRadius * sinAbs;
    halfExtentY = radius * sinAbs + minorRadius * cosAbs;
  }
  // Raw dab bounds — NOT clamped to the canvas origin: pasteboard
  // painting reaches negative space. Paint paths clamp the region to the
  // surface's pasteboard rect at their clip step.
  final left = (dab.center.x - halfExtentX).floor();
  final top = (dab.center.y - halfExtentY).floor();
  final rightExclusive = (dab.center.x + halfExtentX).ceil();
  final bottomExclusive = (dab.center.y + halfExtentY).ceil();

  if (rightExclusive <= left || bottomExclusive <= top) {
    return null;
  }

  return DirtyRegion(
    left: left,
    top: top,
    rightExclusive: rightExclusive,
    bottomExclusive: bottomExclusive,
  );
}

List<DirtyRegion> dirtyRegionsForBrushDabSequence(BrushDabSequence sequence) {
  return List<DirtyRegion>.unmodifiable(
    sequence.dabs.map(dirtyRegionForBrushDab).whereType<DirtyRegion>(),
  );
}

DirtyRegion? dirtyRegionForBrushDabSequence(BrushDabSequence sequence) {
  final regions = dirtyRegionsForBrushDabSequence(sequence);
  if (regions.isEmpty) {
    return null;
  }

  return regions.skip(1).fold<DirtyRegion>(regions.first, (union, region) {
    return union.union(region);
  });
}

DirtyTileSet dirtyTileSetForBrushDabSequence({
  required BrushDabSequence sequence,
  required int tileSize,
}) {
  if (tileSize <= 0) {
    throw ArgumentError.value(
      tileSize,
      'tileSize',
      'tileSize must be greater than 0.',
    );
  }

  final regions = dirtyRegionsForBrushDabSequence(sequence);
  if (regions.isEmpty) {
    return DirtyTileSet.empty();
  }

  return DirtyTileSet.fromRegions(regions: regions, tileSize: tileSize);
}
