import 'package:flutter/painting.dart' show Color;

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';

/// 색 라벨의 색.
///
/// 🚨★★★THE HUES ARE THE USER'S, MEASURED FROM THEIR OWN SCREENSHOT — not
/// chosen here. 유저 2026-08-27: 「색 내가 첨부한거 그대로 살리고 톤만
/// 바꾸라니까? **LO는 흰색이야. 원화는 초록색이었고. BG는 파랑색이었고 뭘본거야?**」
///
/// ⛔I had invented a palette while their reference sat in `board-shots/`
/// unopened. These values came out of those PNGs pixel by pixel (each swatch
/// is a 14×14 square, so the exact colours fall straight out of a frequency
/// count). Five entries had no source — 러프원화 · 콘티 · 총감독 · 동화검사 ·
/// 셀검사 — and were marked as proposals in the design artifact.
///
/// ⚠️A mark's colour is not just a chip: it is the PAPER of that layer's
/// frame blocks (`timeline_row_cells_painter.dart`), which the user confirmed
/// is the intended spec. A colour lands across whole rows, not on a small
/// swatch.
///
/// 🪦**네 톤이 있었고, 골랐고, 끝났다.** original · pastel · **cream** ·
/// pencil 을 전부 구현해 설정에서 고르게 했던 것은 유저 요청이었다(I-4:
/// 「ABCD 네개 다 구현해서 **프로그램 내에서 직접 보면서 확인**하고싶어」).
/// 실기에서 크림이 확정됐고(2026-08-28: 「답은 크림이고」), 고르는 장치는
/// 그 목적을 다했다 — 「색도 크림으로 정했으니까 나머지 유물 없애도되.
/// 코드에서 잔재하는거 싹 삭제」. 아래 값은 그 크림 열이다.
///
/// ⇒ 다시 여러 톤이 필요해지면 **한 행이 한 색이 아니라 한 줄이 되는** 옛
/// 모양으로 돌아가면 된다. 톤은 같은 색상의 변환이었으므로 표는 하나였고,
/// 색상 하나를 고치면 네 톤이 함께 움직였다.
const Map<LayerProcess, int> _processColors = {
  LayerProcess.paper: 0xFFFFA463,
  LayerProcess.conte: 0xFFD1BAF7,
  LayerProcess.art: 0xFF6BB3F7,
  LayerProcess.layout: 0xFFFFFDF7,
  LayerProcess.roughKey: 0xFFAEFCF2,
  LayerProcess.key: 0xFFB5FDB0,
  LayerProcess.inbetween: 0xFFFFF2C2,
  LayerProcess.finish: 0xFFF2BDB7,
};

/// 🚨THE REVISE'S COLOUR IS THE SAME WHATEVER THE STAGE. 유저 2026-08-27:
/// 「수정공정이면 어느 공정의 수정이던간에 저 고정색 사용됨. 즉 **LO연출이던
/// 원화연출이던 같은색**이란거지」 — the reason is the real thing: 「실제
/// 업계에서 해당 용지 위에 그림 그리면 아 작감수정이구나 라는걸 토대로 한거임」.
const Map<LayerRevise, int> _reviseColors = {
  LayerRevise.direction: 0xFFFFC1E8,
  LayerRevise.animationDirector: 0xFFFFC663,
  LayerRevise.chiefAnimationDirector: 0xFFEDFDCE,
  LayerRevise.director: 0xFFC0BEF7,
  LayerRevise.chiefDirector: 0xFFD7BEF7,
  LayerRevise.actionAnimationDirector: 0xFFA2EDBF,
  LayerRevise.inbetweenCheck: 0xFFAEE8F7,
  LayerRevise.cellCheck: 0xFFFFBDC8,
};

/// The paper an unlabelled layer's blocks wear. Passed in rather than named
/// here so the theme keeps owning it — this file knows labels, not chrome.
Color resolveLayerMarkColor(LayerMark mark, {required Color noneColor}) {
  final revise = mark.revise;
  if (revise != null) {
    return Color(_reviseColors[revise]!);
  }
  final process = mark.process;
  if (process == null) {
    return noneColor;
  }
  return Color(_processColors[process]!);
}
