import '../models/brush_dab.dart';
import '../models/brush_shape.dart';

/// The colour already on the cel under a dab, as the mixer needs it.
///
/// [coverage] is how much of the sampled area was actually painted, 0..1 —
/// mixing on bare canvas must not drag the reservoir toward the transparent
/// pixels' RGB (which is black), so an empty ground contributes nothing.
class BrushGroundSample {
  const BrushGroundSample({required this.rgb, required this.coverage});

  /// Straight (un-premultiplied) 0xRRGGBB of the painted pixels.
  final int rgb;

  /// Painted fraction of the sampled area, 0..1.
  final double coverage;

  static const BrushGroundSample empty = BrushGroundSample(
    rgb: 0,
    coverage: 0.0,
  );
}

/// Reads the ground under a dab centred at ([x], [y]) with radius [radius].
typedef BrushGroundColorSampler =
    BrushGroundSample Function(double x, double y, double radius);

/// Resolves the colour a mixing brush actually deposits, one dab at a time.
///
/// Clip Studio's 밑바탕 혼색 and Photoshop's Mixer Brush are one model: the
/// brush carries a reservoir of paint, each dab lifts colour from the canvas
/// into it, then puts a blend of the two back down. Both are reproduced by
/// resolving the deposit colour AT PLACEMENT and baking it into the dab —
/// the rasterizers never learn about mixing, the parity suites stay intact,
/// and undo/redo replays the stored dabs byte-identically.
///
/// One reservoir lives per stroke, so it must be fed dabs in stroke order.
/// That ordering is now load-bearing: the rasterizers may never reorder or
/// parallelise dabs within a stroke.
class BrushGroundColorMixer {
  BrushGroundColorMixer({required this.shape});

  final BrushShape shape;

  /// The paint currently on the brush, 0xRRGGBB. Null until the first dab
  /// seeds it from the brush colour.
  int? _reservoir;

  bool get isActive => shape.mixesGroundColor;

  /// Returns [dabs] with their deposit colours resolved.
  ///
  /// [sample] reads the composite as of the START of this batch. A dab does
  /// not see the dabs beside it in the same batch — the rasterizer works a
  /// pointer-move at a time and forcing a rasterize per dab would undo that
  /// batching. The reservoir still carries across every dab, which is what
  /// actually produces the smear.
  List<BrushDab> apply(
    List<BrushDab> dabs, {
    required BrushGroundColorSampler sample,
  }) {
    if (!isActive || dabs.isEmpty) {
      return dabs;
    }
    final stretch = shape.colorStretch.clamp(0.0, 1.0);
    final amount = shape.paintAmount.clamp(0.0, 1.0);
    final density = shape.paintDensity.clamp(0.0, 1.0);

    final mixed = <BrushDab>[];
    for (final dab in dabs) {
      final sourceArgb = dab.color;
      _reservoir ??= sourceArgb & 0x00FFFFFF;

      final ground = sample(dab.center.x, dab.center.y, dab.size / 2.0);
      // Bare canvas has no colour to lift; the brush keeps what it holds.
      if (ground.coverage > 0.0) {
        _reservoir = _lerpRgb(
          _reservoir!,
          ground.rgb,
          stretch * ground.coverage,
        );
      }
      // What lands is the reservoir pulled back toward the ground by however
      // little paint the brush is releasing.
      final depositRgb = ground.coverage > 0.0
          ? _lerpRgb(ground.rgb, _reservoir!, amount)
          : _reservoir!;
      final alpha = (((sourceArgb >> 24) & 0xFF) * density).round().clamp(
        0,
        255,
      );
      mixed.add(dab.copyWith(color: (alpha << 24) | depositRgb));
    }
    return mixed;
  }
}

/// Channel-wise linear blend of two 0xRRGGBB colours.
int _lerpRgb(int from, int to, double t) {
  if (t <= 0.0) {
    return from;
  }
  if (t >= 1.0) {
    return to;
  }
  final r =
      (((from >> 16) & 0xFF) + (((to >> 16) & 0xFF) - ((from >> 16) & 0xFF)) * t)
          .round()
          .clamp(0, 255);
  final g =
      (((from >> 8) & 0xFF) + (((to >> 8) & 0xFF) - ((from >> 8) & 0xFF)) * t)
          .round()
          .clamp(0, 255);
  final b = ((from & 0xFF) + ((to & 0xFF) - (from & 0xFF)) * t).round().clamp(
    0,
    255,
  );
  return (r << 16) | (g << 8) | b;
}
