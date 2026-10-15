/// The 색 편집 list's clipboard rows (I-55): 픽셀 잘라내기 (I-90), 픽셀 복사
/// and the two pastes — in the list's order.
///
/// 🗣️유저 2026-10-01: 「픽셀복사/픽셀 아래 붙여넣기/픽셀 위 붙여넣기」 — the
/// timeline button of 08-12 (⑤), revived inside 색 편집: 「타임라인버튼으로
/// 제안한걸 다시 살리려는거야」.
///
/// ⛔Not rows of `CelPixelVerb`: those four rewrite a channel of the cels
/// they name, where these read one cel onto a board and lay that board back
/// down — a different kind of verb in the same list.
enum PixelClipboardVerb {
  /// What [copy] reads, onto the board — and then OFF the cel, as one undo.
  ///
  /// 🗣️I-90 (유저 2026-10-10): 「픽셀 잘라내기 버튼 신설. 복사버튼 위. 내용은
  /// 동일하게 원본대상 삭제하고 복사한단느낌. 진짜 단어 그대로 잘라내기라는
  /// 느낌」.
  cut,

  /// The standing cel onto the pixel board — through the selection when
  /// there is one, else its whole picture.
  copy,

  /// The board, OVER what each named cel holds (`BrushBlendMode.color`).
  pasteAbove,

  /// The board, BEHIND what each named cel holds (`BrushBlendMode.behind`).
  ///
  /// 위/아래 is composite order and never a layer row (유저 2026-08-10:
  /// 「위/아래는 합성순서야」).
  pasteBelow,
}
