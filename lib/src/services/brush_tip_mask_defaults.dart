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

/// Canvas-anchored PAPER texture (see `textureMask`): seamless two-octave
/// noise. A texture mask is sampled with wrapping, so any discontinuity
/// across the tile edge would print a visible grid over the artwork.
final BrushTipMask paperGrainTextureMask = _generatePaperGrainMask();

/// Canvas-anchored WEAVE texture: over/under threads on an exact period, so
/// it tiles by construction.
final BrushTipMask canvasWeaveTextureMask = _generateCanvasWeaveMask();

const int _maskSize = 64;

/// Grainy disc: a soft round footprint whose interior is modulated by
/// noise, leaving chalk-like speckle and ragged edges.
BrushTipMask _generateChalkMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  var seed = 0x9E3779B9;
  const center = _maskSize / 2.0;
  const radius = _maskSize / 2.0 - 1.0;
  for (var y = 0; y < _maskSize; y += 1) {
    for (var x = 0; x < _maskSize; x += 1) {
      final dx = x + 0.5 - center;
      final dy = y + 0.5 - center;
      final distance = math.sqrt(dx * dx + dy * dy);
      seed = _nextSeed(seed);
      if (distance > radius) {
        continue;
      }
      final falloff = 1.0 - (distance / radius) * 0.6;
      final noise = (seed >> 8) & 0xFF;
      // Drop ~30% of pixels entirely for grain; scale the rest by noise.
      if (noise < 77) {
        continue;
      }
      final value = (falloff * (96 + (noise - 77) * 159 / 178)).round();
      alpha[y * _maskSize + x] = value.clamp(0, 255);
    }
  }
  return BrushTipMask(id: 'builtin-chalk', size: _maskSize, alpha: alpha);
}

/// Scattered droplets: a dense core blob surrounded by satellite dots.
BrushTipMask _generateSplatterMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  var seed = 0x2545F491;

  void stampDot(double centerX, double centerY, double radius, int strength) {
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
        final value = (strength * (1.0 - distance / radius)).round();
        final offset = y * _maskSize + x;
        alpha[offset] = math.max(alpha[offset], value.clamp(0, 255));
      }
    }
  }

  // Dense core.
  stampDot(_maskSize / 2.0, _maskSize / 2.0, 14, 255);
  // Satellites scattered around it.
  for (var dot = 0; dot < 26; dot += 1) {
    seed = _nextSeed(seed);
    final angle = ((seed >> 4) & 0x3FF) / 1024.0 * 2.0 * math.pi;
    seed = _nextSeed(seed);
    final distance = 10.0 + ((seed >> 4) & 0xFF) / 255.0 * 18.0;
    seed = _nextSeed(seed);
    final radius = 1.5 + ((seed >> 4) & 0xFF) / 255.0 * 4.0;
    seed = _nextSeed(seed);
    final strength = 140 + ((seed >> 4) & 0x7F);
    stampDot(
      _maskSize / 2.0 + math.cos(angle) * distance,
      _maskSize / 2.0 + math.sin(angle) * distance,
      radius,
      strength,
    );
  }
  return BrushTipMask(id: 'builtin-splatter', size: _maskSize, alpha: alpha);
}

/// Pencil grain: a disc that stays solid in the middle and dissolves into
/// fine speckle towards the rim, so light pressure lays down tooth rather
/// than a clean line.
BrushTipMask _generateGrainMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  var seed = 0x1F123BB5;
  const center = _maskSize / 2.0;
  const radius = _maskSize / 2.0 - 1.0;
  for (var y = 0; y < _maskSize; y += 1) {
    for (var x = 0; x < _maskSize; x += 1) {
      final dx = x + 0.5 - center;
      final dy = y + 0.5 - center;
      final distance = math.sqrt(dx * dx + dy * dy);
      seed = _nextSeed(seed);
      if (distance > radius) {
        continue;
      }
      final noise = ((seed >> 8) & 0xFF) / 255.0;
      // Speckle thins out with distance: solid core, ragged edge.
      final edge = distance / radius;
      final keep = 1.0 - edge * edge * 0.85;
      if (noise > keep) {
        continue;
      }
      final value = (255 * (0.55 + noise * 0.45) * (1.0 - edge * 0.35)).round();
      alpha[y * _maskSize + x] = value.clamp(0, 255);
    }
  }
  return BrushTipMask(id: 'builtin-grain', size: _maskSize, alpha: alpha);
}

/// Bristle tip: one strength per ROW, so the footprint is a comb of lines
/// that drag into streaks along a horizontal stroke (the tip's own angle and
/// direction-following rotation turn them with it).
BrushTipMask _generateBristleMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  var seed = 0x7F4A7C15;
  final rowStrength = List<double>.filled(_maskSize, 0);
  for (var row = 0; row < _maskSize; row += 1) {
    seed = _nextSeed(seed);
    final noise = ((seed >> 8) & 0xFF) / 255.0;
    // Roughly a fifth of the rows are gaps between bristles.
    rowStrength[row] = noise < 0.2 ? 0.0 : 0.5 + noise * 0.5;
  }
  const center = _maskSize / 2.0;
  const radius = _maskSize / 2.0 - 1.0;
  for (var y = 0; y < _maskSize; y += 1) {
    final strength = rowStrength[y];
    if (strength == 0.0) {
      continue;
    }
    for (var x = 0; x < _maskSize; x += 1) {
      final dx = x + 0.5 - center;
      final dy = y + 0.5 - center;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radius) {
        continue;
      }
      // Bristles thin towards their ends, not just towards the rim.
      final along = 1.0 - (dx.abs() / radius) * 0.45;
      final falloff = 1.0 - math.pow(distance / radius, 3).toDouble();
      final value = (255 * strength * along * falloff).round();
      alpha[y * _maskSize + x] = value.clamp(0, 255);
    }
  }
  return BrushTipMask(id: 'builtin-bristle', size: _maskSize, alpha: alpha);
}

/// Sponge/cloud tip: overlapping soft blobs inside a disc, so every dab
/// lands as an irregular clump instead of a circle.
BrushTipMask _generateSpongeMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  var seed = 0x5D588B65;
  for (var blob = 0; blob < 16; blob += 1) {
    seed = _nextSeed(seed);
    final angle = ((seed >> 4) & 0x3FF) / 1024.0 * 2.0 * math.pi;
    seed = _nextSeed(seed);
    final distance = ((seed >> 4) & 0xFF) / 255.0 * 15.0;
    seed = _nextSeed(seed);
    final blobRadius = 5.0 + ((seed >> 4) & 0xFF) / 255.0 * 9.0;
    seed = _nextSeed(seed);
    final strength = 150 + ((seed >> 4) & 0x7F);
    _stampSoftBlob(
      alpha,
      _maskSize / 2.0 + math.cos(angle) * distance,
      _maskSize / 2.0 + math.sin(angle) * distance,
      blobRadius,
      strength,
    );
  }
  return BrushTipMask(id: 'builtin-sponge', size: _maskSize, alpha: alpha);
}

/// Adds a radially fading blob, keeping the brighter of the two values so
/// overlapping blobs merge instead of banding.
void _stampSoftBlob(
  Uint8List alpha,
  double centerX,
  double centerY,
  double radius,
  int strength,
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
      final fade = 1.0 - distance / radius;
      final value = (strength * fade * fade).round();
      final offset = y * _maskSize + x;
      alpha[offset] = math.max(alpha[offset], value.clamp(0, 255));
    }
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
