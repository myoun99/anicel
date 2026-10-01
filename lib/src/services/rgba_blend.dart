import 'dart:typed_data';

import '../models/rgba_color.dart';
import '../models/stroke_pixel.dart';
import 'brush_dab_share.dart';

double effectiveSourceAlpha({
  required RgbaColor source,
  required double opacity,
  required double flow,
}) {
  _validateUnitIntervalFinite(opacity, 'opacity');
  _validateUnitIntervalFinite(flow, 'flow');

  return (source.a / 255.0) * opacity * flow;
}

/// The source alpha a blend actually applies — validating [opacity] and
/// [flow] on the way, and answering null where the source contributes
/// nothing and the destination stands unchanged.
///
/// ⛔EVERY BLEND OPENS THIS WAY. Both ops validated, then guarded, then
/// derived the alpha in three copied statements; the guard is exactly
/// "the effective alpha is zero", and saying it twice is how one op would
/// keep validating an argument the other had stopped checking.
double? _contributingSourceAlpha({
  required RgbaColor source,
  required double opacity,
  required double flow,
}) {
  final alpha = effectiveSourceAlpha(
    source: source,
    opacity: opacity,
    flow: flow,
  );
  return alpha == 0.0 ? null : alpha;
}

/// Source-over onto a pixel of a stroke: what is under the source comes off
/// the destination's 16-bit plane, and the result lands on both planes
/// ([StrokePixel], ABI 40). With an [evening] table the source lays its
/// share of what it would lay whole ([evenedLaid], ABI 41).
StrokePixel strokeSourceOver({
  required RgbaColor source,
  required StrokePixel destination,
  required double opacity,
  required double flow,
  Float64List? evening,
}) {
  final sourceAlpha = _contributingSourceAlpha(
    source: source,
    opacity: opacity,
    flow: flow,
  );
  if (sourceAlpha == null) {
    return destination;
  }
  return strokeSourceOverAt(
    source: source,
    destination: destination,
    sourceAlpha: evening == null
        ? sourceAlpha
        : evenedLaid(evening, sourceAlpha),
  );
}

/// [strokeSourceOver] at a [sourceAlpha] the caller has already resolved —
/// for a blend whose alpha depends on the destination (a brush dab settling
/// at its opacity, F-205).
StrokePixel strokeSourceOverAt({
  required RgbaColor source,
  required StrokePixel destination,
  required double sourceAlpha,
}) {
  final destinationAlpha = destination.a / 65535.0;
  final inverseSourceAlpha = 1.0 - sourceAlpha;
  final outAlpha = sourceAlpha + destinationAlpha * inverseSourceAlpha;

  if (outAlpha == 0.0) {
    return StrokePixel.transparent;
  }

  // Over nothing or over its own colour the source lands its own colour
  // exactly — `qa_dab_over_own_colour` says why that is the same bytes.
  if (destination.a == 0 ||
      (destination.r == source.r * 257 &&
          destination.g == source.g * 257 &&
          destination.b == source.b * 257)) {
    return StrokePixel.rounded(
      red: source.r.toDouble(),
      green: source.g.toDouble(),
      blue: source.b.toDouble(),
      alpha: outAlpha,
    );
  }

  return StrokePixel.rounded(
    red:
        (source.r * sourceAlpha +
            destination.r / 257.0 * destinationAlpha * inverseSourceAlpha) /
        outAlpha,
    green:
        (source.g * sourceAlpha +
            destination.g / 257.0 * destinationAlpha * inverseSourceAlpha) /
        outAlpha,
    blue:
        (source.b * sourceAlpha +
            destination.b / 257.0 * destinationAlpha * inverseSourceAlpha) /
        outAlpha,
    alpha: outAlpha,
  );
}

/// Destination-out: removes [destination] alpha by the source's effective
/// alpha (the eraser blend). Straight-alpha convention: RGB stays the
/// destination's; a fully erased pixel zeroes out entirely, matching
/// [strokeSourceOver]'s zero-alpha handling — and its [evening].
StrokePixel strokeDestinationOut({
  required RgbaColor source,
  required StrokePixel destination,
  required double opacity,
  required double flow,
  Float64List? evening,
}) {
  final whole = _contributingSourceAlpha(
    source: source,
    opacity: opacity,
    flow: flow,
  );
  if (whole == null) {
    return destination;
  }
  final sourceAlpha = evening == null ? whole : evenedLaid(evening, whole);
  final destinationAlpha = destination.a / 65535.0;
  final outAlpha = destinationAlpha * (1.0 - sourceAlpha);

  if (outAlpha == 0.0) {
    return StrokePixel.transparent;
  }

  return StrokePixel.withAlpha(destination, outAlpha);
}

void _validateUnitIntervalFinite(double value, String fieldName) {
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      '$fieldName must be finite and between 0.0 and 1.0 inclusive.',
    );
  }
}
