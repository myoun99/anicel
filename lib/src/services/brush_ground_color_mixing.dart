import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../core/argb_channels.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_shape.dart';
import 'brush_dab_share.dart';
import 'brush_pressure_dynamics.dart';

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
  BrushGroundColorMixer({required this.shape, this.random});

  final BrushShape shape;

  /// The ランダム row's dice for 絵の具量 and 絵の具濃度 — the stroke's own,
  /// as [applyBrushInputDynamics] takes its. Without them that row is
  /// skipped.
  final math.Random? random;

  /// The paint currently on the brush. Null until the first dab seeds it
  /// from the brush colour.
  ///
  /// ⚠️UNROUNDED: a dab moves it by a fraction of a stamp's pull, and at a
  /// low 물감량 that is a fraction of a level — rounded each dab, it
  /// rounded back, and a wet watercolour that crossed red stayed red to
  /// the end of the stroke (measured 2026-10-30: 125 → 125 over twenty of
  /// its widths). Only what a dab lays is rounded.
  _Paint? _reservoir;

  /// How much paint a DRY brush holds, 0..1 — one whose paint amount is 0
  /// carries no drawing colour, only what it picked up ([apply]).
  double _held = 0.0;

  bool get isActive => shape.picksUpGround;

  /// Returns [dabs] with their deposit colours resolved.
  ///
  /// [sample] reads the composite as of the START of this batch. A dab does
  /// not see the dabs beside it in the same batch — the rasterizer works a
  /// pointer-move at a time and forcing a rasterize per dab would undo that
  /// batching. The reservoir still carries across every dab, which is what
  /// actually produces the smear.
  ///
  /// 🗣️THE BRUSH COMES BACK TO ITS OWN COLOUR (gouache card Q3 = c, Q8 = a,
  /// 2026-10-24: fitted to the user's Clip Studio strokes — 유채 · 진한 수채 ·
  /// 불투명 수채 · 투명 수채 · 구아슈 · 수채 섞기 crossing red, yellow and black
  /// bands, `参考/CSP_decode/mixing`). Each dab:
  /// • picks the ground up, a whole stamp lifting [_pickPerStamp] of it at
  ///   色延び 0 and none at 1 — Clip Studio's manual: the higher the stretch,
  ///   the further the picked colour is drawn out (it lingers);
  /// • is refilled with the drawing colour, a stamp by [_refillPerStamp] ×
  ///   絵の具量² — so a blue 유채 (40) that crossed red is purple for a long
  ///   way and comes back to blue, a 진한 수채 (70) soon;
  /// • lays what it carries with [_drawingLaid] × 絵の具量 of the drawing
  ///   colour on top, at 絵の具濃度 as before.
  /// 🔬Against the sample's stroke centres every 20px (RGB RMS): 유채 92 →
  /// 12, 진한 수채 124 → 25. 불투명 · 투명 수채 and 구아슈 stay ~45–70 under
  /// every law tried. Their 絵の具量 · 絵の具濃度 follow the pen in Clip
  /// Studio, and since Q9 those rows come in ([_ofDab]): at the steady
  /// press that fits each best, 불투명 수채 71 → 42, 구아슈 54 → 52, 진한
  /// 수채 25 → 22, 유채 12 as it was, but 투명 수채 44 → 69 — its 濃度
  /// falls with the press from 0, and the sample was drawn at no press we
  /// know. The constants were not fitted again.
  /// ↩️Until then the reservoir was never refilled — a blue oil brush that
  /// crossed red was red to the end of the stroke — and the stretch was how
  /// much a stamp lifted.
  ///
  /// A brush with no 絵の具量 is DRY (수채 섞기: 「필압 최대로 그려도 색이
  /// 안 나옴, 다른 칠해진 색을 섞을 뿐」): it lays nothing on bare canvas and
  /// carries what it picked up as thick as it was, thinning over bare
  /// canvas at the pickup's rate. 絵の具濃度 is the drawing colour's, and it
  /// carries none.
  List<BrushDab> apply(
    List<BrushDab> dabs, {
    required BrushGroundColorSampler sample,
  }) {
    if (!isActive || dabs.isEmpty) {
      return dabs;
    }
    final stretch = shape.colorStretch.clamp(0.0, 1.0);
    final pickPerStamp = (1.0 - stretch) * _pickPerStamp;

    final mixed = <BrushDab>[];
    for (final dab in dabs) {
      final sourceArgb = dab.color;
      final drawing = _Paint.of(sourceArgb);
      final ground = sample(dab.center.x, dab.center.y, dab.size / 2.0);
      // ⚠️DRY IS THE BRUSH'S, NOT THE DAB'S — my reading, not the user's: a
      // 絵の具量 its curve presses down to 0 is a loaded brush laying none
      // of its own colour this dab, still laying what it carries at its
      // 絵の具濃度; only a 絵の具量 set to 0 makes the 수채 섞기 that lays
      // nothing on bare canvas.
      final (:deposit, :thickness) = shape.paintAmount > 0.0
          ? _laidLoaded(dab, drawing, ground, pickPerStamp)
          : _laidDry(dab, drawing, ground, pickPerStamp);
      final alpha = (argbAlpha(sourceArgb) * thickness).round().clamp(0, 255);
      mixed.add(dab.copyWith(color: (alpha << 24) | deposit.rgb));
    }
    return mixed;
  }

  /// What a loaded brush lays at [dab] over [ground] — the reservoir picks
  /// the ground up and is refilled with [drawing] by the dab's 絵の具量, and
  /// lays at its 絵の具濃度 ([apply]).
  _Laid _laidLoaded(
    BrushDab dab,
    _Paint drawing,
    BrushGroundSample ground,
    double pickPerStamp,
  ) {
    final amount = _ofDab(
      dab,
      BrushPressureTarget.paintAmount,
      shape.paintAmount,
    );
    var carried = _reservoir ?? drawing;
    // Bare canvas has no colour to lift; the brush keeps what it holds.
    if (ground.coverage > 0.0) {
      carried = carried.towards(
        _Paint.of(ground.rgb),
        _pickedUp(dab, pickPerStamp * ground.coverage),
      );
    }
    carried = carried.towards(
      drawing,
      _pickedUp(dab, amount * amount * _refillPerStamp),
    );
    _reservoir = carried;
    return (
      deposit: carried.towards(drawing, amount * _drawingLaid),
      thickness: _ofDab(
        dab,
        BrushPressureTarget.paintDensity,
        shape.paintDensity,
      ),
    );
  }

  /// What a dry brush lays at [dab] over [ground] — what it picked up, as
  /// thick as it holds it ([apply]).
  _Laid _laidDry(
    BrushDab dab,
    _Paint drawing,
    BrushGroundSample ground,
    double pickPerStamp,
  ) {
    final take = _pickedUp(dab, pickPerStamp);
    final held = _held + (ground.coverage - _held) * take;
    if (held > 0.0) {
      final lifted = _Paint.of(ground.rgb);
      _reservoir = (_reservoir ?? lifted).towards(
        lifted,
        ground.coverage * take / held,
      );
    }
    _held = held;
    return (deposit: _reservoir ?? drawing, thickness: held);
  }

  /// [target]'s setting for [dab]: the brush's [base], through the curves
  /// the dab's inputs reach — size's and flow's own reading
  /// ([brushInputFactor]).
  double _ofDab(BrushDab dab, BrushPressureTarget target, double base) =>
      (base * brushInputFactor(dab, shape, target, random: random)).clamp(
        0.0,
        1.0,
      );
}

/// What a dab lays: the colour, and how thick of its alpha.
typedef _Laid = ({_Paint deposit, double thickness});

/// What a whole stamp lifts of the ground at 色延び 0 ([BrushGroundColorMixer]
/// — fitted to the user's Clip Studio strokes).
const double _pickPerStamp = 0.12;

/// How far a whole stamp refills the brush with its drawing colour at 絵の具量
/// 1 — by 絵の具量², fitted with [_pickPerStamp].
const double _refillPerStamp = 0.12;

/// The share of the drawing colour a dab lays over what the brush carries at
/// 絵の具量 1, fitted with [_pickPerStamp].
const double _drawingLaid = 0.3;

/// How far [dab] moves the reservoir — toward the ground it lifts, or the
/// drawing colour it is refilled with — where a whole stamp would move it
/// by [pull]: its share of that stamp ([stampShareOf]).
///
/// 🚨THE STRETCH DRAGS AS FAR AT EVERY SPACING — the flow's law, through the
/// flow's own numbers (유저 2026-10-01 「엔진이 쌓임을 환산 — 크기와 무관하게
/// (클튜처럼)」 · 「모든 브러시」; board `mixing-strength-follows-the-dab-spacing`).
/// A pickup compounds dab after dab exactly as a laid alpha piles, and it
/// was taken whole by every dab: a brush laid a pixel apart lifted its
/// stretch several times over the length one laid a tenth of its size apart
/// lifts it once, so one 색 늘이기 dragged a different distance at every
/// size and spacing.
double _pickedUp(BrushDab dab, double pull) {
  final share = stampShareOf(dab);
  return share >= 1.0 ? pull : evenedLaid(eveningTableFor(share), pull);
}

/// A colour on the brush, 0..255 a channel and unrounded
/// ([BrushGroundColorMixer._reservoir]).
final class _Paint {
  const _Paint(this.red, this.green, this.blue);

  _Paint.of(int rgb)
    : this(
        argbRed(rgb).toDouble(),
        argbGreen(rgb).toDouble(),
        argbBlue(rgb).toDouble(),
      );

  final double red;
  final double green;
  final double blue;

  /// This moved [t] of the way to [to], channel by channel.
  _Paint towards(_Paint to, double t) {
    if (t <= 0.0) {
      return this;
    }
    if (t >= 1.0) {
      return to;
    }
    return _Paint(
      red + (to.red - red) * t,
      green + (to.green - green) * t,
      blue + (to.blue - blue) * t,
    );
  }

  /// 0xRRGGBB, each channel rounded.
  int get rgb {
    int channel(double value) => value.round().clamp(0, 255);
    return (channel(red) << 16) | (channel(green) << 8) | channel(blue);
  }
}
