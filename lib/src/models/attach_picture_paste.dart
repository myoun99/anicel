import 'frame_id.dart';
import 'layer.dart';
import 'timeline_coverage.dart';
import 'timeline_repeat.dart' show ghostFreeTimeline;

/// Which of a row's cels takes which of [drawings], cel to drawing: the block
/// [shown] shows at [from] takes the first, the block after it the second,
/// until the drawings or the blocks — those starting before [until], with a
/// selection — run out. Of two blocks showing one cel, the later one's
/// drawing is what the cel ends on.
///
/// 🗣️F-545 (유저 2026-11-02): 「어태치 싱크 레이어의 프레임블록 복사한걸 다른
/// 어태치 싱크행에 붙여넣을수있게. 대신 블록을 붙여넣는다기보단 그 경우 그림을
/// 교체하는게 되도록. 물론 싱크행을 대상으로 한 링크붙여넣기는 불가」.
///
/// The row's blocks are its base's, so no block lands: every cel, name,
/// exposure and link stays, and only what is hung in the cels changes — the
/// law of the picture trade a rows' hop makes
/// (`picturesTradedInAttachGroup`, F-330 · I-98), and of the picture row,
/// which puts the clip's first in its one block
/// (image-row-cut-paste-Q1: 「그림이 있어도 갈아끼운다」). A block dragged
/// there picks by this too (`picturesTradedInBlocks`, F-546).
///
/// [shown] is the row as a cut shows it (`attachedRowAsShown`). A cursor on a
/// hold's ghost stands on the drawing it shows, as a copy there does (F-140);
/// no ghost further on is a block.
Map<FrameId, FrameId> picturesHungInBlocks(
  Layer shown, {
  required List<FrameId> drawings,
  required int from,
  int? until,
}) {
  final cels = [
    ?coveringDrawingBlockAt(shown.timeline, from)?.entry.frameId,
    for (final MapEntry(key: start, value: block)
        in ghostFreeTimeline(shown).entries)
      if (start > from && (until == null || start < until)) ?block.frameId,
  ];
  return {
    for (final (index, cel) in cels.take(drawings.length).indexed)
      cel: drawings[index],
  };
}
