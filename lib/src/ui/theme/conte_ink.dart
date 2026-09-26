import 'package:flutter/painting.dart' show Color;

import '../../models/conte/conte_page_marks.dart' show conteInkArgb;

/// The conte sheet's printed ink ([conteInkArgb]) as a colour — the black of
/// the heavy silhouette round every picture window of the conte preview, and
/// of its lines and type.
///
/// 🗣️유저 2026-09-26: 「바탕색을 콘티프리뷰패널의 픽쳐의 실루엣이랑 똑같이
/// 검정색으로 한다던가?」 — the storyboard's cut block wears it as its plate
/// ([storyboardCutBlockBackgroundColor]), so the V row's pictures sit on the
/// same black the conte sheet frames its pictures in. ONE number: this reads
/// the sheet's own rather than agreeing with it by value.
const Color conteSheetInk = Color(conteInkArgb);
