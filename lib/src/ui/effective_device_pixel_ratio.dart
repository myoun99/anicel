import 'package:flutter/widgets.dart';

/// The device-pixel ratio the ROOT TRANSFORM actually uses: the monitor's
/// ratio multiplied by the app's UI scale.
///
/// ⛔`MediaQuery.devicePixelRatioOf` is NOT that number once a UI scale is
/// in force, and the difference is silent. The hook that owns the root
/// device matrix is `RendererBinding.createViewConfigurationFor`; a probe
/// overriding it measured `MediaQuery` and `View.of` still reporting the
/// raw 1.25 while the real root transform carried the 1.125 product. Every
/// site that turns logical units into DEVICE pixels — raster sizes, grid
/// snaps, hairline widths, the pan-phase snap — has to read this instead,
/// or it sizes against a grid the compositor is not using.
///
/// MediaQuery stays the right source for "how big is a logical pixel on
/// this HARDWARE" — a question the UI scale does not change. [AppInput]'s
/// small-form-factor test is the one such caller today.
///
/// Absent a scope this falls back to MediaQuery (then `View`), so widget
/// tests and any subtree built outside the app shell keep working. In the
/// running app the scope is mounted once, from `MaterialApp.builder`.
class EffectiveDevicePixelRatio extends InheritedWidget {
  const EffectiveDevicePixelRatio({
    super.key,
    required this.ratio,
    required super.child,
  });

  final double ratio;

  /// The effective ratio for [context] — the scope's value, or the raw
  /// view ratio when no scope is mounted.
  static double of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EffectiveDevicePixelRatio>();
    if (scope != null) {
      return scope.ratio;
    }
    return rawViewRatioOf(context);
  }

  /// The HARDWARE ratio, ignoring any UI scale. Only for questions about
  /// the physical display itself.
  static double rawViewRatioOf(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.of(context).devicePixelRatio;

  @override
  bool updateShouldNotify(EffectiveDevicePixelRatio oldWidget) =>
      ratio != oldWidget.ratio;
}

/// Mounts [EffectiveDevicePixelRatio] as `monitor ratio × uiScale`.
///
/// It multiplies rather than reading the root matrix back because the two
/// factors stay independent: the override below changes the matrix without
/// moving MediaQuery, so `raw × scale` remains the product whether or not
/// a scale is installed. That is what lets this widget stay unchanged when
/// the scale becomes real.
class EffectiveDevicePixelRatioScope extends StatelessWidget {
  const EffectiveDevicePixelRatioScope({
    super.key,
    this.uiScale = 1.0,
    required this.child,
  });

  final double uiScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The ratio is a DIVISOR downstream — the pan-phase snap divides by it
    // (`viewport_canvas_transform.dart`) and so does the integral-offset
    // compensation. A zero or NaN scale would not degrade the grid, it
    // would produce infinities in every snapped coordinate, so the value
    // is refused here rather than at each of those sites.
    assert(
      uiScale.isFinite && uiScale > 0,
      'uiScale must be finite and positive, got $uiScale',
    );
    final scale = uiScale.isFinite && uiScale > 0 ? uiScale : 1.0;
    return EffectiveDevicePixelRatio(
      ratio: EffectiveDevicePixelRatio.rawViewRatioOf(context) * scale,
      child: child,
    );
  }
}
