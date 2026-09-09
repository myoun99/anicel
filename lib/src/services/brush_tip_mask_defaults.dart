import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_tip_mask.dart';

/// Built-in sampled brush tips, generated deterministically (fixed-seed
/// LCG) so the same bytes are produced on every run and platform — the
/// masks are engine data, and reproducibility keeps strokes and tests
/// stable. Real artist tips arrive later through ABR import.
/// CHANGING A GENERATOR RE-RENDERS EVERY OLD STROKE that used its mask, so
/// each one is frozen once shipped (the alpha sums are locked in tests). A
/// new look means a NEW mask with a new id, never an edit to one of these.
final BrushTipMask chalkBrushTipMask = _generateChalkMask();
final BrushTipMask splatterBrushTipMask = _generateSplatterMask();

/// Fine pencil grain: a near-hard disc broken by high-frequency speckle —
/// finer and denser than [chalkBrushTipMask], which reads as chalk dust.
final BrushTipMask grainBrushTipMask = _generateGrainMask();

/// Parallel bristle lines across a round footprint; a moving stroke rakes
/// them into streaks.
final BrushTipMask bristleBrushTipMask = _generateBristleMask();

/// Clumped soft blobs — sponge dabs and cloud puffs.
final BrushTipMask spongeBrushTipMask = _generateSpongeMask();

/// Wet watercolour blot: a pale, uneven pool that DARKENS towards its rim.
///
/// 🚨THE RIM IS THE POINT, and it runs the opposite way to every other tip
/// here — the others fade out at the edge, this one gains there. That is what
/// a wet wash does as it dries: pigment is carried to the boundary and left
/// behind, so the mark reads as a puddle rather than a stamp. Doing it in the
/// TIP is what lets a watercolour preset get the look with no new engine
/// field; the alternative would have been a wet-edge parameter nobody asked
/// for.
final BrushTipMask wetBlotBrushTipMask = _generateWetBlotMask();

/// Canvas-anchored PAPER texture (see `textureMask`): seamless two-octave
/// noise. A texture mask is sampled with wrapping, so any discontinuity
/// across the tile edge would print a visible grid over the artwork.
final BrushTipMask paperGrainTextureMask = _generatePaperGrainMask();

/// Canvas-anchored WEAVE texture: over/under threads on an exact period, so
/// it tiles by construction.
final BrushTipMask canvasWeaveTextureMask = _generateCanvasWeaveMask();

const int _maskSize = 64;

/// Every round tip is one disc about the mask centre, a pixel short of the
/// edge so the sampler's zero padding rings it.
const double _discCenter = _maskSize / 2.0;
const double _discRadius = _maskSize / 2.0 - 1.0;

/// The value law [_stampDisc] asks at every pixel inside its disc: the
/// pixel's cell ([x], [y]), its horizontal offset [dx] from the centre and
/// [edge] = distance / radius (0 at the centre, 1 on the rim). The stamp
/// rounds and clamps the answer to a byte; 0 leaves the pixel as it was.
typedef _DiscLaw = double Function(int x, int y, double dx, double edge);

/// Grainy disc: a soft round footprint whose interior is modulated by
/// noise, leaving chalk-like speckle and ragged edges.
BrushTipMask _generateChalkMask() {
  final noise = _noiseBytes(0x9E3779B9, _maskSize * _maskSize);
  return _discMask('builtin-chalk', (x, y, dx, edge) {
    final falloff = 1.0 - edge * 0.6;
    final grain = noise[y * _maskSize + x];
    // Drop ~30% of pixels entirely for grain; scale the rest by noise.
    if (grain < 77) {
      return 0;
    }
    return falloff * (96 + (grain - 77) * 159 / 178);
  });
}

/// Wet blot: pale in the pool, heavier at the rim, with a soft irregular
/// boundary so two dabs never stack into a clean circle.
///
/// ⚠️The rim gain is capped below 255 on purpose. A wash is a MULTIPLIER on
/// the stroke's own flow (these presets run flow ~0.35), so a saturated rim
/// here would still land pale — but a rim at full alpha would make the blot
/// read as an outline the moment someone raised flow, which is not what a
/// wet edge looks like.
BrushTipMask _generateWetBlotMask() {
  final noise = _noiseBytes(0x6C078965, _maskSize * _maskSize);
  return _discMask('builtin-wet-blot', (x, y, dx, edge) {
    final grain = noise[y * _maskSize + x];
    // The boundary wanders: the rim sits between 0.72 and 1.0 of the radius
    // depending on the cell, so the pool is not a disc.
    final rimStart = 0.72 + (grain / 255.0) * 0.16;
    if (edge > rimStart + 0.24) {
      return 0;
    }
    // Inside the pool: pale, lightly mottled.
    if (edge < rimStart) {
      return 96.0 + (grain >> 3);
    }
    // In the rim band: rises to the deposit, then feathers out past 1.0.
    final into = (edge - rimStart) / 0.24;
    final deposit = 96 + 108 * (into < 0.55 ? into / 0.55 : 1.0);
    final feather = into < 0.55 ? 1.0 : 1.0 - (into - 0.55) / 0.45;
    return deposit * feather;
  });
}

/// Scattered droplets: a dense core blob surrounded by satellite dots.
BrushTipMask _generateSplatterMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  // Dense core, stamped before the scatter so it draws no seed.
  _stampDisc(alpha, _discCenter, _discCenter, 14, _linearDot(255));
  // Satellites scattered around it.
  _scatterDots(
    alpha,
    0x2545F491,
    const _ScatterRecipe(
      count: 26,
      minDistance: 10,
      distanceSpan: 18,
      minRadius: 1.5,
      radiusSpan: 4,
      minStrength: 140,
      dot: _linearDot,
    ),
  );
  return BrushTipMask(id: 'builtin-splatter', size: _maskSize, alpha: alpha);
}

/// Pencil grain: a disc that stays solid in the middle and dissolves into
/// fine speckle towards the rim, so light pressure lays down tooth rather
/// than a clean line.
BrushTipMask _generateGrainMask() {
  final noise = _noiseBytes(0x1F123BB5, _maskSize * _maskSize);
  return _discMask('builtin-grain', (x, y, dx, edge) {
    final speckle = noise[y * _maskSize + x] / 255.0;
    // Speckle thins out with distance: solid core, ragged edge.
    final keep = 1.0 - edge * edge * 0.85;
    if (speckle > keep) {
      return 0;
    }
    return 255 * (0.55 + speckle * 0.45) * (1.0 - edge * 0.35);
  });
}

/// Bristle tip: one strength per ROW, so the footprint is a comb of lines
/// that drag into streaks along a horizontal stroke (the tip's own angle and
/// direction-following rotation turn them with it).
BrushTipMask _generateBristleMask() {
  final rowNoise = _noiseBytes(0x7F4A7C15, _maskSize);
  final rowStrength = List<double>.filled(_maskSize, 0);
  for (var row = 0; row < _maskSize; row += 1) {
    final noise = rowNoise[row] / 255.0;
    // Roughly a fifth of the rows are gaps between bristles.
    rowStrength[row] = noise < 0.2 ? 0.0 : 0.5 + noise * 0.5;
  }
  return _discMask('builtin-bristle', (x, y, dx, edge) {
    final strength = rowStrength[y];
    if (strength == 0.0) {
      return 0;
    }
    // Bristles thin towards their ends, not just towards the rim.
    final along = 1.0 - (dx.abs() / _discRadius) * 0.45;
    final falloff = 1.0 - math.pow(edge, 3).toDouble();
    return 255 * strength * along * falloff;
  });
}

/// Sponge/cloud tip: overlapping soft blobs inside a disc, so every dab
/// lands as an irregular clump instead of a circle.
BrushTipMask _generateSpongeMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  _scatterDots(
    alpha,
    0x5D588B65,
    const _ScatterRecipe(
      count: 16,
      minDistance: 0,
      distanceSpan: 15,
      minRadius: 5,
      radiusSpan: 9,
      minStrength: 150,
      dot: _softDot,
    ),
  );
  return BrushTipMask(id: 'builtin-sponge', size: _maskSize, alpha: alpha);
}

/// One round tip: [law] stamped once over the full [_discRadius] disc of a
/// fresh buffer, so the stamp's max-blend is plain assignment.
///
/// ⚠️[_generateChalkMask] and [_generateGrainMask] walk the same seeded
/// disc — the clone scan pairs them, and the audit read both (2026-09-04).
/// They are HELD, not merged: only two tips share it (the bristle runs a
/// per-row pre-pass, the sponge walks blobs, the weave has no noise at
/// all), and a per-pixel callback for two callers buys a closure call per
/// pixel and one more indirection to read through. A THIRD speckled disc
/// is what makes this worth a `_seededDiscMask(id, seed, valueAt)`.
/// 2026-09-06 (round 8): the bristle's footprint was that third disc, so
/// this is it — the seed moved into a table ([_noiseBytes]) read by cell,
/// so the callback carries no LCG state, and the disc walk itself is the
/// dot stamp ([_stampDisc]) the splatter and sponge already shared.
BrushTipMask _discMask(String id, _DiscLaw law) {
  final alpha = Uint8List(_maskSize * _maskSize);
  _stampDisc(alpha, _discCenter, _discCenter, _discRadius, law);
  return BrushTipMask(id: id, size: _maskSize, alpha: alpha);
}

/// [count] bytes of the [seed] LCG stream in order: cell k holds bits 8..15
/// of the (k+1)-th state. A generator reads its noise by cell, so a pixel
/// outside the disc still owns its byte and the speckle stays where it
/// shipped.
Uint8List _noiseBytes(int seed, int count) {
  final bytes = Uint8List(count);
  var state = seed;
  for (var index = 0; index < count; index += 1) {
    state = _nextSeed(state);
    bytes[index] = (state >> 8) & 0xFF;
  }
  return bytes;
}

/// A scatter of dots as data: how many, how far from the centre, how big
/// and how strong each may be (every "may be" is `min + draw * span` with
/// one LCG draw), and the [dot] law stamped at each.
class _ScatterRecipe {
  const _ScatterRecipe({
    required this.count,
    required this.minDistance,
    required this.distanceSpan,
    required this.minRadius,
    required this.radiusSpan,
    required this.minStrength,
    required this.dot,
  });

  final int count;
  final double minDistance;
  final double distanceSpan;
  final double minRadius;
  final double radiusSpan;
  final int minStrength;
  final _DiscLaw Function(int strength) dot;
}

/// Stamps [recipe]'s dots around the mask centre, each placed and sized by
/// four draws of the [seed] LCG in the order angle, distance, radius,
/// strength — the draw order is part of the frozen bytes.
void _scatterDots(Uint8List alpha, int seed, _ScatterRecipe recipe) {
  var state = seed;
  for (var dot = 0; dot < recipe.count; dot += 1) {
    state = _nextSeed(state);
    final angle = ((state >> 4) & 0x3FF) / 1024.0 * 2.0 * math.pi;
    state = _nextSeed(state);
    final distance =
        recipe.minDistance +
        ((state >> 4) & 0xFF) / 255.0 * recipe.distanceSpan;
    state = _nextSeed(state);
    final radius =
        recipe.minRadius + ((state >> 4) & 0xFF) / 255.0 * recipe.radiusSpan;
    state = _nextSeed(state);
    final strength = recipe.minStrength + ((state >> 4) & 0x7F);
    _stampDisc(
      alpha,
      _discCenter + math.cos(angle) * distance,
      _discCenter + math.sin(angle) * distance,
      radius,
      recipe.dot(strength),
    );
  }
}

/// Paper tooth: two octaves of wrapping value noise, kept in the upper half
/// of the range so the texture bites into a stroke without erasing it.
BrushTipMask _generatePaperGrainMask() {
  final coarse = _seamlessValueNoise(8, 0x68E31DA4);
  final fine = _seamlessValueNoise(16, 0xB5297A4D);
  final alpha = Uint8List(_maskSize * _maskSize);
  for (var index = 0; index < alpha.length; index += 1) {
    final noise = coarse[index] * 0.6 + fine[index] * 0.4;
    alpha[index] = (255 * (0.35 + noise * 0.65)).round().clamp(0, 255);
  }
  return BrushTipMask(id: 'builtin-paper-grain', size: _maskSize, alpha: alpha);
}

/// Canvas weave: warp and weft threads alternating over and under on an
/// 8px period, which divides the mask exactly — no seam arithmetic needed.
BrushTipMask _generateCanvasWeaveMask() {
  const period = 8;
  final alpha = Uint8List(_maskSize * _maskSize);
  for (var y = 0; y < _maskSize; y += 1) {
    for (var x = 0; x < _maskSize; x += 1) {
      final overUnder = ((x ~/ period) + (y ~/ period)).isEven;
      // The thread on top is shaded across its width; the one beneath keeps
      // a dimmer, flatter face.
      final across = overUnder ? y % period : x % period;
      final profile = 1.0 - ((across + 0.5) / period - 0.5).abs() * 2.0;
      final value = overUnder ? 0.55 + profile * 0.45 : 0.4 + profile * 0.3;
      alpha[y * _maskSize + x] = (255 * value).round().clamp(0, 255);
    }
  }
  return BrushTipMask(
    id: 'builtin-canvas-weave',
    size: _maskSize,
    alpha: alpha,
  );
}

/// Value noise on a [lattice]×[lattice] grid, smoothly interpolated up to
/// the mask size with the lattice WRAPPING at both edges — that wrap is what
/// makes the result tile seamlessly.
List<double> _seamlessValueNoise(int lattice, int seed) {
  final grid = List<double>.filled(lattice * lattice, 0);
  var state = seed;
  for (var index = 0; index < grid.length; index += 1) {
    state = _nextSeed(state);
    grid[index] = ((state >> 8) & 0xFFFF) / 65535.0;
  }

  double smooth(double t) => t * t * (3.0 - 2.0 * t);

  final result = List<double>.filled(_maskSize * _maskSize, 0);
  final scale = lattice / _maskSize;
  for (var y = 0; y < _maskSize; y += 1) {
    final sampleY = y * scale;
    final y0 = sampleY.floor() % lattice;
    final y1 = (y0 + 1) % lattice;
    final ty = smooth(sampleY - sampleY.floor());
    for (var x = 0; x < _maskSize; x += 1) {
      final sampleX = x * scale;
      final x0 = sampleX.floor() % lattice;
      final x1 = (x0 + 1) % lattice;
      final tx = smooth(sampleX - sampleX.floor());
      final top =
          grid[y0 * lattice + x0] * (1 - tx) + grid[y0 * lattice + x1] * tx;
      final bottom =
          grid[y1 * lattice + x0] * (1 - tx) + grid[y1 * lattice + x1] * tx;
      result[y * _maskSize + x] = top * (1 - ty) + bottom * ty;
    }
  }
  return result;
}

/// Deterministic 31-bit LCG so the masks are identical everywhere.
int _nextSeed(int seed) => (seed * 1103515245 + 12345) & 0x7FFFFFFF;

/// Stamps a disc of [radius] at ([centerX], [centerY]) into [alpha]: [law]
/// at each covered pixel, max-blended so overlapping blobs merge instead of
/// banding. Every byte a bundled tip holds comes through here, so the file
/// header's freeze applies to this walk above all.
///
/// 🚨ONE stamp for the splatter's dots (linear) and the soft blobs
/// (squared) — the audit's clone scan, 2026-09-03. [law] keeps each
/// caller's own multiplication order, so the generated bytes are theirs.
void _stampDisc(
  Uint8List alpha,
  double centerX,
  double centerY,
  double radius,
  _DiscLaw law,
) {
  final left = math.max(0, (centerX - radius).floor());
  final top = math.max(0, (centerY - radius).floor());
  final right = math.min(_maskSize - 1, (centerX + radius).ceil());
  final bottom = math.min(_maskSize - 1, (centerY + radius).ceil());
  for (var y = top; y <= bottom; y += 1) {
    for (var x = left; x <= right; x += 1) {
      final dx = x + 0.5 - centerX;
      final dy = y + 0.5 - centerY;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radius) {
        continue;
      }
      final value = law(x, y, dx, distance / radius).round();
      final offset = y * _maskSize + x;
      alpha[offset] = math.max(alpha[offset], value.clamp(0, 255));
    }
  }
}

/// A dot of [strength] that fades linearly to the rim.
_DiscLaw _linearDot(int strength) =>
    (x, y, dx, edge) => strength * (1.0 - edge);

/// A soft dot of [strength]: the linear fade squared, so the blob has no
/// hard shoulder.
_DiscLaw _softDot(int strength) => (x, y, dx, edge) {
  final fade = 1.0 - edge;
  return strength * fade * fade;
};
