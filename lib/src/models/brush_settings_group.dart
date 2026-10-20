/// The groups a brush's settings are shown in — Clip Studio's categories,
/// as the tool settings panel lays them out (インク · ブラシ先端 · 色の混ぜ方 ·
/// 散布効果 · テクスチャ · 補正).
///
/// A brush remembers which of them are folded (F-418-Q10, 유저 2026-10-20:
/// 「모든 그룹 머리가 접힌다」 — the brush's own, with what the hand changed
/// on it, so a brush pack carries it).
enum BrushSettingsGroup { ink, tip, mixing, scattering, texture, correction }
