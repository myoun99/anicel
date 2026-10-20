/// How a dab's tip angle is chosen at placement time — the base of Clip
/// Studio's 向き, to which `angleDegrees` is added and the brush's random
/// turn (`angleJitter`) after that.
///
/// F-176-Q1 (유저 2026-10-18 「클튜처럼 — 「방향」 하나: 기준 + 랜덤」):
/// one 向き, and Clip Studio's four bases. ↩️Its fourth, ペン軸の回転, was
/// left out while no input here measured a pen's turn about its barrel;
/// F-176-Q9 (유저 2026-10-21 「클튜처럼 — 방향의 기준 「펜 축 회전」 하나」)
/// gave it the Windows pen's own report.
enum BrushTipRotationMode {
  /// No base: the tip keeps the fixed `angleDegrees` setting.
  fixed,

  /// The tip follows the stroke direction; `angleDegrees` becomes an offset
  /// on top of it (Photoshop "Direction" angle control, Clip Studio 線の方向).
  direction,

  /// The tip turns with the way the pen leans (Clip Studio ペンの方向); a
  /// device that reports no tilt, or a pen held upright, leaves it at
  /// `angleDegrees`.
  penTilt,

  /// The tip turns as the pen turns about its own barrel (Clip Studio
  /// ペン軸の回転 — a Wacom Art Pen rolled in the fingers); a device that
  /// reports no turn leaves it at `angleDegrees`, as 없음 does.
  penTwist;

  String toJson() => name;

  static BrushTipRotationMode fromJson(Object? value) {
    return BrushTipRotationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => BrushTipRotationMode.fixed,
    );
  }
}
