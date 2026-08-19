import 'package:flutter/widgets.dart';

import '../effective_device_pixel_ratio.dart';

/// The DEVICE-pixel grid a chrome boundary is placed on.
///
/// 🚨★★★ THE FORM IS A TOP-DOWN INVARIANT, NOT A MEASUREMENT. Flutter
/// cannot answer "where am I on screen" during layout: inside its own
/// `performLayout` a RenderBox's `getTransformTo(null)` reads tx = 0.0
/// while the settled truth is 10.3, and an offset-only ancestor change
/// moves a child from 10.3 to 40.7 with `performLayout` NEVER running
/// again — only `paint()` re-runs, at a new offset. A child is not one
/// frame late about its position; it is never woken when its position
/// changes (measured 2026-08-19). ⛔So nothing here may ask for a global
/// position, and nothing does.
///
/// What holds instead: `RenderView` installs a PURE SCALE with no
/// translation, so the root child's origin is exactly on the grid. If
/// every offset the app chooses below it is an integral count of device
/// pixels, every descendant origin is on the grid BY CONSTRUCTION, with
/// nothing measured. Each method here takes a distance from an anchor
/// that is ALREADY on the grid — your own box's top-left — and returns an
/// on-grid distance.
///
/// ⛔There is no `origin` and no `phase` field, deliberately. A phase
/// nobody can compute without measuring is decorative: it would read zero
/// for ever while an unquantized ancestor offset silently put the whole
/// subtree between two device columns. The rule that replaces it is
/// mechanical — **every expression that establishes a new local origin
/// goes through [position] at the site where it is written**.
@immutable
class DeviceGrid {
  const DeviceGrid(this.ratio);

  /// The EFFECTIVE ratio (monitor × UI scale) — the number the ROOT MATRIX
  /// uses. ⛔Never `MediaQuery.devicePixelRatioOf`: it keeps reporting the
  /// monitor's raw ratio while the compositor works on the product, so a
  /// grid built from it is not the grid anything lands on.
  factory DeviceGrid.of(BuildContext context) =>
      DeviceGrid(EffectiveDevicePixelRatio.of(context));

  final double ratio;

  bool get _usable => ratio.isFinite && ratio > 0;

  /// ⚠️NOT slop. `48 * 1.25` can arrive as 59.99999999999999 and floor to
  /// 59 — a quantizer that moves an already-correct constant by a whole
  /// device pixel is worse than none. It is also what makes [position]
  /// IDEMPOTENT: `position(x) * ratio` is an integer only to within an ulp
  /// or two, and `floor` would amplify a 1-ulp deficit into a whole pixel
  /// on the second pass.
  static const double _epsilon = 1e-6;

  /// The largest on-grid logical position at or before [logical].
  ///
  /// FLOOR, not round: flooring cumulative positions lands three 800/3
  /// columns at device 0/333/666/1000 exactly and their widths sum to
  /// exactly 800.0 logical (measured at DPR 1.25). Floor is also monotone
  /// — a run can never overshoot its parent — and never overshooting is
  /// what keeps a row from overflowing by half a device pixel.
  ///
  /// ★Composes exactly: for an already-snapped `a`, `position(a + b)`
  /// equals `a + position(b)`, because `floor(int + x) == int + floor(x)`.
  /// So a nested origin snapped against its parent's snapped origin
  /// carries ONE rounding for the whole chain, not one per level.
  double position(double logical) {
    if (!_usable || !logical.isFinite) {
      return logical;
    }
    return ((logical * ratio) + _epsilon).floorToDouble() / ratio;
  }

  /// A cumulative run of adjacent extents along one axis, anchored at
  /// [from] — a distance from this box's own top-left, which the invariant
  /// says is already on the grid.
  DeviceGridRun run({double from = 0}) => DeviceGridRun(this, from);

  /// Debug/test predicate. Tolerance is in DEVICE pixels.
  bool isOnGrid(double logical) {
    if (!_usable) {
      return true;
    }
    final device = logical * ratio;
    return (device - device.roundToDouble()).abs() < 1e-3;
  }

  @override
  bool operator ==(Object other) => other is DeviceGrid && other.ratio == ratio;

  @override
  int get hashCode => ratio.hashCode;

  @override
  String toString() => 'DeviceGrid($ratio)';
}

/// A cumulative run of adjacent extents: floor each cumulative POSITION,
/// and take each extent as the DIFFERENCE OF NEIGHBOURS.
///
/// ⛔NEVER round an extent on its own. That is the bug wearing this fix's
/// clothes: three 333.33 widths each rounded independently sum to 999, and
/// the last boundary walks a whole pixel off the parent — every frame, in
/// the same direction. A run of n extents carries ONE rounding for the
/// whole run however long it is.
///
/// ⛔And never two runs over the same boundary. A splitter's thickness is
/// a SPAN BETWEEN TWO BOUNDARIES; quantizing it a second time as a
/// standalone thickness makes a region's cover and the region's own edge
/// disagree by a device pixel at a large fraction of drag positions.
class DeviceGridRun {
  DeviceGridRun(this._grid, double from)
    : _raw = from,
      _snapped = _grid.position(from);

  final DeviceGrid _grid;
  double _raw;
  double _snapped;

  /// The on-grid boundary the run has reached.
  double get position => _snapped;

  /// Advances by [extent] and returns the ON-GRID extent to hand a
  /// `Positioned`/`SizedBox` — the snapped position after, minus before.
  double take(double extent) {
    _raw += extent;
    final next = _grid.position(_raw);
    final used = next - _snapped;
    _snapped = next;
    return used;
  }
}
