/// How a dab's tip angle is chosen at placement time — the base of Clip
/// Studio's 向き, to which `angleDegrees` is added and the brush's random
/// turn (`angleJitter`) after that.
///
/// F-176-Q1 (유저 2026-10-18 「클튜처럼 — 「방향」 하나: 기준 + 랜덤」):
/// one 向き, three bases. Clip Studio's fourth, ペンの回転 (barrel rotation),
/// is absent because no input here measures it.
enum BrushTipRotationMode {
  /// No base: the tip keeps the fixed `angleDegrees` setting.
  fixed,

  /// The tip follows the stroke direction; `angleDegrees` becomes an offset
  /// on top of it (Photoshop "Direction" angle control, Clip Studio 線の方向).
  direction,

  /// The tip turns with the way the pen leans (Clip Studio ペンの方向); a
  /// device that reports no tilt, or a pen held upright, leaves it at
  /// `angleDegrees`.
  penTilt;

  String toJson() => name;

  static BrushTipRotationMode fromJson(Object? value) {
    return BrushTipRotationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => BrushTipRotationMode.fixed,
    );
  }
}
