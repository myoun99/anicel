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
  /// ⚠️A ratio that cannot describe a grid — zero, negative, NaN, infinite —
  /// is normalised to 0 rather than stored. Two reasons, both measured:
  /// a stored NaN makes `==` NON-REFLEXIVE while the hash codes still
  /// collide, and this class is read in `shouldRepaint` /
  /// `updateShouldNotify`, where "never equal to itself" pins *changed*
  /// for ever; and an infinite ratio would sail through a `> 0` gate and
  /// produce infinities downstream. The comparison form is deliberate —
  /// `.isFinite` is not a constant expression, so it cannot run here.
  const DeviceGrid(double ratio)
    : ratio = ratio > 0 && ratio < double.infinity ? ratio : 0;

  /// The EFFECTIVE ratio (monitor × UI scale) — the number the ROOT MATRIX
  /// uses. ⛔Never `MediaQuery.devicePixelRatioOf`: it keeps reporting the
  /// monitor's raw ratio while the compositor works on the product, so a
  /// grid built from it is not the grid anything lands on.
  factory DeviceGrid.of(BuildContext context) =>
      DeviceGrid(EffectiveDevicePixelRatio.of(context));

  final double ratio;

  /// Whether this grid quantizes at all. A degenerate ratio makes every
  /// method the identity and [isOnGrid] vacuously TRUE, so anything that
  /// AUDITS or GATES on the grid must ask this FIRST — otherwise it
  /// reports a perfect grid on a broken ratio.
  bool get isActive => ratio > 0;

  /// One double ulp. The slack in [position] is a MULTIPLE OF THIS times
  /// the coordinate, never a constant.
  ///
  /// ⚠️Slack is not slop. The effective ratio is a computed product
  /// (monitor × UI scale) and is itself inexact: at
  /// `1.5 * 0.7 == 1.0499999999999998`, `20 * ratio` arrives as
  /// 20.999999999999996 and a bare floor moves a correct 20 by a WHOLE
  /// device pixel. It is also what makes [position] idempotent, since
  /// `position(x) * ratio` is an integer only to within an ulp or two.
  ///
  /// ⛔`48 * 1.25` is NOT such a case, and an earlier draft of this file
  /// said it was. 48 and 1.25 are both dyadic, so the product is exactly
  /// 60.0 — every integer × dyadic-ratio product is exact. The deficits
  /// are real only at PRODUCT ratios, which is precisely what a UI scale
  /// creates and why this matters now rather than before.
  ///
  /// ⛔A FIXED epsilon cannot do this job, in either direction, and both
  /// directions were measured. The error absorbed is RELATIVE, so a
  /// constant large enough at a coordinate of 1e6 is millions of times
  /// larger than the ulp at a coordinate of 100 — and all of that excess
  /// is OVERSHOOT. The 1e-6 this file shipped first overshot by up to
  /// 1e-6 device px, four orders above Flutter's `precisionErrorTolerance`
  /// of 1e-10, and a `Row` built from a run reported `overflowed by
  /// 3.20e-7 pixels`. Shrinking it to 1e-9 fails the other way:
  /// idempotence breaks by a full device pixel around coordinate 1e6,
  /// which scroll offsets reach.
  static const double _ulp = 2.220446049250313e-16;

  /// How many ulps of the coordinate the slack spans. Eight is empirical:
  /// it rescues every product-ratio deficit measured across the real
  /// ladder × monitor matrix, with zero overshoots in 2.4M samples and
  /// zero idempotence failures at magnitude 1e9.
  static const double _slackUlps = 8;

  /// The largest on-grid logical position at or before [logical].
  ///
  /// FLOOR, not round: flooring cumulative positions lands three 800/3
  /// columns at device 0/333/666/1000 exactly and their widths sum to
  /// exactly 800.0 logical (measured at DPR 1.25). Floor is monotone, so a
  /// run can never overshoot its parent by anything anyone can see — which
  /// is what keeps a row from overflowing by half a device pixel.
  ///
  /// ⚠️Monotone, but not to the last bit. The slack can carry a result up
  /// to `_slackUlps · ulp · x` ABOVE its input (~2e-15 relative). Some
  /// overshoot is unavoidable — the alternative is moving a correct
  /// constant by a whole device pixel — so the rule is to keep it as small
  /// as the arithmetic allows, which is what a relative slack does. It
  /// stays under Flutter's `precisionErrorTolerance` (1e-10) for any
  /// coordinate the UI actually uses.
  ///
  /// ★Composes: for an already-snapped `a`, `position(a + b)` equals
  /// `a + position(b)`, because `floor(int + x) == int + floor(x)`. So
  /// snapping a nested origin against its parent's snapped origin adds NO
  /// rounding beyond the one [position] at its own site. ⚠️That does not
  /// make a deep chain free: n levels each snapping their own local offset
  /// carry n roundings. When adjacent extents must sum EXACTLY, one
  /// [DeviceGridRun] is what carries one rounding however long it is.
  double position(double logical) {
    if (!isActive || !logical.isFinite) {
      return logical;
    }
    final device = logical * ratio;
    final slack = _slackUlps * _ulp * device.abs();
    return (device + slack).floorToDouble() / ratio;
  }

  /// A cumulative run of adjacent extents along one axis, anchored at
  /// [from] — a distance from this box's own top-left, which the invariant
  /// says is already on the grid.
  ///
  /// The assert is the invariant's only tripwire. Nothing inside a run can
  /// notice that its anchor was off-grid: `run(from: 10.3)` at ratio 1.25
  /// reports a position of 9.6 — the whole subtree shifted 0.875 device px
  /// — while the first `take(48)` still returns exactly 48.0, so every
  /// number at the call site looks right. Measured across 120,000
  /// legitimate anchors (outputs of [position], sums of snapped pieces,
  /// live run positions, and 0) it never fires.
  DeviceGridRun run({double from = 0}) {
    assert(
      !isActive || !from.isFinite || isOnGrid(from),
      'DeviceGridRun anchored at an OFF-GRID position ($from at ratio '
      '$ratio). The run will be correct relative to that anchor and wrong '
      'relative to the window, and nothing downstream can tell. Snap the '
      'anchor at the site that produced it.',
    );
    return DeviceGridRun(this, from);
  }

  /// Debug/test predicate. Tolerance is in DEVICE pixels.
  ///
  /// ⚠️Vacuously TRUE on an inactive grid — ask [isActive] first when this
  /// is used to audit or to gate.
  bool isOnGrid(double logical) {
    if (!isActive) {
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
  ///
  /// ⚠️A non-finite [extent] is REFUSED rather than accumulated. Letting
  /// one in poisons `_raw` permanently — measured, a run fed
  /// `[120, infinity, 40, 40]` returns `[120, Infinity, NaN, NaN]` and
  /// never recovers — and `take(constraints.maxWidth)` under an unbounded
  /// parent is an ordinary spelling, so this is reachable by accident.
  /// The symptom would surface in a sibling's `BoxConstraints`, nowhere
  /// near the call that caused it.
  ///
  /// ⚠️An extent smaller than one device pixel legitimately returns 0.0 on
  /// some calls and a whole device pixel on others. That is the cumulative
  /// rule working, not a bug: it is how a row of sub-pixel items lands
  /// exactly on its parent instead of drifting. A caller that cannot cope
  /// with a zero extent should not be quantizing that axis.
  double take(double extent) {
    assert(
      extent.isFinite,
      'DeviceGridRun.take($extent): a non-finite extent would poison the '
      'run permanently. Clamp unbounded constraints before quantizing.',
    );
    // ⛔The guard is on the RESULT, not on the argument, and that is not a
    // stylistic choice. Guarding the argument leaves the branch dead in
    // debug — the assert above fires first — so it could never be pinned,
    // and it would still miss the case where every individual extent is
    // finite and their SUM overflows. Guarding here covers both, and the
    // overflow case is reachable in debug, so a test can hold it.
    final nextRaw = _raw + extent;
    if (!nextRaw.isFinite) {
      return 0;
    }
    _raw = nextRaw;
    final next = _grid.position(_raw);
    final used = next - _snapped;
    _snapped = next;
    return used;
  }
}
