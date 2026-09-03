import 'dart:ui' show DisplayFeature;

import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

export '../models/app_ui_scale.dart';

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
