import 'package:flutter/painting.dart' show Color;

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';

/// The colour a 색 라벨 wears, in four tones of the SAME hues.
///
/// 🚨★★★THE HUES ARE THE USER'S, MEASURED FROM THEIR OWN SCREENSHOT — not
/// chosen here. 유저 2026-08-27: 「색 내가 첨부한거 그대로 살리고 톤만
/// 바꾸라니까? **LO는 흰색이야. 원화는 초록색이었고. BG는 파랑색이었고 뭘본거야?**」
///
/// ⛔I had invented a palette while their reference sat in `board-shots/`
/// unopened. These values came out of those PNGs pixel by pixel (each swatch
/// is a 14×14 square, so the exact colours fall straight out of a frequency
/// count). Five entries had no source — 러프원화 · 콘티 · 총감독 · 동화검사 ·
/// 셀검사 — and are marked as proposals in the design artifact.
///
/// ⚠️A mark's colour is not just a chip: it is the PAPER of that layer's
/// frame blocks (`timeline_frame_cell.dart`), which the user confirmed is the
/// intended spec. So a tone lands across whole rows, not on a small swatch —
/// which is why all four exist and the user picks by looking at the program.
enum LayerMarkPalette {
  /// 원본 그대로 — the screenshot's values, untouched. ⚠️08-27 까지의 기본값.
  original('original', 'Original'),

  /// 흰색을 45% 섞은 파스텔.
  pastel('pastel', 'Pastel'),

  /// 따뜻한 아이보리를 42% 섞은 크림. 🔒**유저 확정 기본값**(2026-08-28).
  cream('cream', 'Cream'),

  /// 채도를 32% 죽이고 종이색을 26% 섞은 색연필.
  pencil('pencil', 'Coloured pencil');

  const LayerMarkPalette(this.jsonValue, this.displayName);

  final String jsonValue;

  /// The tone's name in ENGLISH — 다른 언어는 [AppStrings.layerMarkPaletteName]
  /// 이 [jsonValue] 로 든다. 색 라벨의 공정·수정과 **같은 계약**이다.
  final String displayName;

  /// 🚨★★★THE default, named ONCE. 유저 2026-08-28 실기 확정: **크림**
  /// (「답은 크림이고」) — 08-27 의 「기본값은 원본그대로로 두고」는 넷을 놓고
  /// 고르는 동안의 임시값이었다.
  ///
  /// ⛔[AppAccentSettings] 의 기본 인자와 [fromJson] 의 폴백은 **같은 질문에
  /// 답한다** — 「고른 적이 없으면 무엇인가」. 두 군데에 적으면 저장값이 깨졌을
  /// 때만 다른 톤이 나오는, 아무도 못 찾는 어긋남이 생긴다.
  static const LayerMarkPalette fallback = cream;

  static LayerMarkPalette fromJson(Object? json) {
    for (final palette in LayerMarkPalette.values) {
      if (json == palette.jsonValue) {
        return palette;
      }
    }
    return fallback;
  }
}

/// 🚨ONE TABLE, FOUR COLUMNS — ⛔not four tables.
///
/// The tones are the same hues transformed, so writing them as four separate
/// palettes would be four places to forget when a hue is corrected. Each row
/// is `[original, pastel, cream, pencil]` and the palette picks the column;
/// a hue fix edits one row and all four tones move together.
const Map<LayerProcess, List<int>> _processColors = {
  LayerProcess.paper: [0xFFFF6600, 0xFFFFAB73, 0xFFFFA463, 0xFFE2945F],
  LayerProcess.conte: [0xFFBF80FF, 0xFFD4C0FF, 0xFFD1BAF7, 0xFFC0AEE6],
  LayerProcess.art: [0xFF007FFF, 0xFF73B9FF, 0xFF6BB3F7, 0xFF5A99D8],
  LayerProcess.layout: [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFDF7, 0xFFFEFDFC],
  LayerProcess.roughKey: [0xFF80FFF4, 0xFFB3FFF8, 0xFFAEFCF2, 0xFFB5EFEA],
  LayerProcess.key: [0xFF80FF85, 0xFFB9FFBC, 0xFFB5FDB0, 0xFFB2F1B2],
  LayerProcess.inbetween: [0xFFFFECA3, 0xFFFFF5CC, 0xFFFFF2C2, 0xFFF9EEC8],
  LayerProcess.finish: [0xFFE99191, 0xFFF3C2C2, 0xFFF2BDB7, 0xFFDFB2B0],
};

/// 🚨THE REVISE'S COLOUR IS THE SAME WHATEVER THE STAGE. 유저 2026-08-27:
/// 「수정공정이면 어느 공정의 수정이던간에 저 고정색 사용됨. 즉 **LO연출이던
/// 원화연출이던 같은색**이란거지」 — the reason is the real thing: 「실제
/// 업계에서 해당 용지 위에 그림 그리면 아 작감수정이구나 라는걸 토대로 한거임」.
const Map<LayerRevise, List<int>> _reviseColors = {
  LayerRevise.direction: [0xFFFF97E5, 0xFFFFC6F1, 0xFFFFC1E8, 0xFFEFBADF],
  LayerRevise.animationDirector: [0xFFFFA000, 0xFFFFCB73, 0xFFFFC663, 0xFFEAB967],
  LayerRevise.chiefAnimationDirector: [
    0xFFE0FFB9,
    0xFFEEFFD8,
    0xFFEDFDCE,
    0xFFEAF9D4,
  ],
  LayerRevise.director: [0xFF9393FF, 0xFFC4C4FF, 0xFFC0BEF7, 0xFFB1B0E5],
  LayerRevise.chiefDirector: [0xFFC29BFF, 0xFFDAC4FF, 0xFFD7BEF7, 0xFFCBB6E8],
  LayerRevise.actionAnimationDirector: [
    0xFF5EE49F,
    0xFFA6F0CA,
    0xFFA2EDBF,
    0xFF9BDEBA,
  ],
  LayerRevise.inbetweenCheck: [0xFF80DFFF, 0xFFB3ECFF, 0xFFAEE8F7, 0xFFB5DFEE],
  LayerRevise.cellCheck: [0xFFFF99B3, 0xFFFFC2D1, 0xFFFFBDC8, 0xFFF2CBD3],
};

/// The paper an unlabelled layer's blocks wear. Passed in rather than named
/// here so the theme keeps owning it — this file knows labels, not chrome.
Color resolveLayerMarkColor(
  LayerMark mark,
  LayerMarkPalette palette, {
  required Color noneColor,
}) {
  final revise = mark.revise;
  if (revise != null) {
    return Color(_reviseColors[revise]![palette.index]);
  }
  final process = mark.process;
  if (process == null) {
    return noneColor;
  }
  return Color(_processColors[process]![palette.index]);
}
