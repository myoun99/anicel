/// What DRIVES a brush setting — the pen, the hand's speed, or chance.
///
/// A setting (size, opacity, flow, hardness) can answer to more than one of
/// these at once, each through its own response curve. Clip Studio files them
/// exactly that way: one curve block per enabled source inside the effector
/// blob, plus a minimum per source.
///
/// ## How several enabled sources combine: THEY MULTIPLY
///
/// ⛔**This is OUR engine's rule, chosen on precedent. It is NOT "what Clip
/// Studio does"** — 2026-09-09 survey: no Celsys documentation and no credible
/// secondary source states CSP's combination rule, so anyone writing that here
/// later would be inventing it. What the survey DID establish:
///
/// * **Krita** (`KisCurveOption::computeValueComponents`, GPL source): several
///   sources per setting, the rule is a user-selectable mode, and the DEFAULT
///   is multiply — its accumulator starts at `1.0`, the multiplicative
///   identity.
/// * **MyPaint** (libmypaint source): each input's curve output is ADDED to
///   the setting's base value — but radius is stored logarithmically, so
///   adding in log space IS multiplying in linear space. Same answer for size,
///   reached from the other side.
/// * **Photoshop**: one Control dropdown per setting plus a separate jitter,
///   so it never faces the question. An `.abr` can only ever carry one source.
///
/// Multiplying is also what makes enabling a source NON-DESTRUCTIVE: an
/// inactive source contributes exactly 1.0, so turning one on or off cannot
/// move the others, and the order they combine in cannot matter.
///
/// ⛔**No user-facing "combination mode" selector** (유저 확정 2026-09-09).
/// Krita offers one because Krita exposes everything; the panel here is built
/// after Clip Studio, which does not, and a dropdown Clip Studio users have
/// never seen is a control that has to be explained — and explanatory text is
/// banned.
///
/// ## Randomness is NOT one of these
///
/// 🚨Chance already has a home: `BrushShape.sizeJitter` and its siblings,
/// applied in `brush_stroke_dynamics.dart` as `value *= 1 - jitter * rand`.
/// Promoting it to a fourth source here would be a second machine doing one
/// job. **Krita agrees structurally** — its fuzzy sensors return
/// `isAdditive() == true`, so they skip the combination mode entirely and get
/// folded in by a hard-coded multiply at the end, which is the same shape as
/// our jitter.
enum BrushInputSource {
  /// 筆圧. The only source every tablet reports.
  pressure,

  /// 傾き — how far the pen leans, from `BrushDab.tiltAltitude` (1.0 is
  /// upright). The one source Clip Studio also gives a MAXIMUM, which is why
  /// [BrushPressureCurve] has one.
  tilt,

  /// 速度 — how fast the stroke is moving, as canvas px/s over the user's
  /// reference speed (`AppInputSettings.speedReferencePixelsPerSecond`).
  ///
  /// 🚨THE ONLY SOURCE WITH A CEILING WE CHOSE. 筆圧 and 傾き arrive already
  /// bounded by the hardware, so their 0..1 is the device's own; speed has no
  /// natural maximum, and no file format supplies one — Clip Studio's 速度
  /// effector stores a curve and a minimum and stops there. So the ceiling is
  /// a SETTING, deliberately visible, rather than a constant hidden in here.
  ///
  /// ⚠️Measured per SEGMENT, not per dab: every dab interpolated between two
  /// pointer readings carries the speed of the move that produced them.
  speed;

  /// The bit this source sets in an effector's input-flag word (int[2]).
  ///
  /// ⚠️0x40 is 傾き, NOT stroke direction. That was guessed wrong once, on the
  /// evidence that it only appeared on the rotation effector, and `물붓.sut`
  /// settled it (2026-09-08): all four inputs ticked, size effector reads
  /// 0xF0. Stroke direction stays unmapped.
  int get effectorFlagBit => switch (this) {
    pressure => 0x10,
    speed => 0x20,
    tilt => 0x40,
  };

  /// Where this source's 최소치 sits in the effector blob: `int[3 + index]`.
  ///
  /// 🚨**PANEL ORDER, WHICH IS NOT FLAG-BIT ORDER.** The four minimum slots
  /// run 筆圧 · 傾き · 速度 · ランダム the way the panel lists them, while the
  /// CURVE blocks in the tail run in ascending flag-bit order (筆圧 0x10,
  /// 速度 0x20, 傾き 0x40, ランダム 0x80). Reading one order for the other is
  /// the mistake this field exists to stop.
  ///
  /// 🔬Measured 2026-09-08 against two real brushes and their panel
  /// screenshots. ⚠️That is two files, not a spec — a brush that disagrees
  /// is evidence, not a bug in the brush.
  int get effectorMinimumIndex => switch (this) {
    pressure => 0,
    tilt => 1,
    speed => 2,
  };

  /// Chance's slot in that same run of four. Not a [BrushInputSource] because
  /// randomness is not one here (see the class doc) — but the blob still
  /// stores its minimum beside the others, and the jitter amplitude is read
  /// from it.
  static const int randomEffectorMinimumIndex = 3;
}
