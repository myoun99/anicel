import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';

export '../../services/viewport_transform_matrix.dart';

/// [viewport] with its TRANSLATION snapped to whole device pixels — what
/// every canvas-space painter actually renders (the pan-phase snap,
/// 2026-08-17 실기: two symptoms, one fractional device translation).
///
///  * Skia's raster cache snaps a stable picture to INTEGRAL device
///    translation and live repaints render fractionally, so pen-down /
///    pen-up / layer-switch flipped between the two and axis-aligned edges
///    hopped 1px. Snapped, a live render lands where the cached one will.
///  * Every pan step changed the fractional phase, so nearest-sampled
///    edges trembled at position-deterministic spots. Snapped, a pan
///    sweeps the phase in whole device pixels.
///
/// ⛔Render-time only: stored pan/gesture state stays a free float, and
/// pointer math keeps the exact mapping — the two agree within half a
/// device pixel, which is the snap's whole budget.
/// ⛔A rotated view is exempt: sampling under rotation is inherently
/// fractional, and rounding a pre-rotation translate in device space is
/// ill-defined. Flips snap like everything else.
CanvasViewport renderSnappedViewport(
  CanvasViewport viewport,
  double devicePixelRatio,
) {
  if (viewport.rotationDegrees != 0) {
    return viewport;
  }
  final panX =
      (viewport.panX * devicePixelRatio).roundToDouble() / devicePixelRatio;
  final panY =
      (viewport.panY * devicePixelRatio).roundToDouble() / devicePixelRatio;
  if (panX == viewport.panX && panY == viewport.panY) {
    return viewport;
  }
  return viewport.copyWith(panX: panX, panY: panY);
}

/// The ONE way painters take canvas-space geometry to the screen (P8):
/// translate · scale · rotate · flip — the matrix
/// [CanvasViewport.canvasToViewport] speaks, with the translation snapped
/// through [renderSnappedViewport]. Painters call this instead of
/// hand-rolling translate/scale pairs; a viewport feature added here
/// reaches every painter at once — and the snap only keeps sibling
/// painters mutually aligned because they all take it from this one spot.
///
/// [devicePixelRatio] is the EFFECTIVE ratio at build time — monitor × UI
/// scale, the ratio the ROOT MATRIX uses — read through
/// `EffectiveDevicePixelRatio.of`, the same source the layer stack painter
/// reads. ⛔NOT `MediaQuery`: it reports the monitor's raw ratio while the
/// compositor works on the product, so a caller that reaches for it puts
/// its painter on a different grid from every sibling that feeds this
/// parameter. The default snaps to whole
/// LOGICAL pixels — right only where every canvas-space painter of a host
/// stays at the default together; the editing canvas wires the real value
/// through every painter it composes, or a snapped artwork and an
/// unsnapped sibling would sit a sub-pixel apart.
void applyViewportTransform(
  Canvas canvas,
  CanvasViewport viewport, {
  double devicePixelRatio = 1.0,
}) {
  final snapped = renderSnappedViewport(viewport, devicePixelRatio);
  canvas.translate(snapped.panX, snapped.panY);
  canvas.scale(snapped.zoom, snapped.zoom);
  if (snapped.rotationDegrees != 0) {
    canvas.rotate(snapped.rotationRadians);
  }
  if (snapped.flipHorizontal || snapped.flipVertical) {
    canvas.scale(
      snapped.flipHorizontal ? -1 : 1,
      snapped.flipVertical ? -1 : 1,
    );
  }
}
