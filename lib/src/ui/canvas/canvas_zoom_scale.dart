import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import '../../models/viewport_point.dart';
import '../effective_device_pixel_ratio.dart';

/// The two units a document view's zoom is spoken in, and the one number
/// that converts between them.
///
/// ## The convention (유저 확정 2026-08-21)
///
/// **100% means one artwork pixel per DEVICE pixel** — the Photoshop /
/// Clip Studio / Krita convention, which the user chose explicitly
/// ("맞추는쪽으로") after asking what the other tools do. So the zoom a
/// user reads, types and drags is measured in DEVICE pixels per artwork
/// pixel, while [CanvasViewport.zoom] stays what every painter and every
/// hit test needs: LOGICAL pixels per artwork pixel.
///
///     render = display / effectiveRatio
///
/// ## The same division also excludes document views from the UI scale
///
/// The user drew the scale's boundary by KIND: the chrome scales, the
/// document views do not — "캔버스패널 베이스패널은 안 걸리는게
/// 맞을거같아", naming the canvas, the media viewer, the conte, the cut
/// envelope and the timesheet. Because the UI scale multiplies into the
/// effective ratio, one division answers both requirements at once: raise
/// the scale and the render zoom drops by exactly the factor the root
/// matrix just gained, so the artwork covers the same device pixels it
/// did before.
///
/// ⛔That is why there is no second, separate "is this panel excluded?"
/// flag. A document view is excluded by asking for its zoom in display
/// units; a chrome surface never asks at all.
@immutable
class CanvasZoomScale {
  const CanvasZoomScale(double effectiveRatio)
    // Normalized in the constructor, like [DeviceGrid], so `==` stays
    // reflexive (NaN != NaN) and no consumer divides by zero.
    : ratio = effectiveRatio > 0 && effectiveRatio < double.infinity
          ? effectiveRatio
          : 1.0;

  /// The effective device-pixel ratio: monitor × UI scale.
  final double ratio;

  /// The scale in force for [context] — the same source every quantizer
  /// reads. ⛔Not `MediaQuery`, which reports the monitor's raw ratio and
  /// would leave a scaled UI showing a zoom percentage that means nothing.
  static CanvasZoomScale of(BuildContext context) =>
      CanvasZoomScale(EffectiveDevicePixelRatio.of(context));

  /// What the readout shows for [renderZoom] — device pixels per artwork
  /// pixel.
  double display(double renderZoom) => renderZoom * ratio;

  /// The viewport zoom that renders [displayZoom].
  double render(double displayZoom) => displayZoom / ratio;

  /// The user-facing zoom range, as the readout has always advertised it:
  /// 10% to 1600%, in DEVICE pixels per artwork pixel.
  ///
  /// 🚨It lives here rather than on [CanvasViewport] because it is a
  /// DISPLAY-unit limit, and the render zoom that reaches it moves with the
  /// effective ratio. The model's own `minZoom`/`maxZoom` stayed behind as
  /// a wide sanity rail — if that rail is ever the binding one again, the
  /// exclusion breaks silently at the ends of the range.
  static const double minDisplayZoom = 0.1;
  static const double maxDisplayZoom = 16.0;

  /// [renderZoom] clamped to the advertised range.
  ///
  /// Every absolute zoom verb goes through this — the ± buttons, the
  /// readout's drag, a typed percentage — so all three stop at the same
  /// number the label promises.
  double clampRender(double renderZoom) => renderZoom.clamp(
    render(minDisplayZoom),
    render(maxDisplayZoom),
  );

  /// The identity view: artwork 1px = device 1px, whatever the monitor and
  /// the UI scale are.
  ///
  /// This is what "reset" means now. ⛔It is NOT `CanvasViewport()`: a bare
  /// 1.0 is one artwork pixel per LOGICAL pixel, which on a 1.5 display put
  /// the artwork at 150% and called it 100%.
  CanvasViewport get identityViewport => CanvasViewport(zoom: render(1));

  /// [viewport] re-zoomed so it still covers the same DEVICE pixels after
  /// the effective ratio changed from [previous] to this one, keeping the
  /// canvas point under [anchor] fixed.
  ///
  /// 🚨This is the exclusion's moving part. The ratio changes when the user
  /// picks a new UI scale and when the window is dragged to a display with
  /// a different ratio; in both cases the percentage is the invariant, and
  /// without this the artwork would jump by the scale factor.
  CanvasViewport rescaledFrom(
    CanvasZoomScale previous,
    CanvasViewport viewport, {
    required ViewportPoint anchor,
  }) {
    if (previous.ratio == ratio) {
      return viewport;
    }
    return viewport.zoomedAround(
      nextZoom: render(previous.display(viewport.zoom)),
      anchor: anchor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasZoomScale && other.ratio == ratio;

  @override
  int get hashCode => ratio.hashCode;

  @override
  String toString() => 'CanvasZoomScale($ratio)';
}
