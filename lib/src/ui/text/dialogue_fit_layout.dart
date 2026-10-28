import 'dart:math' as math;

import '../../models/se_dialogue_spacing.dart';

/// Where ONE glyph of an SE block's dialogue stands along the block: a
/// block word ([timelineBlockWordLayout]) with the glyph for its word —
/// [cellStart] and [cellExtent] the frame it stands on, [roomExtent] how far
/// from [cellStart] it may run before it narrows.
typedef DialogueGlyphSlot = ({
  double cellStart,
  double cellExtent,
  double roomExtent,
});

/// Pure layout math for an SE block's dialogue. Shared by the timeline row
/// overlay, the X-sheet, the conte panel's SE track and the timesheet
/// painter, so screen and print lay a glyph on the same frame — and a part
/// of the block seen through a window shows what the whole lays there
/// ([dialogueGlyphsShownIn]).
///
/// 🗣️F-496 ③ (유저 2026-10-28): 「지금까지는 중앙정렬 기준으로 텍스트
/// 배치했는데, 왼쪽정렬로 둬서 1코마부터 첫번째 글자가 시작되도록. 대사
/// 오프셋은 이 시작되는 위치를 변경함 … 글자별 코마는 … 3코마로 설정하면
/// 글자 하나당 3코마의 공간을 차지하는느낌. 그 공간 안에서만 존재하면
/// 되니까 줌 줄일때 너무 한 칸에 넣으려 안해도됨. 프레임블록의 글자 그대로
/// 법 통일해서 적용」 — glyph `i` stands on the frame [spacing]'s offset plus
/// `i` times its koma, as a block's name stands on its first frame, and has
/// those koma to grow into. ↩️The glyphs spread evenly over the whole
/// block, each centred in an equal share of it — the paper sheet's
/// justified SE column.
///
/// [frames] is how many frames the block runs over [mainExtent]. Glyphs
/// too many for the frames after the offset share those evenly, each its
/// cell no longer than its share, as every glyph shared the block before;
/// an offset past the block stands on its last frame (「알아서 맡김」,
/// F-496-Q2). Zero glyphs, or a block of no frames, have no slots.
List<DialogueGlyphSlot> dialogueGlyphSlots({
  required int glyphCount,
  required int frames,
  required double mainExtent,
  required SeDialogueSpacing spacing,
}) {
  if (glyphCount <= 0 || frames <= 0) {
    return const [];
  }
  final frame = mainExtent / frames;
  final start = math.min(spacing.offset, frames - 1);
  final share = math.min(
    spacing.komaPerGlyph.toDouble(),
    (frames - start) / glyphCount,
  );
  final cell = math.min(1.0, share) * frame;
  return [
    for (var i = 0; i < glyphCount; i += 1)
      (
        cellStart: (start + i * share) * frame,
        cellExtent: cell,
        roomExtent: share * frame,
      ),
  ];
}

/// The glyphs of [slots] a WINDOW `[from, to)` along their block shows, as
/// the indices `[first, end)` of those whose cell's centre it holds — each
/// still where the WHOLE block lays it.
///
/// 🗣️F-358 (유저 2026-10-14): 「여러 컷에 걸친 se블록이 있을때, 글로벌에선
/// e라는 글자가 보이는 구간인데 로컬에선 T라는게 보인다던가 … 위치는
/// 같도록. 글로벌기준으로」. A cut, or a page half, is a window on the
/// block's one layout. ↩️Each laid its share out again over its own
/// stretch: the cut a sound spilled into spread the whole line over the
/// frames it had left.
///
/// A glyph shows whole, in the one window holding the frame it stands on —
/// no window prints half a glyph, and none prints one twice.
({int first, int end}) dialogueGlyphsShownIn(
  List<DialogueGlyphSlot> slots, {
  double from = double.negativeInfinity,
  double to = double.infinity,
}) {
  int firstAtOrPast(double at) {
    var index = 0;
    while (index < slots.length &&
        slots[index].cellStart + slots[index].cellExtent / 2 < at) {
      index += 1;
    }
    return index;
  }

  return (first: firstAtOrPast(from), end: firstAtOrPast(to));
}

// 🪦`dialogueGlyphCondensation` — F-93's narrowing of a glyph into its cell —
// became every block word's rule and moved to `word_condensation.dart`
// (`wordCondensation`): the dialogue's glyphs narrow into their room there,
// as a name narrows into its block.
