/// The groups a brush's settings are filed in — Clip Studio's categories
/// (インク · ブラシ先端 · 色の混ぜ方 · 散布効果 · テクスチャ · 補正), the rail
/// down the brush detail window's left side (I-141-Q4, 유저 2026-10-29:
/// 「클튜처럼 왼쪽에 두자. 브러시그룹/브러시목록이랑 비슷한느낌으로」).
///
/// ↩️They were the panel's group heads, and a brush remembered which of them
/// were folded (F-418-Q10). The panel shows a brush's chosen rows with no
/// heads now (`BrushSettingsRow`), so there is nothing left to fold.
enum BrushSettingsGroup { ink, tip, mixing, scattering, texture, correction }
