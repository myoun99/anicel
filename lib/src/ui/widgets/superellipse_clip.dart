import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Clips to the app's superellipse WITHOUT building a `Path` for it.
///
/// ## Why not `ClipPath`
///
/// `ClipPath` is what this app used, through `ShapeBorderClipper`, and it
/// is correct — but `PaintingContext.pushClipPath` does `clipPath.shift(
/// offset)`, which allocates a BRAND NEW `Path` object on every paint.
/// A path carries a generation id, and the engine's clip-mask cache is
/// keyed on it, so a fresh object misses every single frame. A
/// superellipse is not a cheap outline to re-mask: it is a long run of
/// curve segments, and the app clips one per open rail group, one per
/// visible tab, one per floating region, plus three on the canvas
/// surfaces.
///
/// `pushClipRSuperellipse` takes an [ui.RSuperellipse] VALUE instead —
/// four numbers and a rect, stable frame to frame, and the engine gets to
/// treat the shape as the primitive it is.
///
/// ## Why not the `ClipRSuperellipse` widget
///
/// Because of hit testing, and that ban stands: `RenderClipRSuperellipse
/// .hitTest` asks only `outerRect.contains(position)`, so the four
/// corners it visibly cuts away still swallow pointers — a floating panel
/// drawn that way eats strokes in a square of empty canvas at each
/// corner. `AppShapes` says so, and it is right.
///
/// The ban is on the WIDGET, not on the engine operation. This asks
/// [ui.RSuperellipse.contains], which is exact, so the cut corner is
/// genuinely not there for a pointer either. That is the one thing
/// `ClipPath` was buying, and it is kept.
///
/// ## Not inside a still region
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2: 「그림 안의
/// 자르기를 『자르지 않고 그 모양으로 칠하는』 그리기로 다시 짠다」): on the
/// device a superellipse clip is multisampled, and the image a still region
/// takes of it parts from the screen by 50~51/255 at its rim — a value bar's
/// by 56~57 — where the shape FILLED by its formula parts by 5~7 and an
/// axis-aligned rectangle's clip by 0 (🔬the Surface's edge probe, 11-08
/// 04:40: `rse-clip` · `field` · `rse-fill` · `clip-blocks`). So what a
/// region drawn as an image holds is not clipped to the shape: what lies
/// inside it is left alone, and what reaches its corners fills the shape
/// itself, cut by a rectangle where it must be cut. A region that is
/// always live — a dialog, a popup, a floating panel's body over arbitrary
/// content — may clip.
class SuperellipseClip extends SuperellipseHit {
  const SuperellipseClip({super.key, required super.shape, super.child});

  @override
  RenderSuperellipseClip createRenderObject(BuildContext context) =>
      RenderSuperellipseClip(borderRadius: borderRadiusIn(context));
}

/// The app's superellipse to a POINTER, as [SuperellipseClip] is — a press
/// on a corner it cuts away misses — without clipping what it holds: for
/// what a still region holds, which is not clipped (above).
class SuperellipseHit extends SingleChildRenderObjectWidget {
  const SuperellipseHit({super.key, required this.shape, super.child});

  /// The shape — always one of `AppShapes`', so the silhouette stays the
  /// app's and this widget never invents a corner.
  final RoundedSuperellipseBorder shape;

  /// [shape]'s corners where [context] reads — what the render object is
  /// handed, by this widget and by one that stands in it as it does.
  BorderRadius borderRadiusIn(BuildContext context) => shape.borderRadius
      .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);

  @override
  RenderSuperellipseHit createRenderObject(BuildContext context) =>
      RenderSuperellipseHit(borderRadius: borderRadiusIn(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSuperellipseHit renderObject,
  ) {
    renderObject.borderRadius = borderRadiusIn(context);
  }
}

class RenderSuperellipseHit extends RenderProxyBox {
  RenderSuperellipseHit({required BorderRadius borderRadius})
    : _borderRadius = borderRadius;

  BorderRadius _borderRadius;
  BorderRadius get borderRadius => _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) {
      return;
    }
    _borderRadius = value;
    markNeedsPaint();
  }

  /// The shape over this box.
  ui.RSuperellipse get shape =>
      _borderRadius.toRSuperellipse(Offset.zero & size);

  /// The exact silhouette, which is the whole reason this is not the
  /// stock `ClipRSuperellipse`: a pointer in a cut corner must MISS.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!shape.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<BorderRadius>('radius', _borderRadius));
  }
}

class RenderSuperellipseClip extends RenderSuperellipseHit {
  RenderSuperellipseClip({required super.borderRadius});

  final LayerHandle<ClipRSuperellipseLayer> _clipLayer =
      LayerHandle<ClipRSuperellipseLayer>();

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      Offset.zero & size;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      _clipLayer.layer = null;
      return;
    }
    _clipLayer.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      Offset.zero & size,
      shape,
      super.paint,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }
}

/// What reaches a superellipse's corner in a still region, drawn as the
/// shape itself (Not inside a still region, [SuperellipseClip]).
extension SuperellipseCut on Canvas {
  /// [shape] filled with [paint] where [cut] lies — its corner drawn by its
  /// formula, the cut by an axis-aligned rectangle: a rectangle within the
  /// shape is drawn as itself, one the shape lies within is the shape, and
  /// an empty one is nothing.
  ///
  /// ⛔The cut's clip is HARD-edged: that is the rectangle's clip the probe
  /// measured at 0 (`clip-blocks`, a `ClipRect`'s own edge, at every
  /// fraction of a device pixel).
  void drawRSuperellipseCut(ui.RSuperellipse shape, Rect cut, Paint paint) {
    final box = shape.outerRect;
    if (cut.isEmpty) {
      return;
    } else if (cut.left <= box.left &&
        cut.top <= box.top &&
        cut.right >= box.right &&
        cut.bottom >= box.bottom) {
      drawRSuperellipse(shape, paint);
    } else if ([
      cut.topLeft,
      cut.topRight,
      cut.bottomLeft,
      cut.bottomRight,
    ].every(shape.contains)) {
      drawRect(cut, paint);
    } else {
      save();
      clipRect(cut, doAntiAlias: false);
      drawRSuperellipse(shape, paint);
      restore();
    }
  }
}
