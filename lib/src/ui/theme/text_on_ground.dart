import 'dart:ui';

/// THE text-on-ground law (2026-08-17, the difference blend's successor —
/// device verdict: white ink in [BlendMode.difference] read as navy over the
/// PURPLE blocks). Surfaces we paint ourselves have KNOWN colors, so writing
/// on them simply picks solid BLACK or WHITE by the luminance of the ground
/// it sits on: crisp glyphs, no halo, no blend.
///
/// 🚨★★★ONE RULE ON EVERY SURFACE, AND NOBODY COMPUTES CONTRAST AGAIN
/// (유저 2026-09-08: 「앞으로 이런식으로 뒤에 뭐 있을때 텍스트쓸때는 해당
/// 로직을 공용으로 사용하도록 해줘」). It lived in `ui/timeline/` while the
/// timeline was its only reader and the header already claimed it was "one
/// rule on every surface"; the settings slider filling its track with the
/// accent made that claim true, so the law moved here rather than being
/// copied. `timeline_cell_style.dart` re-exports it, so the timeline's
/// thirty-one call sites keep their import.
///
/// ↩️The SLIDER left the law for a day and came back: 09-10 fixed it white
/// (「흰색 고정으로 하고」), H38 fixed it black, and black vanished over the
/// empty track — 유저 2026-09-11: 「그냥 저번에 한대로 뒤 색에 따라 하양/검정
/// 바꾸는거 … 그거대로 하자」. It asks the law through `GroundInkWriting` now
/// — the writing whose ink changes part way through a word. A brush row's
/// name asked the same way (「슬라이더 공용 텍스트ui 그대로 재사용」) until F-82
/// (유저 2026-09-11 19:28) put it back on a plate in a fixed colour.
const Color textOnLightGroundColor = Color(0xFF000000);
const Color textOnDarkGroundColor = Color(0xFFFFFFFF);

/// The crossover luminance where black's WCAG contrast overtakes white's:
/// black wins iff (L+0.05)² > 0.05×1.05, i.e. L > √0.0525−0.05 ≈ 0.1791.
/// Sitting exactly there makes every pick the higher-contrast one by
/// construction — every layer-mark paper lands BLACK (purple, the reported
/// regression, is L≈0.22 where white manages only 3.9:1 against black's
/// 5.4:1), the dark lanes land WHITE (15:1+), and the 43%-alpha empty-cel
/// blends land WHITE for every colored mark (purple's is L≈0.07, white
/// 9.0:1) — only the plain paper's blend sits a hair ABOVE the crossover
/// (L≈0.181), where the two inks are equal anyway (4.6:1 vs 4.5:1).
const double textGroundLuminanceCrossover = 0.179;

/// Whether [ground] takes the DARK ink under the law above.
bool groundIsLight(Color ground) =>
    ground.computeLuminance() > textGroundLuminanceCrossover;

/// The writing's ink over [ground].
///
/// ⚠️[ground] must be the COMPOSITED color the writing actually sits on: a
/// translucent paper is blended over its backdrop first, because
/// `computeLuminance` ignores alpha.
Color textOnColor(Color ground) =>
    groundIsLight(ground) ? textOnLightGroundColor : textOnDarkGroundColor;
