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
/// display scale [scale] (zoom × device pixel ratio).
///
/// Zero at 1:1 and below — whole pixels, the old law, byte for byte — and
/// zero wherever whole pixels already keep every sample off the texel
/// boundaries. For a scale s = p/q in lowest terms the device pixel centres
/// sample the texel grid at residues that step through every multiple of
/// 1/p, offset by `(0.5 − phase)·q/p`; the best any phase can do is put that
/// offset on the half — 1/(2p) of a texel from every boundary. Whole pixels
/// already do when q is odd (every whole zoom among them); when q is even,
/// the smallest phase that does is 1/(2q). Ties keep the smaller phase, so
/// a scale that whole pixels already serve keeps phase 0 and its bytes.
///
/// 🚨★★★F-83 (유저 2026-09-11: 「1의자리 배율에서 발생하는게
/// 남아있는거같음」, reported at 146%). This was a SEARCH over sixteenths of
/// a pixel, argued enough because a 1%-step zoom's denominator carries at
/// most 2² — true at a device pixel ratio of 1 or 2 and nowhere else. A
/// monitor at 125% (5/4) or 175% (7/4) multiplies another 2² in, and there
/// no sixteenth put the residues on the half: every odd-percent zoom from
/// 101% to 399% — 150 of them at each — kept a column exactly ON a texel
/// boundary, and an app UI scale on top lost more (225 zooms at
/// 125% × 110%; 146% itself breaks under any UI scale other than 100% on a
/// 125–250% monitor — measured 2026-09-15). A finer fixed grid only moves
/// the cliff, so the phase is read off the denominator itself, and a pinch
/// that changes the scale every frame pays a few divisions instead of a
/// sixteen-way search per frame (100,000 calls measured at 13ms).
double samplingPhaseFor(double scale) {
  if (!(scale > 1) || !scale.isFinite) {
    return 0;
  }
  final q = _denominatorOf(scale);
  return q.isOdd ? 0 : 1 / (2 * q);
}

/// The denominator of the fraction closest to [scale] that a view can tell
/// apart from it: continued-fraction convergents, stopping at the first one
/// exact to 1e-9, or before a denominator larger than the 16,384 device
/// pixels the law is measured over.
int _denominatorOf(double scale) {
  var numerator = scale.floor();
  var previousNumerator = 1;
  var denominator = 1;
  var previousDenominator = 0;
  var rest = scale - numerator;
  while (rest > 1e-12 && (scale - numerator / denominator).abs() > 1e-9) {
    final x = 1 / rest;
    final term = x.floor();
    final nextDenominator = term * denominator + previousDenominator;
    if (nextDenominator > 16384) {
      break;
    }
    final nextNumerator = term * numerator + previousNumerator;
    previousNumerator = numerator;
    numerator = nextNumerator;
    previousDenominator = denominator;
    denominator = nextDenominator;
    rest = x - term;
  }
  return denominator;
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
