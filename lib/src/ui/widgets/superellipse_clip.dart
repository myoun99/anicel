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
class SuperellipseClip extends SingleChildRenderObjectWidget {
  const SuperellipseClip({
    super.key,
    required this.shape,
    this.clipBehavior = Clip.antiAlias,
    super.child,
  });

  /// The shape to clip to — always one of `AppShapes`', so the silhouette
  /// stays the app's and this widget never invents a corner.
  final RoundedSuperellipseBorder shape;

  final Clip clipBehavior;

  BorderRadius _radiusOf(BuildContext context) => shape.borderRadius.resolve(
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );

  @override
  RenderSuperellipseClip createRenderObject(BuildContext context) {
    return RenderSuperellipseClip(
      borderRadius: _radiusOf(context),
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSuperellipseClip renderObject,
  ) {
    renderObject
      ..borderRadius = _radiusOf(context)
      ..clipBehavior = clipBehavior;
  }
}

class RenderSuperellipseClip extends RenderProxyBox {
  RenderSuperellipseClip({
    required BorderRadius borderRadius,
    required Clip clipBehavior,
  }) : _borderRadius = borderRadius,
       _clipBehavior = clipBehavior;

  BorderRadius _borderRadius;
  BorderRadius get borderRadius => _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) {
      return;
    }
    _borderRadius = value;
    markNeedsPaint();
  }

  Clip _clipBehavior;
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (_clipBehavior == value) {
      return;
    }
    _clipBehavior = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRSuperellipseLayer> _clipLayer =
      LayerHandle<ClipRSuperellipseLayer>();

  ui.RSuperellipse get _shape =>
      _borderRadius.toRSuperellipse(Offset.zero & size);

  /// The exact silhouette, which is the whole reason this is not the
  /// stock `ClipRSuperellipse`: a pointer in a cut corner must MISS.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_clipBehavior != Clip.none && !_shape.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipBehavior == Clip.none ? null : Offset.zero & size;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _clipBehavior == Clip.none) {
      _clipLayer.layer = null;
      if (child != null) {
        super.paint(context, offset);
      }
      return;
    }
    _clipLayer.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      Offset.zero & size,
      _shape,
      super.paint,
      clipBehavior: _clipBehavior,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<BorderRadius>('radius', _borderRadius));
    properties.add(EnumProperty<Clip>('clipBehavior', _clipBehavior));
  }
}
