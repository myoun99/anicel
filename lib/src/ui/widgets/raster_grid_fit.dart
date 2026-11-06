import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// How a surface sits on the device pixel grid, which is what decides
/// whether an image of it is a copy or a resample — the one law both
/// rasters draw by: `StaticRaster`'s bake and `StillRaster`'s still image.
@immutable
class RasterGridFit {
  const RasterGridFit({required this.shift, required this.scale});

  /// How far the surface's top-left corner sits INTO the device pixel it
  /// begins in, in the surface's own logical units. Zero when the surface
  /// already starts on a whole pixel.
  final Offset shift;

  /// One logical unit of the surface, in device pixels — the view's ratio
  /// times any scale an ancestor applies.
  final double scale;

  /// Puts back an image taken over `Offset(-shift) & (size + shift)` at
  /// [scale], for a surface whose box starts at [origin]: 1:1, every
  /// source pixel on exactly one device pixel, which is what makes
  /// `FilterQuality.none` both the fastest and the SHARPEST choice rather
  /// than a snapping resample.
  ///
  /// The destination reaches up to one device pixel above and left of the
  /// box; that margin is the transparent slack [shift] describes, because
  /// the capture clips the content to its own box exactly as painting
  /// through does.
  void blit(Canvas canvas, ui.Image image, Offset origin) {
    blitPart(
      canvas,
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        origin.dx - shift.dx,
        origin.dy - shift.dy,
        image.width / scale,
        image.height / scale,
      ),
    );
  }

  /// [blit] for a part of an image: the pixels [from] of [image] put back
  /// over [onto], in the surface's own units — [logicalOf] the pixels of
  /// the surface's image grid they were taken from, so every one of them
  /// lands on exactly one device pixel.
  void blitPart(Canvas canvas, ui.Image image, Rect from, Rect onto) {
    canvas.drawImageRect(
      image,
      from,
      onto,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// The pixels of the surface's image grid — the grid of an image taken
  /// over `Offset(-shift) & (size + shift)` at [scale], its origin on the
  /// device pixel the box begins in — that [logical], in the surface's own
  /// units from its box's corner, reaches: whole pixels, outward.
  Rect devicePixelsOf(Rect logical) => Rect.fromLTRB(
    ((logical.left + shift.dx) * scale).floorToDouble(),
    ((logical.top + shift.dy) * scale).floorToDouble(),
    ((logical.right + shift.dx) * scale).ceilToDouble(),
    ((logical.bottom + shift.dy) * scale).ceilToDouble(),
  );

  /// Pixels of the surface's image grid ([devicePixelsOf]), in the
  /// surface's own units from its box's corner — where they land put back
  /// 1:1.
  Rect logicalOf(Rect device) => Rect.fromLTRB(
    device.left / scale - shift.dx,
    device.top / scale - shift.dy,
    device.right / scale - shift.dx,
    device.bottom / scale - shift.dy,
  );

  /// Where [box]'s top-left corner sits on the device pixel grid, or null
  /// when no 1:1 blit exists at all.
  ///
  /// 🚨This is the difference between a bake that COPIES and a bake that
  /// RESAMPLES, and getting it wrong is invisible in the one configuration
  /// people usually test in.
  ///
  /// `toImageSync` rounds the image UP to whole pixels, and the blit lands
  /// wherever layout puts the box. So unless the box's device-space origin
  /// AND size are both whole pixels, `FilterQuality.none` snaps every
  /// column and row to its nearest neighbour. Measured, both ways:
  ///
  ///  * a panel half a device pixel off the grid: **1483 pixels wrong
  ///    across 12 whole columns**, worst channel 128 — entire hairlines
  ///    and glyph stems jumping a pixel;
  ///  * a panel whose height is not a whole number of device pixels: the
  ///    whole bottom row wrong, worst channel 127.
  ///
  /// Neither is exotic. The second happens to EVERY panel at the 125%,
  /// 150% and 175% display scalings Windows ships, and the first whenever
  /// a splitter leaves a dock on a fractional pixel. At 100% and 200% both
  /// vanish, which is exactly why this survived: the parity test rendered
  /// at a whole ratio, on whole bounds, at a whole offset.
  ///
  /// So the capture is aligned instead: grown to cover whole device pixels
  /// and painted with [shift] so the content keeps the sub-pixel phase it
  /// would have had unbaked.
  static RasterGridFit? of(RenderObject box, double devicePixelRatio) {
    final ratio = devicePixelRatio;
    if (!ratio.isFinite || ratio <= 0) {
      return null;
    }
    // Logical global pixels, not device ones — `getTransformTo(null)`
    // stops at the root render object and the view's own ratio is applied
    // after it.
    //
    // 🚨It throws when the root is not an ancestor of ours, and a throw
    // out of `paint()` leaves a blank panel behind (see
    // `RenderStaticRaster._captureChild`). Not baking is always available
    // and always correct, so a surface we cannot locate simply paints
    // through.
    final Matrix4 toGlobal;
    try {
      toGlobal = box.getTransformTo(null);
    } on Object catch (_) {
      return null;
    }
    final uniformScale = uniformScaleOf(toGlobal);
    if (uniformScale == null) {
      return null;
    }
    // One of OUR logical units, in device pixels: the ancestors' scale
    // takes it to global logical units and the view's ratio from there.
    final scale = uniformScale * ratio;
    if (!scale.isFinite || scale <= 0) {
      return null;
    }
    // `origin` is already in global logical units, so it needs the view's
    // ratio and not the ancestors' scale a second time.
    final origin = MatrixUtils.transformPoint(toGlobal, Offset.zero);
    final left = origin.dx * ratio;
    final top = origin.dy * ratio;
    if (!left.isFinite || !top.isFinite) {
      return null;
    }
    return RasterGridFit(
      shift: Offset(_phaseOf(left) / scale, _phaseOf(top) / scale),
      scale: scale,
    );
  }

  /// How far into the device pixel it begins in [device] lies, in whole
  /// [_phaseStep]s — the same pixels read the same phase however the sum
  /// that placed them rounded.
  ///
  /// 🚨THE PHASE IS COMPARED, so its last bits are a question of their own
  /// (11-07, card a-live-dock-frame-costs-a-whole-draw). A region's corner
  /// is a sum of its ancestors' offsets times the ratio, rounded on the
  /// grid of the largest number it passed through. 🔬A conte row at 150%
  /// scrolled sideways by whole device pixels read 0 at device 1042 and
  /// 7.6e-14 at 1021, a pixel's width across 1024 — one image dropped and
  /// the row drawn live; and a sum that lands an ulp short of a whole pixel
  /// floors to the one before it, a phase of a whole pixel less an ulp.
  ///
  /// ⛔Not `DeviceGrid`'s relative slack: that floors a POSITION something
  /// is laid out at, where any overshoot shows. A phase is in [0, 1), and
  /// what is in its last bits is the coordinate's rounding — a few ulps of
  /// it, under 2e-9 of a pixel at a million pixels — so a fixed step far
  /// above that and far below a visible edge serves every coordinate: an
  /// edge moved by 1/65536 of a pixel changes its coverage by less than a
  /// 255th of a level. A phase that rounds up to the next pixel is that
  /// pixel's zero.
  static double _phaseOf(double device) {
    final steps = ((device - device.floorToDouble()) / _phaseStep)
        .roundToDouble();
    return steps * _phaseStep % 1;
  }

  static const double _phaseStep = 1 / 65536;

  /// The scale in [transform] when it is a translation and a single
  /// positive uniform scale, and null for anything else — a rotation, a
  /// skew, a mirror, a scale that differs per axis. Those can still be
  /// baked, but not as a pixel-for-pixel copy, so the surface paints
  /// through instead of quietly resampling itself.
  static double? uniformScaleOf(Matrix4 transform) {
    final m = transform.storage;
    const epsilon = 1e-6;
    bool zero(double value) => value.abs() < epsilon;
    if (!zero(m[1]) ||
        !zero(m[2]) ||
        !zero(m[3]) ||
        !zero(m[4]) ||
        !zero(m[6]) ||
        !zero(m[7]) ||
        !zero(m[8]) ||
        !zero(m[9]) ||
        !zero(m[11]) ||
        (m[15] - 1).abs() > epsilon) {
      return null;
    }
    final sx = m[0];
    final sy = m[5];
    if (sx <= 0 || (sx - sy).abs() > epsilon) {
      return null;
    }
    return sx;
  }

  /// How far [device] (a device-pixel coordinate) is from the NEAREST
  /// gridline — signed, and always in `[-0.5, 0.5]`.
  static double signedDistanceToGrid(double device) {
    final fraction = device - device.floorToDouble();
    return fraction > 0.5 ? fraction - 1.0 : fraction;
  }

  @override
  bool operator ==(Object other) =>
      other is RasterGridFit && other.shift == shift && other.scale == scale;

  @override
  int get hashCode => Object.hash(shift, scale);
}
