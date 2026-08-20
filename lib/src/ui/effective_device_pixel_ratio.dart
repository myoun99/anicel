import 'package:flutter/widgets.dart';

import 'ui_scale.dart';

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
/// For "how big is a logical pixel on this HARDWARE" — a question the UI
/// scale does not change — read the `FlutterView` directly, as the
/// small-form-factor test in `app_input_settings.dart` does. ⛔Not
/// [rawViewRatioOf]: that reads the AMBIENT MediaQuery, which the scope
/// below rewrites, so it answers the hardware question only ABOVE the
/// scope. It stays that way on purpose — it is the scope's own input, and
/// widget tests set a ratio by wrapping in a `MediaQuery`.
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

/// Mounts [EffectiveDevicePixelRatio] as `monitor ratio × uiScale`, and the
/// MediaQuery that matches it.
///
/// It multiplies rather than reading the root matrix back because the two
/// factors stay independent: `AnicelBinding` changes the matrix without
/// moving the `FlutterView` MediaQuery is built from, so `raw × scale`
/// remains the product whether or not a scale is installed.
///
/// 🚨**This is the widget half of the UI scale, and it is not optional.**
/// The binding scales the root matrix and shrinks the logical constraints;
/// `MediaQuery` comes from the raw `FlutterView` and follows neither. With
/// the binding override alone, `MediaQuery.sizeOf` at 125% reports a box
/// 25% wider than the one the child is actually laid out in — and so do the
/// paddings `SafeArea` reads and the `viewInsets` a keyboard raises. The
/// correction is [scaleMediaQueryData]; it lives here so there is exactly
/// one place where the two halves can drift apart.
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
    // ⛔Read BEFORE the corrected MediaQuery is mounted — this is the raw
    // ambient one, and the product is built from it exactly once.
    final ratio = EffectiveDevicePixelRatio.rawViewRatioOf(context) * scale;
    Widget scoped = EffectiveDevicePixelRatio(ratio: ratio, child: child);
    final ambient = MediaQuery.maybeOf(context);
    if (ambient != null) {
      // ⛔NOT `if (scale != 1.0)`. Mounting the MediaQuery conditionally
      // changes the widget TYPE at this slot, so the first move off 100%
      // would deactivate the element below it — which here is the whole
      // app: every session, canvas, controller and focus node. At 1.0
      // `scaleMediaQueryData` returns the ambient data unchanged, so an
      // always-mounted MediaQuery costs one identical inherited widget and
      // notifies nobody. (Same law as `DeviceGridScrollBody`'s always-on
      // `Transform`.)
      scoped = MediaQuery(
        data: scaleMediaQueryData(ambient, scale),
        child: scoped,
      );
    }
    return scoped;
  }
}
