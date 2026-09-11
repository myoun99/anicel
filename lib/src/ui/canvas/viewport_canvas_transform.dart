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
///
/// 🚨★★★F-67 (2026-09-11): WHOLE pixels was the right law at 1:1 and the
/// wrong one under magnification. Above 1 the display samples the artwork
/// at `FilterQuality.none`, so device pixel i reads texel
/// `floor((i + 0.5 - t) / s)` — and for a scale s = p/q with p odd and q
/// even (110% = 11/10, 125% = 5/4, 150% = 3/2, …) a whole-pixel t puts one
/// column in every q EXACTLY on a texel boundary. Which texel that column
/// shows is then decided by float rounding, and the engine's cached
/// raster of the picture reaches the same point through different
/// operands than a live repaint: those columns hopped a whole texel at
/// every cache engage/disengage — pen-down/up, tool change, pan start.
/// 실기 09-11: hops at 105·110·115·125·130·135·150·175·250%, none at
/// 100·120·140·160·180·200·300·400% — exactly the p-odd/q-even set.
///
/// So the translation is snapped to `whole + `[samplingPhaseFor]`(s)`
/// device pixels: the phase at which every visible sample point is as far
/// from a texel boundary as this scale allows. At 1:1 and at every whole
/// zoom the phase is 0 and the bytes are what they always were; at 110%
/// it is a quarter pixel, and the nearest tie is 1/22 of a texel away —
/// hundreds of times the rounding any path can carry.
CanvasViewport renderSnappedViewport(
  CanvasViewport viewport,
  double devicePixelRatio,
) {
  if (viewport.rotationDegrees != 0) {
    return viewport;
  }
  final phase = samplingPhaseFor(viewport.zoom.abs() * devicePixelRatio);
  double snap(double pan) =>
      ((pan * devicePixelRatio - phase).roundToDouble() + phase) /
      devicePixelRatio;
  final panX = snap(viewport.panX);
  final panY = snap(viewport.panY);
  if (panX == viewport.panX && panY == viewport.panY) {
    return viewport;
  }
  return viewport.copyWith(panX: panX, panY: panY);
}

/// The fraction of a device pixel the render translation is snapped TO at
/// display scale [scale] (zoom × device pixel ratio), in sixteenths.
///
/// Zero at 1:1 and below — whole pixels, the old law, byte for byte — and
/// zero wherever whole pixels already keep every sample off the texel
/// boundaries (every whole zoom). Otherwise the sixteenth that maximises
/// the smallest distance from `((j + 0.5 - phase) / scale)` to an integer
/// over 8192 device pixels either side of the origin: for a 1%-step zoom
/// the denominator's power of two is at most 4, and one of the sixteenths
/// always lands the residues on the half — the tie is then 1/(2q) of a
/// texel away, 1/200 at worst, where the paths' rounding is ~1e-5.
///
/// Memoised on the scale: a pinch changes it every frame, and the search
/// is 16 × 16384 subtractions.
double samplingPhaseFor(double scale) {
  if (!(scale > 1) || !scale.isFinite) {
    return 0;
  }
  final memo = _phaseMemo;
  if (memo != null && memo.scale == scale) {
    return memo.phase;
  }
  var best = 0.0;
  var bestMargin = -1.0;
  for (var sixteenth = 0; sixteenth < 16; sixteenth += 1) {
    final phase = sixteenth / 16;
    var margin = 0.5;
    for (var j = -8192; j < 8192 && margin > bestMargin; j += 1) {
      final u = (j + 0.5 - phase) / scale;
      final d = (u - u.roundToDouble()).abs();
      if (d < margin) {
        margin = d;
      }
    }
    // Strictly better only: ties keep the smaller phase, so a scale that
    // whole pixels already serve keeps phase 0 and its exact bytes.
    if (margin > bestMargin + 1e-9) {
      bestMargin = margin;
      best = phase;
    }
  }
  _phaseMemo = (scale: scale, phase: best);
  return best;
}

({double scale, double phase})? _phaseMemo;

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
