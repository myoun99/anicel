import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Parks its child's compositing layer on the device-pixel grid.
///
/// Skia's picture raster cache (desktop Skia — Impeller carries no such
/// cache) snaps a STABLE picture's CTM to an integral device translation
/// and replays the cached raster there, while live repaints render at the
/// fractional offset the panel layout actually produced. The flip between
/// those two renders hopped axis-aligned edges by 1px at every
/// engage/disengage moment — pen-down, pen-up, layer switch, a tool
/// button — device-confirmed 2026-08-17.
///
/// ⛔No in-picture transform can close that gap: the cache replays the
/// SAME picture at the snapped CTM, so a compensation recorded inside the
/// picture is replayed snapped too — it contradicts itself. (#1101's
/// in-picture pan snap is a different phenomenon — pan jitter from our own
/// fractional-phase blits — and stays.) The only coordinate the cached and
/// the live render can be made to agree on is the layer's own device
/// offset: hold it integral and the snap is a no-op.
///
/// Mechanism: after every rendered frame this widget measures its own
/// accumulated paint transform to the root — a post-frame callback,
/// because ancestors can move this subtree without ever rebuilding it —
/// takes the fractional part of translation × devicePixelRatio, and
/// applies the negation as a tiny `Transform.translate` (≤ half a device
/// pixel per axis). A pure translation pushes no layer of its own; it
/// merely shifts where the child's `RepaintBoundary` lays its layer down,
/// which is exactly the offset the raster cache keys on. ⚠️The child MUST
/// therefore carry a `RepaintBoundary` at its top: below a boundary the
/// shift would be recorded in-picture, which the paragraph above proves
/// useless.
///
/// ⚠️One-frame honesty: the frame right AFTER a layout change still paints
/// with the previous compensation, so the layer can sit fractional for
/// that single frame. That frame is a raster-cache miss anyway — the
/// picture or its position just changed — so what appears is the live
/// render, internally consistent; the correction lands with the next
/// frame and costs a re-composite, not a re-record (the boundary's layer
/// is reused at the new offset).
///
/// ⛔Gate: the panel chrome above the canvas is axis-aligned. Under an
/// ancestor rotation or scale "one device pixel" stops being one
/// direction and the measurement would be a guess — the widget then
/// applies NO compensation (fail open) rather than a wrong one.
///
/// Hit tests ride the same transform (`transformHitTests: true`), so the
/// pointer and the pixels disagree with the untransformed chrome by at
/// most half a device pixel — and never with each other.
class IntegralLayerOffset extends StatefulWidget {
  const IntegralLayerOffset({super.key, required this.child});

  final Widget child;

  @override
  State<IntegralLayerOffset> createState() => _IntegralLayerOffsetState();
}

class _IntegralLayerOffsetState extends State<IntegralLayerOffset> {
  /// The current correction, in LOGICAL pixels (the fractional device-part
  /// divided back by the ratio). Zero until the first post-frame
  /// measurement, and zero under a non-axis-aligned ancestor.
  Offset _compensation = Offset.zero;

  /// The ratio the last build saw. Captured in [build] so the MediaQuery
  /// subscription re-runs the build on a monitor move, and read by the
  /// measurement instead of a raw `PlatformDispatcher` singleton (which
  /// neither tracks moves nor answers per view).
  double _devicePixelRatio = 1.0;

  bool _measurementArmed = false;

  @override
  void initState() {
    super.initState();
    _armMeasurement();
  }

  void _armMeasurement() {
    if (_measurementArmed) {
      return;
    }
    _measurementArmed = true;
    // ⚠️A post-frame callback does NOT schedule a frame — this chain rides
    // frames something else already paid for, so an idle canvas costs
    // nothing here. It re-arms itself because the question it answers
    // ("where did layout put me") can change on any frame without this
    // widget rebuilding.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measurementArmed = false;
      if (!mounted) {
        return;
      }
      _measure();
      _armMeasurement();
    });
  }

  void _measure() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    // ⚠️Measured on THIS render object, whose own transform is excluded
    // from getTransformTo — so the reading never contains the correction
    // it feeds, and the loop settles in one step instead of chasing
    // itself.
    final transform = box.getTransformTo(null);
    var next = Offset.zero;
    if (_isAxisAlignedTranslation(transform)) {
      final dpr = _devicePixelRatio;
      final deviceX = transform.storage[12] * dpr;
      final deviceY = transform.storage[13] * dpr;
      next = Offset(
        -(deviceX - deviceX.roundToDouble()) / dpr,
        -(deviceY - deviceY.roundToDouble()) / dpr,
      );
    }
    // Tolerance in DEVICE pixels: below a thousandth of one, no snap
    // mismatch is visible and a setState would only churn frames.
    if (((next - _compensation) * _devicePixelRatio).distance > 1e-3) {
      setState(() => _compensation = next);
    }
  }

  /// True when the accumulated transform moves this subtree without
  /// rotating, scaling or perspecting it — the only geometry in which
  /// "round the translation to device pixels" is well-defined.
  static bool _isAxisAlignedTranslation(Matrix4 transform) {
    const eps = 1e-6;
    final s = transform.storage;
    return (s[0] - 1).abs() < eps &&
        (s[5] - 1).abs() < eps &&
        s[1].abs() < eps &&
        s[4].abs() < eps &&
        s[3].abs() < eps &&
        s[7].abs() < eps &&
        (s[15] - 1).abs() < eps;
  }

  @override
  Widget build(BuildContext context) {
    _devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return Transform.translate(
      offset: _compensation,
      transformHitTests: true,
      child: widget.child,
    );
  }
}
