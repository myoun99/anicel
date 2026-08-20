import 'dart:ui' show DisplayFeature;

import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The app's UI scale: how large the CHROME draws, independent of the
/// monitor's own device-pixel ratio.
///
/// ## What it does and does not cover (유저 확정 2026-08-21)
///
/// It scales the chrome — toolbars, rails, panel strips, dialogs — and
/// **not the document views**: the canvas, the media viewer, the conte, the
/// cut envelope and the timesheet all keep their own zoom. The user drew
/// that line by KIND ("캔버스패널 베이스패널은 안 걸리는게 맞을거같아"),
/// not by "which surfaces happen to be rasters", so a new document panel
/// inherits the exclusion by being one rather than by being listed.
///
/// ## ⛔ It is a LADDER, not a slider
///
/// 유저 확정: "배율을 사다리로". Six stops clustered around 100 because that
/// is where a hand actually lands; a continuous control would multiply the
/// monitor ratio into an unbounded set of effective ratios, and every pin in
/// the quantization round would then assert about a grid nobody can
/// enumerate.
///
/// ## How it reaches the pixels
///
/// The scale multiplies into the ROOT DEVICE MATRIX (see
/// `AnicelBinding.createViewConfigurationFor`), so a logical pixel simply
/// becomes larger — nothing below has to know. That is also why
/// [EffectiveDevicePixelRatio] exists: once this is not 1.0,
/// `MediaQuery.devicePixelRatioOf` no longer answers "how many device pixels
/// is one logical pixel", and every site that quantizes has to read the
/// product instead.
class AppUiScale {
  const AppUiScale._();

  /// The stops, ascending. Tight around 100 (90/110) because that is the
  /// range a user reaches for to make one panel comfortable; wider steps
  /// further out, where the choice is "much bigger" rather than "a little".
  static const List<double> ladder = <double>[0.75, 0.9, 1.0, 1.1, 1.25, 1.5];

  static const double defaultScale = 1.0;

  /// The LIVE scale. App-wide rather than session-owned for the same reason
  /// the accents are: widgets holding no session read it, and it outlives
  /// any one project.
  ///
  /// Writing it is what changes the root matrix — `AnicelBinding` listens.
  static final ValueNotifier<double> value = ValueNotifier<double>(
    defaultScale,
  );

  /// The nearest ladder stop to [scale].
  ///
  /// ⚠️Anything that arrives from OUTSIDE the ladder comes through here: a
  /// settings file written by an older build, a hand-edited JSON, a future
  /// build with more stops. Returning it unchanged would let a value the UI
  /// cannot represent sit in the notifier, and the settings row would then
  /// show no stop as selected.
  static double snap(double scale) {
    if (!scale.isFinite || scale <= 0) {
      return defaultScale;
    }
    var best = ladder.first;
    var bestDistance = (scale - best).abs();
    for (final stop in ladder.skip(1)) {
      final distance = (scale - stop).abs();
      if (distance < bestDistance) {
        best = stop;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The stop [steps] away from the current one, clamped at both ends.
  static double stepped(double from, int steps) {
    final index = ladder.indexOf(snap(from));
    return ladder[(index + steps).clamp(0, ladder.length - 1)];
  }

  /// "125%" — the label, with no trailing `.0`.
  static String label(double scale) {
    final percent = scale * 100;
    final rounded = percent.roundToDouble();
    return (percent - rounded).abs() < 1e-9
        ? '${rounded.toInt()}%'
        : '${percent.toStringAsFixed(1)}%';
  }
}

/// The root view configuration for a display of [rawDevicePixelRatio],
/// rendered at [uiScale].
///
/// Pure, and separate from the binding, so the arithmetic can be pinned
/// without a `FlutterView` to fake.
///
/// 🚨**Both halves move together.** The device ratio goes UP by the scale
/// (each logical pixel covers more of the display) and the logical
/// constraints go DOWN by it (there are fewer logical pixels to lay out in).
/// Raising only the first would scale the chrome and then let it lay out in
/// the old, too-large logical box — the app would draw a window's worth of
/// UI off the edge of the window.
ViewConfiguration scaledViewConfiguration({
  required BoxConstraints physicalConstraints,
  required double rawDevicePixelRatio,
  required double uiScale,
}) {
  final safeRaw = rawDevicePixelRatio.isFinite && rawDevicePixelRatio > 0
      ? rawDevicePixelRatio
      : 1.0;
  final safeScale = uiScale.isFinite && uiScale > 0 ? uiScale : 1.0;
  final effective = safeRaw * safeScale;
  return ViewConfiguration(
    physicalConstraints: physicalConstraints,
    logicalConstraints: physicalConstraints / effective,
    devicePixelRatio: effective,
  );
}

/// [data] as seen by a subtree laid out at [uiScale].
///
/// ⛔**The binding override alone is not enough.** `MediaQuery` is built by
/// the `View` widget from the raw `FlutterView`, not from the
/// [ViewConfiguration] the binding hands the `RenderView` — so with the
/// override in place and this correction missing, `MediaQuery.sizeOf`
/// reports a logical size the child is never given. At 125% that is 25% too
/// wide, and everything sized from it — dialog widths, `SafeArea`'s insets,
/// the keyboard's `viewInsets` — is wrong by the same factor, silently.
///
/// Every LENGTH divides by the scale, because a length in logical pixels
/// shrinks when a logical pixel grows. The ratio is the one field that
/// multiplies.
MediaQueryData scaleMediaQueryData(MediaQueryData data, double uiScale) {
  if (!uiScale.isFinite || uiScale <= 0 || uiScale == 1.0) {
    return data;
  }
  return data.copyWith(
    size: data.size / uiScale,
    devicePixelRatio: data.devicePixelRatio * uiScale,
    padding: data.padding / uiScale,
    viewPadding: data.viewPadding / uiScale,
    viewInsets: data.viewInsets / uiScale,
    systemGestureInsets: data.systemGestureInsets / uiScale,
    // ⚠️`touchSlop` is a LENGTH too — `MediaQueryData.fromView` computes it
    // as `physicalTouchSlop / rawRatio`, so leaving it alone makes every
    // drag threshold grow physically with the scale: at 150% on a 2x
    // tablet a drag would have to travel 36 physical px instead of 24
    // before any recognizer accepts, which is further than every other app
    // on the device. `panSlop` is derived from it and follows.
    gestureSettings: data.gestureSettings.touchSlop == null
        ? data.gestureSettings
        : DeviceGestureSettings(
            touchSlop: data.gestureSettings.touchSlop! / uiScale,
          ),
    // Foldables: a hinge's bounds are logical pixels like everything else.
    // Cheap to carry and impossible to notice missing until an app runs on
    // the one device that has one.
    displayFeatures: data.displayFeatures
        .map(
          (feature) => DisplayFeature(
            bounds: Rect.fromLTRB(
              feature.bounds.left / uiScale,
              feature.bounds.top / uiScale,
              feature.bounds.right / uiScale,
              feature.bounds.bottom / uiScale,
            ),
            type: feature.type,
            state: feature.state,
          ),
        )
        .toList(growable: false),
  );
}
