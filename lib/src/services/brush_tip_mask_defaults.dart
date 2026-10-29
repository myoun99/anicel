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

/// The DECORATION tips (유저 확정 `brush-roster-Q1 = 2`: the whole roster in
/// one round, with its new procedural masks made together so their looks can
/// be judged side by side).
///
/// 🚨THEY ARE ANGULAR, which is what nothing here had: every mask above is a
/// disc modulated by DISTANCE, so a scatter brush could only ever throw
/// round blobs. A sparkle needs rays and a snowflake needs six of them, so
/// the law reads the pixel's ANGLE — and both of them read it the same way,
/// which is why there is one [_rayMask] and not two generators.
final BrushTipMask starBrushTipMask = _rayMask(
  'builtin-star',
  arms: 4,
  sharpness: 3.0,
  core: 0.16,
);
final BrushTipMask flakeBrushTipMask = _rayMask(
  'builtin-flake',
  arms: 6,
  sharpness: 6.0,
  core: 0.22,
);

/// A bubble: bright rim, hollow middle. ⚠️Not the wet blot's gain-at-the-rim
/// — that one still fills its interior, this one is empty there, which is
/// what makes a bubble read as glass rather than as a puddle.
final BrushTipMask ringBrushTipMask = _generateRingMask();

/// A leaf/blade: a pointed lens, so a scatter of them lands as foliage
/// rather than as dots. The one non-round footprint here.
final BrushTipMask leafBrushTipMask = _generateLeafMask();

/// A tuft of grass: thin blades rising from the bottom, each from a place
/// of its own, leaning its own way, as long as its own (F-462 ③, 유저
/// 2026-10-25 「팁의 한 소재끼리 다른곳 바라보고 다른 위치에 있어야하지
/// 않나」). ↩️Grass threw the leaf's lens five at a time across the stroke,
/// and every dab stood as one column of blades end to end (「너무 일직선」).
final BrushTipMask grassClumpBrushTipMask = _generateGrassClumpMask();

/// Canvas-anchored PAPER texture (see `textureMask`): seamless two-octave
/// noise. A texture mask is sampled with wrapping, so any discontinuity
/// across the tile edge would print a visible grid over the artwork.
final BrushTipMask paperGrainTextureMask = _generatePaperGrainMask();

/// Canvas-anchored WEAVE texture: over/under threads on an exact period, so
/// it tiles by construction.
final BrushTipMask canvasWeaveTextureMask = _generateCanvasWeaveMask();

/// Canvas-anchored COLD-PRESS watercolour paper (board F-218, 유저: 「질감
/// 있다면 그냥 수채가아니라 아날로그 수채라던가 … 질감도 진짜 아날로그질감
/// 종이질감」): the rounded tooth of mould-made paper, with pigment pooling in
/// the hollows between the bumps.
///
/// ⚠️256 texels, not the 64 of [paperGrainTextureMask]: tooth is a few
/// pixels across, and a 64-texel tile scaled up to read as paper repeats
/// every couple of centimetres of a stroke — the grid the eye finds first.
final BrushTipMask coldPressTextureMask = _generateColdPressMask();

/// 🚨THE SIDE OF A LEAD (유저 F-433, 2026-10-21: 「크게해서 dab 찍어보면 이건
/// 연필모양이아님. 그냥 그물모양임 … 진짜 연필처럼 딱딱한느낌? 실루엣」, and of
/// the laid state 「참고는 안둥글고 직각같은느낌」). A block with straight sides
/// and barely rounded corners, its rim broken only finely, its face nearly
/// solid. The tip squashed along the pen's lean is the strip a lead lying
/// flat leaves; upright, shrunk to a few pixels, it is the point.
///
/// ⛔NO GRAIN IN THE TIP: a tip scales with the dab, so grain baked into it
/// grows into the net the user saw on [grainBrushTipMask] at a large size.
/// The graphite's grain is the PAPER's ([graphiteToothTextureMask]), which
/// stays a pixel or two at any size.
///
/// 256 texels, like [coldPressTextureMask]: the edge is the point of this
/// tip, and at 64 a dab of a few hundred pixels would blur it.
final BrushTipMask pencilSideBrushTipMask = _generatePencilSideMask();

/// Paper TOOTH for graphite (F-433): a speckle a pixel across over a swell
/// of three, a share of it bare — the valleys a lead never reaches, which
/// is what keeps a heavy pass grained instead of filling to a flat tone.
final BrushTipMask graphiteToothTextureMask = _generateGraphiteToothMask();

/// A colouring pencil's scumble (F-433: the user's 「色鉛筆シャープ」 made into
/// a built-in). Soft wax clumps laid one way inside a wide ellipse, mostly
/// bare between them — a brush that turns every dab at random builds them
/// into a cloudy, grained fill. ↩️It was short strokes a few texels long
/// (`builtin-color-flecks`, 10-21), which the user found far finer than
/// their own brush (F-449): a new look is a new id.
///
/// ⛔Not the tip the user's own brush wore: that one was taken from another
/// program's brush (`tvpaint_色鉛筆_シャープ`), and a third party's brush may
/// not ship here (`ip-review-clean`). This is generated afresh to the same
/// purpose.
final BrushTipMask colorClumpBrushTipMask = _generateColorClumpMask();

/// 🚨THE LEAD, UPRIGHT TO FLAT, THREE WORN FACES A STEP (유저 F-451,
/// 2026-10-23: 「세웠을땐 사각형이 아니라 진짜 연필처럼 적어도 6각형이라던가
/// 둥글다던가」, while 「눕혀서 쓸땐 실루엣이 직각으로 떨어져졌으면 하는건
/// 좋은데」; F-456-Q4: 「기울기가 단계를 고르고, 그 단계 안에서 여러 장 중
/// 무작위」 — 「클튜 연필브러쉬가 팁을 한장이나 세장만 쓰고있으니 … 참고해서
/// 하면됨」). Six steps of one lead, from the facet its point wears upright —
/// a five-, six- or seven-sided face, worn round at the corners — squarer
/// step by step to the block its side lays flat, each step three faces
/// whose edges sit and chip differently ([pencilLeadFacesPerStep]). A
/// pencil's lean picks the step (`BrushTipOrder.lean`) and every dab throws
/// one of its faces (`BrushShape.tipsPerTurn`), so the line's edge breaks
/// somewhere new each dab and a stroke laid again fills what the first
/// missed.
///
/// ↩️F-451 gave each step one smooth footprint: every dab of a stroke laid
/// the same rim and only the paper broke the line — always in the same
/// place (F-456: 「결여가 너무 일정함(같은부분 다시 그려도 결여된 픽셀이
/// 안채워짐)」). A new look is a new id: `builtin-pencil-lead-*` are gone.
///
/// 🚨EACH IS HOW HARD THE LEAD PRESSES, not where it inks: whole in the
/// middle, easing to nothing at the rim, so the paper's tooth takes the
/// lightest touches first and the line's edge thins into grain.
///
/// 256 texels, like [pencilSideBrushTipMask]: the edge is the point, and at
/// 64 a laid dab of a few dozen pixels would blur it.
final List<BrushTipMask> pencilLeadBrushTipMasks = List.unmodifiable([
  for (var step = 0; step < _leadSquareness.length; step += 1)
    for (var face = 0; face < pencilLeadFacesPerStep; face += 1)
      _generatePencilLeadMask(step, face),
]);

/// How many faces each step of [pencilLeadBrushTipMasks] holds — what a
/// pencil wears as its `tipsPerTurn`.
const int pencilLeadFacesPerStep = 3;

/// 🗣️THE CRUMBS A LEAD LEAVES (F-462 ②, 유저 2026-10-25: 「클튜
/// 연필브러시들은 육각형식으로 안하니까 그거 참고해서 다시 개편. 육각형같은거
/// 잊어도됨」). Three lumpy rounds, each its own outline, whole through most of
/// its reach and easing to the rim, its face mottled — the way Clip Studio's
/// pencils draw: a few irregular tips thrown at random, each turned at
/// random, the paper's tooth doing the grain. The mottle is what moves the
/// grain dab to dab: under a paper worked by its height a texel the last dab
/// reached short of is reached by the next, so a line laid again fills in.
///
/// ⚠️64 texels, not the lead faces' 256: a pencil is a few pixels across,
/// and the tip sampler has no minification filter (F-462 ③'s tuft, the same
/// finding) — a 256 rim would stair there.
final List<BrushTipMask> pencilCrumbBrushTipMasks = List.unmodifiable([
  for (var crumb = 0; crumb < 3; crumb += 1) _generatePencilCrumbMask(crumb),
]);

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

/// [arms] rays out of a soft core: `cos(arms × θ)` raised to [sharpness],
/// fading to nothing at the rim, over a disc of solid centre [core].
///
/// ⚠️ONE GENERATOR FOR BOTH ANGULAR TIPS, parameterized rather than copied:
/// a sparkle is four sharp rays and a snowflake is six blunter ones, and
/// that is the whole difference between them. A third angular tip needs no
/// new function either.
BrushTipMask _rayMask(
  String id, {
  required int arms,
  required double sharpness,
  required double core,
}) => _discMask(id, (x, y, dx, edge) {
  // The core is solid, so the rays have something to come out of.
  if (edge <= core) {
    return 255.0;
  }
  final dy = y + 0.5 - _discCenter;
  final angle = math.atan2(dy, dx);
  final ray = math.max(0.0, math.cos(angle * arms));
  final along = math.pow(ray, sharpness).toDouble();
  // Rays thin out towards the rim rather than stopping at it.
  final reach = 1.0 - (edge - core) / (1.0 - core);
  return 255.0 * along * reach * reach;
});

/// An annulus: nothing inside, a bright band at [_ringRadius], nothing past
/// it. The band's own falloff is what keeps the edge from aliasing.
BrushTipMask _generateRingMask() => _discMask('builtin-ring', (x, y, dx, edge) {
  const band = 0.18;
  final offBand = (edge - _ringRadius).abs();
  if (offBand >= band) {
    return 0;
  }
  final across = 1.0 - offBand / band;
  return 255.0 * across * across;
});

/// Where the bubble's wall sits, as a fraction of the disc radius.
const double _ringRadius = 0.82;

/// A pointed lens — the intersection of two circles whose centres sit off
/// to either side, which is the cheapest shape that comes to a point at
/// both ends.
///
/// ⛔Not `_discMask`: that walks ONE disc and hands the law a distance from
/// its centre, and a lens is defined by its distance from two others. The
/// walk here is the whole buffer, which is also why the leaf may be longer
/// than the disc is wide.
BrushTipMask _generateLeafMask() {
  final alpha = Uint8List(_maskSize * _maskSize);
  // Two circles of this radius, centres pushed apart along x: the further
  // apart, the narrower and more pointed the leaf.
  const lensRadius = _maskSize * 0.62;
  const lensOffset = _maskSize * 0.40;
  for (var y = 0; y < _maskSize; y += 1) {
    for (var x = 0; x < _maskSize; x += 1) {
      final px = x + 0.5 - _discCenter;
      final py = y + 0.5 - _discCenter;
      final left = math.sqrt(
        (px + lensOffset) * (px + lensOffset) + py * py,
      );
      final right = math.sqrt(
        (px - lensOffset) * (px - lensOffset) + py * py,
      );
      final into = math.min(lensRadius - left, lensRadius - right);
      if (into <= 0) {
        continue;
      }
      // Solid along the spine, softening to the outline.
      final fill = math.min(1.0, into / (lensRadius * 0.22));
      alpha[y * _maskSize + x] = (255.0 * fill * fill).round().clamp(0, 255);
    }
  }
  return BrushTipMask(id: 'builtin-leaf', size: _maskSize, alpha: alpha);
}

/// Blades as bent strokes from a common ground: each a quadratic curve
/// from its root at the bottom, as wide as [_bladeWidth] there and coming
/// to a point at its tip, laid by the most of what covers a texel.
///
/// ⛔64 a side, like the other decoration tips — not the pencil's 256. The
/// tip is sampled bilinear with nothing to shrink it first, so at 256 a
/// tuft drawn at its own size (26–30 px, ten texels a pixel) broke every
/// blade's point into loose dots; at 64 the points taper. Drawn at 110 px
/// the 64 is a little softer at the edge (both measured 2026-10-29).
BrushTipMask _generateGrassClumpMask() {
  const side = _maskSize;
  final alpha = Uint8List(side * side);
  // (root across, lean from upright in degrees, length, bend) — the root
  // and the length as parts of the side, the bend as a part of the length
  // to the blade's right at its middle.
  const blades = <(double, double, double, double)>[
    (0.40, -34, 0.56, -0.10),
    (0.45, -18, 0.80, -0.06),
    (0.49, -6, 0.62, 0.05),
    (0.52, 4, 0.95, 0.04),
    (0.56, 16, 0.74, 0.08),
    (0.61, 30, 0.60, 0.12),
  ];
  for (final (root, lean, length, bend) in blades) {
    final radians = lean * math.pi / 180;
    final reach = length * side;
    final fromX = root * side;
    const fromY = side * 0.98;
    final toX = fromX + math.sin(radians) * reach;
    final toY = fromY - math.cos(radians) * reach;
    // The bend pulls the middle off the chord, square to it.
    final midX = (fromX + toX) / 2 + math.cos(radians) * bend * reach;
    final midY = (fromY + toY) / 2 + math.sin(radians) * bend * reach;
    final steps = reach.ceil() * 2;
    for (var step = 0; step <= steps; step += 1) {
      final t = step / steps;
      final u = 1 - t;
      final x = u * u * fromX + 2 * u * t * midX + t * t * toX;
      final y = u * u * fromY + 2 * u * t * midY + t * t * toY;
      final rim = _bladeWidth * side * u / 2 + 0.5;
      _stampDisc(alpha, x, y, rim, _coveringDot(rim));
    }
  }
  return BrushTipMask(id: 'builtin-grass-clump', size: side, alpha: alpha);
}

/// How wide a blade is at its root, as a part of the tuft's side.
const double _bladeWidth = 0.08;

/// A dot of radius [rim] solid to within a texel of its rim and falling off
/// over that last texel — a blade's edge, smoothed in the mask itself.
_DiscLaw _coveringDot(double rim) =>
    (x, y, dx, edge) => 255 * ((1.0 - edge) * rim).clamp(0.0, 1.0);

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

/// The value law [_textureMask] asks at every texel: the texel's cell ([x],
/// [y]) and its [index] in the alpha, row-major. The mask rounds and clamps
/// the answer to a byte.
typedef _TexelLaw = double Function(int x, int y, int index);

/// A mask laid texel by texel by [law] over the whole of its [size]×[size]
/// — ONE walk for every texture and every tip that fills its square, as
/// [_discMask] is for the round tips. ↩️Each generator kept its own walk
/// until the pencils (F-433) brought the fifth.
BrushTipMask _textureMask(String id, _TexelLaw law, {int size = _maskSize}) {
  final alpha = Uint8List(size * size);
  for (var index = 0; index < alpha.length; index += 1) {
    alpha[index] =
        law(index % size, index ~/ size, index).round().clamp(0, 255);
  }
  return BrushTipMask(id: id, size: size, alpha: alpha);
}

/// Paper tooth: two octaves of wrapping value noise, kept in the upper half
/// of the range so the texture bites into a stroke without erasing it.
BrushTipMask _generatePaperGrainMask() {
  final coarse = _seamlessValueNoise(8, 0x68E31DA4);
  final fine = _seamlessValueNoise(16, 0xB5297A4D);
  return _textureMask('builtin-paper-grain', (x, y, index) {
    final noise = coarse[index] * 0.6 + fine[index] * 0.4;
    return 255 * (0.35 + noise * 0.65);
  });
}

/// Canvas weave: warp and weft threads alternating over and under on an
/// 8px period, which divides the mask exactly — no seam arithmetic needed.
BrushTipMask _generateCanvasWeaveMask() {
  const period = 8;
  return _textureMask('builtin-canvas-weave', (x, y, index) {
    final overUnder = ((x ~/ period) + (y ~/ period)).isEven;
    // The thread on top is shaded across its width; the one beneath keeps a
    // dimmer, flatter face.
    final across = overUnder ? y % period : x % period;
    final profile = 1.0 - ((across + 0.5) / period - 0.5).abs() * 2.0;
    final value = overUnder ? 0.55 + profile * 0.45 : 0.4 + profile * 0.3;
    return 255 * value;
  });
}

/// Cold-press paper: three layers of height, each wrapping at the tile edge.
///
/// - TOOTH — the rounded hills the paper is felted into: one freely
///   jittered point per 16-texel cell, each raising a soft dome
///   `crown · (1 − (d/R)²)²` that reaches past its own cell, so neighbouring
///   domes run into each other the way the tooth of a sheet does, with soft
///   hollows between them rather than lines. Each dome draws its own crown,
///   so the tooth is not a lattice. The search runs across the wrapped
///   neighbour cells, so a dome on one edge continues on the other.
/// - SWELL — the sheet's slow undulation, 8-lattice value noise.
/// - FIBRE — fine felt, 64-lattice value noise.
///
/// The mask is how much paint stays: the hollows hold the most (pigment
/// settles there), the crowns the least — kept above 0.3 so the paper
/// grains a wash without breaking it.
///
/// ⚠️Arithmetic only — no `exp`, no `pow`. The bytes are pinned by their sum
/// (`brush_tip_mask_defaults_test`), and a library function may round its
/// last bit differently on another platform.
BrushTipMask _generateColdPressMask() {
  const size = 256;
  final (tooth, highest) = _coldPressTooth(size);
  final swell = _seamlessValueNoise(8, 0x51ED270B, size: size);
  final fibre = _seamlessValueNoise(64, 0x7C3A9E25, size: size);
  return _textureMask('builtin-cold-press', size: size, (x, y, index) {
    final height =
        tooth[index] / highest * 0.65 + swell[index] * 0.2 + fibre[index] * 0.15;
    // Smoothstep of the depth: broad hollows, broad crowns.
    final depth = (1.0 - height).clamp(0.0, 1.0);
    final paint = 0.3 + depth * depth * (3.0 - 2.0 * depth) * 0.7;
    return 255 * paint;
  });
}

/// The cold-press TOOTH (see [_generateColdPressMask]): the dome heights of
/// a [size]-texel tile, row-major, and the highest of them.
(List<double>, double) _coldPressTooth(int size) {
  const cell = 16;
  final cells = size ~/ cell;
  const reach = cell * 1.1;
  final pointX = List<double>.filled(cells * cells, 0);
  final pointY = List<double>.filled(cells * cells, 0);
  final crown = List<double>.filled(cells * cells, 0);
  final draw = _Draws(0x2F6B3A91).next;
  for (var index = 0; index < cells * cells; index += 1) {
    pointX[index] = (index % cells + draw()) * cell;
    pointY[index] = (index ~/ cells + draw()) * cell;
    crown[index] = 0.5 + draw() * 0.5;
  }
  final tooth = List<double>.filled(size * size, 0);
  var highest = 0.0;
  for (var y = 0; y < size; y += 1) {
    final cy = y ~/ cell;
    for (var x = 0; x < size; x += 1) {
      final cx = x ~/ cell;
      var height = 0.0;
      for (var oy = -2; oy <= 2; oy += 1) {
        for (var ox = -2; ox <= 2; ox += 1) {
          final nx = (cx + ox) % cells;
          final ny = (cy + oy) % cells;
          final n = ny * cells + nx;
          // The neighbour's point, moved to the side of the tile this texel
          // sees it from, so distances run across the seam.
          final dx = x + 0.5 - (pointX[n] + (cx + ox - nx) * cell);
          final dy = y + 0.5 - (pointY[n] + (cy + oy - ny) * cell);
          final reached = (dx * dx + dy * dy) / (reach * reach);
          if (reached < 1.0) {
            final dome = 1.0 - reached;
            height += crown[n] * dome * dome;
          }
        }
      }
      tooth[y * size + x] = height;
      if (height > highest) {
        highest = height;
      }
    }
  }
  return (tooth, highest);
}

/// The side of a lead ([pencilSideBrushTipMask]): halfway between the
/// fourth- and the eighth-power superellipse — square enough to read as a
/// cut block, round enough at the corners not to read as a stamp — its rim
/// moved in and out by a fine noise, its face mottled by a slow one.
///
/// ⚠️`sqrt` only, no `pow`: the bytes are pinned by their sum, and `sqrt` is
/// the one root every platform rounds alike.
BrushTipMask _generatePencilSideMask() {
  const size = 256;
  const centre = size / 2.0;
  const radius = size / 2.0 - 3.0;
  final ragged = _seamlessValueNoise(48, 0x3C6EF372, size: size);
  final mottle = _seamlessValueNoise(7, 0x2545F491, size: size);
  return _textureMask('builtin-pencil-side', size: size, (x, y, index) {
    final down = (y + 0.5 - centre) / radius;
    final down4 = down * down * down * down;
    final across = (x + 0.5 - centre) / radius;
    final across4 = across * across * across * across;
    final fourth = math.sqrt(math.sqrt(across4 + down4));
    final eighth = math.sqrt(
      math.sqrt(math.sqrt(across4 * across4 + down4 * down4)),
    );
    final reach = (fourth + eighth) / 2.0;
    final rim = 0.988 + ragged[index] * 0.024;
    // A texel and a half of ramp across the rim: hard, never aliased.
    final cover = ((rim - reach) * radius / 1.5 + 0.5).clamp(0.0, 1.0);
    return 255 * cover * (0.9 + mottle[index] * 0.1);
  });
}

/// How far from the facet towards the block each step of
/// [pencilLeadBrushTipMasks] lies: 0 the facet [_leadFacet] cuts, 1 the
/// fourth-power superellipse [_superReach] draws, 2 the eighth, 3 the
/// sixteenth, and between two of them their reaches mixed. A pen held as
/// one writes leans about 0.4 and a Wacom pen reports little past 0.65
/// (`_leanRows`), so the first three stay near the facet and the block
/// arrives where the lean runs out.
const _leadSquareness = [0.0, 0.3, 0.75, 1.6, 2.4, 3.0];

/// How much of a lead's reach presses whole before it eases to the rim
/// ([pencilLeadBrushTipMasks]): the band left is where the paper's tooth
/// thins the edge.
const _leadWhole = 0.9;

/// How far a face's chipped rim moves in and out of its reach
/// ([pencilLeadBrushTipMasks]).
const _leadChipping = 0.12;

/// One face of a lead ([pencilLeadBrushTipMasks]): its reach between the
/// facet [_leadFacet] cuts and the superellipses, as far along as
/// [_leadSquareness] names, its rim chipped by a noise of its own; whole
/// out to [_leadWhole] of it, then easing as `(1 - s²)²` to the rim.
BrushTipMask _generatePencilLeadMask(int step, int face) {
  const size = 256;
  const centre = size / 2.0;
  const radius = size / 2.0 - 1.0;
  final along = _leadSquareness[step];
  final lower = math.min(along.floor(), 2);
  final mix = along - lower;
  final seed = 0x1EAD + step * 97 + face * 31;
  final facet = _leadFacet(face, seed);
  final chips = _seamlessValueNoise(24, seed, size: size);
  final id = 'builtin-pencil-face-$step-$face';
  return _textureMask(id, size: size, (x, y, index) {
    final u = (x + 0.5 - centre) / radius;
    final v = (y + 0.5 - centre) / radius;
    final from = lower == 0 ? facet(u, v) : _superReach(u, v, lower);
    final reach =
        (from * (1.0 - mix) + _superReach(u, v, lower + 1) * mix) *
        (1.0 + (chips[index] - 0.5) * _leadChipping);
    if (reach >= 1.0) {
      return 0.0;
    }
    if (reach <= _leadWhole) {
      return 255.0;
    }
    final s = (reach - _leadWhole) / (1.0 - _leadWhole);
    final ease = 1.0 - s * s;
    return 255.0 * ease * ease;
  });
}

/// The facet a lead's point wears upright ([pencilLeadBrushTipMasks]): five,
/// six or seven edges by [face] — the user's 「6각형 5각형」 — each turned a
/// little off the regular face and set back a little, its corners worn
/// round by summing the edges' sixteenth powers. 1 on its rim.
double Function(double u, double v) _leadFacet(int face, int seed) {
  final draws = _Draws(seed);
  final edges = [
    for (final (across, down) in _facetNormals[face])
      _turnedEdge(
        across,
        down,
        turn: (draws.next() - 0.5) * 0.5,
        back: 0.82 + draws.next() * 0.18,
      ),
  ];
  return (u, v) {
    var sum = 0.0;
    for (final (across, down, back) in edges) {
      final reach = (across * u + down * v) / back;
      if (reach > 0.0) {
        final square = reach * reach;
        final fourth = square * square;
        final eighth = fourth * fourth;
        sum += eighth * eighth;
      }
    }
    return math.sqrt(math.sqrt(math.sqrt(math.sqrt(sum))));
  };
}

/// An edge of [_leadFacet]: its outward normal ([across], [down]) turned by
/// the sine [turn], and how far out it stands, [back].
(double, double, double) _turnedEdge(
  double across,
  double down, {
  required double turn,
  required double back,
}) {
  final keep = math.sqrt(1.0 - turn * turn);
  return (across * keep - down * turn, across * turn + down * keep, back);
}

/// The outward normals of the regular faces of five, six and seven sides
/// ([_leadFacet]) — written out, not turned by `cos`: the bytes are pinned
/// by their sum, and only `sqrt` rounds alike on every platform.
const _facetNormals = <List<(double, double)>>[
  [
    (1.0, 0.0),
    (0.30901699437494745, 0.9510565162951535),
    (-0.8090169943749473, 0.5877852522924732),
    (-0.8090169943749475, -0.587785252292473),
    (0.30901699437494723, -0.9510565162951536),
  ],
  [
    (1.0, 0.0),
    (0.5, 0.8660254037844386),
    (-0.5, 0.8660254037844387),
    (-1.0, 0.0),
    (-0.5, -0.8660254037844385),
    (0.5, -0.8660254037844386),
  ],
  [
    (1.0, 0.0),
    (0.6234898018587336, 0.7818314824680298),
    (-0.22252093395631434, 0.9749279121818236),
    (-0.900968867902419, 0.43388373911755823),
    (-0.9009688679024191, -0.433883739117558),
    (-0.2225209339563146, -0.9749279121818236),
    (0.6234898018587334, -0.7818314824680299),
  ],
];

/// Where ([u], [v]) lies on the superellipse of power `2^(order + 1)` — 1
/// on its rim: [order] 0 the circle, 1 the fourth power, 2 the eighth, 3 the
/// sixteenth.
///
/// ⚠️`sqrt` only, no `pow`: the bytes are pinned by their sum, and `sqrt` is
/// the one root every platform rounds alike.
double _superReach(double u, double v, int order) {
  var across = u * u;
  var down = v * v;
  for (var square = 0; square < order; square += 1) {
    across *= across;
    down *= down;
  }
  var reach = across + down;
  for (var root = 0; root <= order; root += 1) {
    reach = math.sqrt(reach);
  }
  return reach;
}

/// One crumb of [pencilCrumbBrushTipMasks]: a round whose reach a slow noise
/// moves in and out by a quarter — its lumps — whole out to 0.7 of it, then
/// easing as `(1 - s²)²` to the rim, every texel of it mottled down by up to
/// three tenths.
BrushTipMask _generatePencilCrumbMask(int crumb) {
  const centre = _maskSize / 2.0;
  const radius = _maskSize / 2.0 - 1.5;
  final lumps = _seamlessValueNoise(5, 0xC0B + crumb * 77);
  final mottle = _seamlessValueNoise(16, 0x3A7 + crumb * 131);
  return _textureMask('builtin-pencil-crumb-$crumb', (x, y, index) {
    final u = (x + 0.5 - centre) / radius;
    final v = (y + 0.5 - centre) / radius;
    final reach =
        math.sqrt(u * u + v * v) * (1.0 + (lumps[index] - 0.5) * 0.5);
    if (reach >= 1.0) {
      return 0.0;
    }
    var cover = 1.0;
    if (reach > 0.7) {
      final s = (reach - 0.7) / 0.3;
      cover = (1.0 - s * s) * (1.0 - s * s);
    }
    return 255.0 * cover * (0.7 + 0.3 * mottle[index]);
  });
}

/// Graphite tooth ([graphiteToothTextureMask]): per texel a hashed speck
/// (six parts) over a three-texel swell (four parts), cut so the lowest
/// part of the range is bare and the top fills. It tiles: the speck is the
/// texel's own and the swell's lattice wraps.
BrushTipMask _generateGraphiteToothMask() {
  const size = 256;
  final swell = _seamlessValueNoise(85, 0xB5297A4D, size: size);
  return _textureMask('builtin-graphite-tooth', size: size, (x, y, index) {
    final speck = _texelHash(x, y) / 65535.0;
    final height = speck * 0.6 + swell[index] * 0.4;
    return 255 * ((height - 0.15) / 0.6).clamp(0.0, 1.0);
  });
}

/// A texel's own 16 pseudo-random bits, from its cell alone. ⛔Not a walk of
/// [_nextSeed]: a stream read texel by texel lays its low bits down the
/// rows, and the eye finds the stripes in a speckle one texel across.
int _texelHash(int x, int y) {
  var hash = (x * 374761393 + y * 668265263) & 0xFFFFFFFF;
  hash = ((hash ^ (hash >> 13)) * 1274126177) & 0xFFFFFFFF;
  return (hash ^ (hash >> 16)) & 0xFFFF;
}

/// Colour clumps ([colorClumpBrushTipMask]): soft wax clumps laid one way
/// inside a wide ellipse — each a flattened oval, fading from its middle,
/// mottled by a fine noise within, sparse in most of the patch and heavy
/// where they pile up. Where one lands is drawn against the ellipse's
/// falloff and a slow envelope.
///
/// 🔬Sized against the tip the user's own brush wore (F-449, 2026-10-23:
/// 「기존 tvp해당브러시 팁에 비해 … 분자들이 너무 작음. 그래서 너무 해칭이
/// 세세해진느낌」), by its statistics, not its pixels: the length at which a
/// texel stops resembling its neighbour (1/e of the autocorrelation) was 17
/// along and 5 across there, against 5 and 1 for the strokes this replaced;
/// the middle of the patch was mostly bare (four in five texels under a
/// quarter) round a few dense clumps.
BrushTipMask _generateColorClumpMask() {
  const size = 256;
  const centre = size / 2.0;
  const radius = size / 2.0 - 4.0;
  const aspect = 1.8;
  final envelope = _seamlessValueNoise(6, 0x1234567, size: size);
  final mottle = _seamlessValueNoise(64, 0x0C0FFEE, size: size);
  final fine = _seamlessValueNoise(128, 0x5EEDF1, size: size);
  final laid = List<double>.filled(size * size, 0);
  final draw = _Draws(0x5EED).next;
  var placed = 0;
  while (placed < 95) {
    final across = draw() * 2.0 - 1.0;
    final down = draw() * 2.0 - 1.0;
    final reach = across * across + down * down;
    if (reach >= 1.0) {
      continue;
    }
    final centreX = centre + across * radius;
    final centreY = centre + down / aspect * radius;
    final cell = centreY.floor() * size + centreX.floor();
    if (draw() > (1.0 - reach * reach) * (0.3 + 0.7 * envelope[cell])) {
      continue;
    }
    placed += 1;
    final halfLength = 13.0 + draw() * 26.0;
    final halfHeight = halfLength * (0.2 + draw() * 0.1);
    final slope = (draw() * 2.0 - 1.0) * 0.2;
    final strength = 0.15 + draw() * 0.85;
    final (left, right) = _texelSpan(centreX, halfLength, size);
    for (var x = left; x <= right; x += 1) {
      final dx = x - centreX;
      final middle = centreY + dx * slope;
      final (top, bottom) = _texelSpan(middle, halfHeight, size);
      for (var y = top; y <= bottom; y += 1) {
        final u = dx / halfLength;
        final v = (y - middle) / halfHeight;
        final reachIn = u * u + v * v;
        if (reachIn >= 1.0) {
          continue;
        }
        final index = y * size + x;
        final fall = (1.0 - reachIn) * (1.0 - reachIn);
        // The mottle read at half the column: twice as long as it is tall,
        // as the clumps are.
        final textured = mottle[y * size + x ~/ 2] * 0.75 + fine[index] * 0.25;
        final grain = ((textured - 0.3) / (1.0 - 0.3)).clamp(0.0, 1.0);
        laid[index] += strength * fall * grain * (1.0 - laid[index]);
      }
    }
  }
  return _textureMask(
    'builtin-color-clumps',
    size: size,
    (x, y, index) => 255 * laid[index].clamp(0.0, 1.0),
  );
}

/// Value noise on a [lattice]×[lattice] grid, smoothly interpolated up to
/// the mask size with the lattice WRAPPING at both edges — that wrap is what
/// makes the result tile seamlessly.
List<double> _seamlessValueNoise(
  int lattice,
  int seed, {
  int size = _maskSize,
}) {
  final draws = _Draws(seed);
  final grid = List<double>.generate(
    lattice * lattice,
    (_) => draws.next(),
    growable: false,
  );

  double smooth(double t) => t * t * (3.0 - 2.0 * t);

  final result = List<double>.filled(size * size, 0);
  final scale = lattice / size;
  for (var y = 0; y < size; y += 1) {
    final sampleY = y * scale;
    final y0 = sampleY.floor() % lattice;
    final y1 = (y0 + 1) % lattice;
    final ty = smooth(sampleY - sampleY.floor());
    for (var x = 0; x < size; x += 1) {
      final sampleX = x * scale;
      final x0 = sampleX.floor() % lattice;
      final x1 = (x0 + 1) % lattice;
      final tx = smooth(sampleX - sampleX.floor());
      final top =
          grid[y0 * lattice + x0] * (1 - tx) + grid[y0 * lattice + x1] * tx;
      final bottom =
          grid[y1 * lattice + x0] * (1 - tx) + grid[y1 * lattice + x1] * tx;
      result[y * size + x] = top * (1 - ty) + bottom * ty;
    }
  }
  return result;
}

/// Deterministic 31-bit LCG so the masks are identical everywhere.
int _nextSeed(int seed) => (seed * 1103515245 + 12345) & 0x7FFFFFFF;

/// The [_nextSeed] stream read as fractions of one: bits 8..23 of each next
/// state over 65535 — ONE reading for every generator that draws from it
/// (the value noise's lattice, the cold press's domes, the colour flecks).
/// ↩️Each kept its own until the flecks (F-433) brought the third.
final class _Draws {
  _Draws(this._state);

  int _state;

  double next() {
    _state = _nextSeed(_state);
    return ((_state >> 8) & 0xFFFF) / 65535.0;
  }
}

/// Stamps a disc of [radius] at ([centerX], [centerY]) into [alpha]: [law]
/// at each covered pixel, max-blended so overlapping blobs merge instead of
/// banding. Every byte a bundled tip holds comes through here, so the file
/// header's freeze applies to this walk above all.
///
/// 🚨ONE stamp for the splatter's dots (linear) and the soft blobs
/// (squared) — the audit's clone scan, 2026-09-03 — and the grass blades'
/// smoothed edge (F-462). [law] keeps each caller's own multiplication
/// order, so the generated bytes are theirs.
void _stampDisc(
  Uint8List alpha,
  double centerX,
  double centerY,
  double radius,
  _DiscLaw law,
) {
  final (left, right) = _texelSpan(centerX, radius, _maskSize);
  final (top, bottom) = _texelSpan(centerY, radius, _maskSize);
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

/// The texels a shape reaching [reach] either side of [centre] covers,
/// clipped to a mask [size] across — first and last, both inclusive. The
/// disc stamp's box and each clump's columns and rows (F-449, the clone
/// scan) are the one walk.
(int, int) _texelSpan(double centre, double reach, int size) => (
  math.max(0, (centre - reach).floor()),
  math.min(size - 1, (centre + reach).ceil()),
);

/// A dot of [strength] that fades linearly to the rim.
_DiscLaw _linearDot(int strength) =>
    (x, y, dx, edge) => strength * (1.0 - edge);

/// A soft dot of [strength]: the linear fade squared, so the blob has no
/// hard shoulder.
_DiscLaw _softDot(int strength) => (x, y, dx, edge) {
  final fade = 1.0 - edge;
  return strength * fade * fade;
};
