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
/// device pixels: the phase, of those the laws below name, at which every
/// visible sample point is farthest from a texel boundary. At 1:1 and at
/// every whole zoom the phase is 0 and the bytes are what they always were;
/// at 110% it is a twentieth of a pixel, and the nearest tie is 1/22 of a
/// texel away — hundreds of times the rounding any path can carry.
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
/// 125% × 110%; 146% itself breaks at a 125% or 175% monitor under the 90,
/// 110, 125 and 150% UI stops and at a 150% or 250% monitor under 125%, and
/// at no monitor under 100% UI — measured 2026-09-15). A finer fixed grid only moves
/// the cliff, so the phase is read off the denominator itself, and a pinch
/// that changes the scale every frame pays a few divisions instead of a
/// sixteen-way search per frame (100,000 calls measured at 13ms). ↩️That
/// was the denominator law alone: since the review below, a scale between
/// fractions — every frame of a pinch — is MEASURED, 30–610 µs once per
/// scale.
///
/// 🚨★★★AND THE DENOMINATOR ALONE WAS WRONG OFF THE EXACT SCALES (review
/// 2026-09-15). 1/(2q) is the best phase only where the scale IS p/q. A
/// wheel notch (×1.1) or a pinch lands NEXT to such a fraction, the
/// continued fraction runs on to a denominator in the thousands, and its
/// phase left samples millionths of a texel off a boundary where a
/// sixteenth had kept them a hundredth away: 39/2 − 4.1e-5 at 2.1e-6
/// against 0.0119, fourteen wheel notches from 100% at 1.0e-5 against
/// 3.4e-5. So neither law picks alone: every phase either one names is
/// measured and the best TRUE margin wins — never worse than the search,
/// never worse than the denominator. Ties keep the smaller phase, as before.
///
/// An exact fraction — every preset, typed and 1%-step zoom at every
/// monitor ratio and UI stop — skips the measuring: its denominator's phase
/// is already the best any phase can do. Measured 2026-09-15 (Dart VM): that
/// answer in under a microsecond; a scale between fractions 30–610 µs, where
/// the search alone had cost 250–620 µs — once per scale, the memo keeping it
/// for every painter that asks after.
double samplingPhaseFor(double scale) {
  if (!(scale > 1) || !scale.isFinite) {
    return 0;
  }
  final kept = _phaseMemo[scale];
  if (kept != null) {
    return kept;
  }
  if (_phaseMemo.length >= 8) {
    _phaseMemo.remove(_phaseMemo.keys.first);
  }
  return _phaseMemo[scale] = _bestPhaseFor(scale);
}

double _bestPhaseFor(double scale) {
  final convergents = _convergentsOf(scale);
  final (:p, :q) = convergents.last;
  // Exactly p/q, with a full period of residues inside the measured pixels:
  // 1/(2q), or whole pixels for an odd q, puts every sample 1/(2p) from a
  // boundary, and no phase can put the nearest one farther.
  if ((scale - p / q).abs() <= 1e-12 * scale &&
      p <= 2 * _measuredHalfWidth) {
    return q.isOdd ? 0 : 1 / (2 * q);
  }
  final phases = <double>{
    0,
    for (final convergent in convergents)
      if (convergent.q.isEven) 1 / (2 * convergent.q),
    for (var sixteenth = 1; sixteenth < 16; sixteenth += 1) sixteenth / 16,
  }.toList()..sort();
  var best = 0.0;
  var bestMargin = -1.0;
  for (final phase in phases) {
    final margin = _marginAt(scale, phase, failsAt: bestMargin + 1e-12);
    if (margin > bestMargin + 1e-12) {
      bestMargin = margin;
      best = phase;
    }
  }
  return best;
}

/// The last few scales' phases. More than one: the sheet canvas and the
/// editing canvas paint at their own scales in the same frame, and a pinch
/// moves one of them every frame.
final Map<double, double> _phaseMemo = {};

/// The device pixel centres a phase is measured over: this many either
/// side of the canvas origin.
const _measuredHalfWidth = 8192;

/// The continued-fraction convergents p/q of [scale], shallowest first — up
/// to the first one exact to 1e-9, or the last before q outgrows the
/// measured pixels.
List<({int p, int q})> _convergentsOf(double scale) {
  var numerator = scale.floor();
  var previousNumerator = 1;
  var denominator = 1;
  var previousDenominator = 0;
  var rest = scale - numerator;
  final convergents = [(p: numerator, q: denominator)];
  while (rest > 1e-12 && (scale - numerator / denominator).abs() > 1e-9) {
    final x = 1 / rest;
    final term = x.floor();
    final nextDenominator = term * denominator + previousDenominator;
    if (nextDenominator > 2 * _measuredHalfWidth) {
      break;
    }
    final nextNumerator = term * numerator + previousNumerator;
    previousNumerator = numerator;
    numerator = nextNumerator;
    previousDenominator = denominator;
    denominator = nextDenominator;
    rest = x - term;
    convergents.add((p: numerator, q: denominator));
  }
  return convergents;
}

/// The least distance, in texels, from a texel boundary that any device
/// pixel centre within [_measuredHalfWidth] of the origin samples at, for
/// [scale] and [phase] — or the first distance at or below [failsAt], which
/// already loses.
///
/// Walks the BOUNDARIES rather than the pixels: boundary n is sampled
/// nearest by the pixel centre closest to `n·scale − 0.5 + phase`, so 16,384
/// / [scale] steps say what 16,384 would.
double _marginAt(double scale, double phase, {required double failsAt}) {
  final first = ((-_measuredHalfWidth + 0.5 - phase) / scale).floor();
  final last = ((_measuredHalfWidth - 0.5 - phase) / scale).ceil();
  var least = 0.5;
  for (var n = first; n <= last; n += 1) {
    final boundary = n * scale;
    var pixel = (boundary - 0.5 + phase).roundToDouble();
    if (pixel < -_measuredHalfWidth) {
      pixel = -_measuredHalfWidth.toDouble();
    } else if (pixel > _measuredHalfWidth - 1) {
      pixel = _measuredHalfWidth - 1.0;
    }
    final distance = (pixel + 0.5 - phase - boundary).abs() / scale;
    if (distance < least) {
      least = distance;
      if (least <= failsAt) {
        return least;
      }
    }
  }
  return least;
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
