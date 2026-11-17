import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_shape.dart';
import 'brush_dab_share.dart';
import 'brush_pressure_dynamics.dart';

/// Makes each dab of a mixing brush a step of the stroke's chain — the
/// colour it deposits is the engine's to resolve, one dab at a time.
///
/// Clip Studio's 밑바탕 혼색 and Photoshop's Mixer Brush are one model: the
/// brush carries a reservoir of paint, each dab lifts colour from the canvas
/// into it, then puts a blend of the two back down. The deposit colour is
/// resolved AT PLACEMENT, a step a dab, and laid as the dab's own colour —
/// the dab kernel never learns about mixing — and pen-up bakes it into the
/// dabs the stroke keeps, so the commit, undo replay and the .anicel lay
/// the stored dabs byte-identically ([BrushDab.mixedAs]).
///
/// One reservoir lives per stroke, so the steps run in stroke order. That
/// ordering is load-bearing: the rasterizers may never reorder or
/// parallelise dabs within a stroke.
///
/// ↩️THE GROUND IS READ ON THE ENGINE (board
/// `the-mixing-brush-reads-a-whole-tile-back-for-its-ground`, 11-17; 🗣️유저
/// 「cpu로하는거 최대한 전부 gpu로 · 진짜 cpu가 빠를수밖에 없는거만 cpu로」):
/// till then this resolved the colour itself, reading an 8×8 grid of the
/// cel under each dab — and a tile the engine had made was read back whole
/// the first time a dab met it, a wait for all the GPU had been handed
/// (the stroke's own dabs among it), and kept on the CPU besides. What
/// stays here is what does not read the ground: the brush's curves and
/// dice, made in the stroke's order as before. The walk — the ground, the
/// reservoir — is the engine's (gpu_engine `mix.wgsl`).
class BrushGroundColorMixer {
  BrushGroundColorMixer({required this.shape, this.random});

  final BrushShape shape;

  /// The ランダム row's dice for 絵の具量 and 絵の具濃度 — the stroke's own,
  /// as [applyBrushInputDynamics] takes its. Without them that row is
  /// skipped.
  final math.Random? random;

  /// The next step's place in the stroke's chain.
  int _steps = 0;

  bool get isActive => shape.picksUpGround;

  /// Returns [dabs], each naming its step of the chain ([BrushDab.mix]).
  ///
  /// A step reads the cel as it stood when the stroke began, under the dab
  /// where it lands — after the dynamics, which move it. It does not see
  /// the stroke's own dabs; the reservoir carries across every dab, which
  /// is what actually produces the smear.
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
  /// ⚠️DRY IS THE BRUSH'S, NOT THE DAB'S — my reading, not the user's: a
  /// 絵の具量 its curve presses down to 0 is a loaded brush laying none of
  /// its own colour this dab, still laying what it carries at its 絵の具濃度;
  /// only a 絵の具量 set to 0 makes the 수채 섞기 that lays nothing on bare
  /// canvas.
  List<BrushDab> apply(List<BrushDab> dabs) {
    if (!isActive || dabs.isEmpty) {
      return dabs;
    }
    return [
      for (final dab in dabs)
        dab.copyWith(mix: _isDry ? _step(dab) : _loaded(dab)),
    ];
  }

  /// A brush with no 絵の具量 of its own ([apply]).
  bool get _isDry => !(shape.paintAmount > 0.0);

  /// What a whole stamp lifts of the ground: less the further 색 늘이기
  /// draws a picked-up colour out.
  double get _pick =>
      (1.0 - shape.colorStretch.clamp(0.0, 1.0)) * _pickPerStamp;

  /// A loaded brush's step at [dab]: the ground it lifts a whole stamp
  /// [_pick] of, refilled with the drawing colour by the dab's 絵の具量 and
  /// laid at its 絵の具濃度 ([apply]).
  BrushDabMix _loaded(BrushDab dab) {
    final amount = _ofDab(
      dab,
      BrushPressureTarget.paintAmount,
      shape.paintAmount,
    );
    return _step(
      dab,
      refill: _pickedUp(dab, amount * amount * _refillPerStamp),
      laid: amount * _drawingLaid,
      density: _ofDab(
        dab,
        BrushPressureTarget.paintDensity,
        shape.paintDensity,
      ),
    );
  }

  /// [dab]'s step of the stroke: a loaded brush's [refill], [laid] and
  /// [density] ([_loaded]); a dry brush's what it picks up of the ground
  /// a whole stamp lifting [_pick] of it.
  BrushDabMix _step(
    BrushDab dab, {
    double refill = 0.0,
    double laid = 0.0,
    double density = 0.0,
  }) {
    final pick = _pick;
    return BrushDabMix(
      step: _steps++,
      center: dab.center,
      radius: dab.size / 2.0,
      color: dab.color,
      refill: refill,
      laid: laid,
      density: density,
      take: _isDry ? _pickedUp(dab, pick) : 0.0,
      share: stampShareOf(dab),
      pick: pick,
      dry: _isDry,
    );
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

/// What a whole stamp lifts of the ground at 色延び 0 ([BrushGroundColorMixer]
/// — fitted to the user's Clip Studio strokes).
const double _pickPerStamp = 0.12;

/// How far a whole stamp refills the brush with its drawing colour at 絵の具量
/// 1 — by 絵の具量², fitted with [_pickPerStamp].
const double _refillPerStamp = 0.12;

/// The share of the drawing colour a dab lays over what the brush carries at
/// 絵の具量 1, fitted with [_pickPerStamp].
const double _drawingLaid = 0.3;

/// How far [dab] moves the reservoir — toward the drawing colour it is
/// refilled with, or a dry brush toward the ground it lifts — where a whole
/// stamp would move it by [pull]: its share of that stamp ([stampShareOf]).
/// The engine moves it toward the ground a loaded brush lifts by the same
/// law, from the step's share (`mix.wgsl`'s `mix_picked_up`) — that pull is
/// the ground's.
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
