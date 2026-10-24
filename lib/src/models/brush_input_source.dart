/// What DRIVES a brush setting — the pen, the hand's speed, or chance.
///
/// A setting (size, opacity, flow, hardness) can answer to more than one of
/// these at once, each through its own response curve. Clip Studio files them
/// that way inside the effector blob: a tick and a minimum per source, and a
/// graph for 筆圧 and for 傾き.
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
/// ## Chance IS one of these — the fourth row
///
/// Clip Studio's 影響元設定 lists ランダム beside 筆圧 · 傾き · 速度: a tick
/// and a 最小値, no graph — the value is thrown between that floor and 100%
/// on every dab. F-176-Q2 (유저 2026-10-18 「클튜식 — 팝업에 랜덤 줄,
/// 「무작위」 묶음 없앰」) put it here, and the five jitter sliders went: a
/// jitter of j IS a random row with 最小値 1 − j (`value *= 1 - j * rand` is
/// the same throw), so they were the second machine.
///
/// ↩️**This section used to say the opposite** (09-09 확정 ②, after
/// `brush-dynamics-sources-Q1`): 「랜덤은 지금 자리 그대로 — 지터 진폭으로
/// 곱해 넣는다. 곡선 소스로 승격시키면 같은 일을 하는 기계가 두 벌」. It was
/// right that one job wants one machine and wrong about which one should
/// stay: the popup a Clip Studio user knows has the random row, and five
/// sliders in a group of their own were the copy.
///
/// ⚠️The throw needs dice, which a dab does not carry — so [random] is the
/// one source [brushInputValue] cannot answer from the dab alone. Whoever
/// owns a stroke's dice hands a throw in (`applyBrushInputDynamics`), and a
/// caller that has none — a still thumbnail — skips the row, the way a mouse
/// skips 傾き.
///
/// ⚠️TWO ROOMS still, and on purpose: size, opacity, flow, hardness and
/// roundness throw PER DAB, while SPACING throws per SEGMENT in
/// `brush_edit_stroke.dart` (`spacingAt`) — spacing is consumed by
/// the interpolator, which is pure and shared, so threading dice into it
/// would cost more than the difference is worth. **Krita agrees
/// structurally** — its fuzzy sensors are folded in by a multiply at the end.
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
  speed,

  /// ランダム — a fresh throw in [0, 1) for every dab (every segment, for
  /// spacing). It has no graph in Clip Studio's panel, only a 最小値, so its
  /// curve is always the straight line and the floor is what a brush sets.
  random;

  /// The bit this source sets in an effector's input-flag word (int[2]).
  ///
  /// 🚨0x20 IS 傾き AND 0x40 IS 速度 (📏F-456, 2026-10-23). ↩️They stood the
  /// other way round from 2026-09-08, read off `물붓.sut` — which ticks all
  /// four (0xF0) and so could not tell those two apart (and 0x40 had been
  /// guessed as stroke direction before that). What does: Clip
  /// Studio's own 影響元設定 window (the user's screenshot) draws exactly two
  /// graphs, 筆圧設定 and 傾き設定, and the effector carries two graph
  /// blocks; the user's five pencils tick 筆圧 + 0x20 and shape the SECOND
  /// block, beside a tilt 最小値 and 最大値 of their own. Read as 速度, four
  /// of them laid nothing at any speed.
  /// ⚠️Stroke direction stays unmapped.
  int get effectorFlagBit => switch (this) {
    pressure => 0x10,
    tilt => 0x20,
    speed => 0x40,
    random => 0x80,
  };

  /// Where this source's 최소치 sits in the effector blob: `int[3 + index]`,
  /// in panel order — 筆圧 · 傾き · 速度 · ランダム.
  ///
  /// ↩️This warned that panel order was NOT flag-bit order, which held only
  /// while 0x20 was read as 速度; with the bits read right (F-456) the two
  /// agree. The GRAPH blocks follow neither — two of them, in fixed places
  /// (`_graphBlockOf` in the .sut decoder).
  ///
  /// 🔬Measured 2026-09-08 against two real brushes and their panel
  /// screenshots. ⚠️That is two files, not a spec — a brush that disagrees
  /// is evidence, not a bug in the brush.
  int get effectorMinimumIndex => switch (this) {
    pressure => 0,
    tilt => 1,
    speed => 2,
    random => 3,
  };
}
