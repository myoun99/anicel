import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';
import 'timeline_repeat.dart';

/// [cut] with every IMAGE layer's stored timeline normalized to the D22
/// form: ONE real 1-frame block at index 0 carrying a FIXED end-side HOLD
/// ([TimelineRunEdgeMark]) whose ghosts fill to the cut's DRAWN end — 「블록은
/// 1칸 + 성질 hold 고정」 (유저 2026-08-17). One picture simply exists
/// throughout, and the row SAYS so: a single cell, then the dim hold
/// dashes every other row uses for the same statement.
///
/// [drawnFrameCount] is the cut's conte 尺 plus its のりしろ (F-227: the
/// margin end line is the real end line), so the picture is there for every
/// frame the cut is drawn for — through an O.L, not just to the red line.
///
/// The storyboard row absorbs cut-length changes at read time (its
/// coverage is derived); the image row has no derived reader — the
/// timeline grid, the composite and every thumbnail paint its STORED
/// exposures — so the store itself must follow the cut. Running as a
/// repository-write normalization (the always-mirror precedent) covers
/// every duration path at once: trims, strip drags, undo/redo replay,
/// file load. It derives its own ghosts inline ([rederiveRunBehaviors] —
/// identity-preserving when nothing changed), so any write leaves the image
/// row fully shaped: real cell + hold ghosts, no matter which verb wrote.
///
/// Coverage is unchanged: `exposedFrameIdAt` resolves ghost cells to
/// their anchor, so playback, thumbnails and the composite still show
/// the picture on every frame. Old covering-form files reshape on their
/// first write. Identity-preserving on no-ops so unchanged cuts pass
/// through untouched.
///
/// 🚨A ROW WITH NO BLOCK STAYS EMPTY (F-98, 유저 2026-09-12: 「이미지
/// 레이어도 프레임이 없는 상태는 존재함. 생성하면 기본적으로 프레임 생성되는건
/// 그대로지만 삭제가능하도록. 없는 상태가 존재하도록 구조/근본적 변경. 그런
/// 부분은 일반 애니메이션레이어랑 법 맞추면서 통일/재사용」 · 2026-10-04
/// 「이미지레이어도 프레임 없는상태. 프레임 삭제 가능하도록 … 같이 작업」).
/// ↩️It used to re-cover an empty row from the first cel of its BANK: a
/// deleted block came back in the same write, so every verb that could empty
/// the row stood down (delete, cut, 링크 독립). The lane is what the row
/// shows; the bank is what its link group holds, and may well hold another
/// cut's picture while this cut shows none.
Cut cutWithCoveringImageRows(Cut cut, {required int drawnFrameCount}) {
  final drawn = drawnFrameCount < 1 ? 1 : drawnFrameCount;
  final layers = mappedOrSame(
    cut.layers,
    (layer) => _coveringImageRow(layer, drawn),
  );
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

/// [layer] in the D22 form when it is an image row holding a block — else
/// [layer] itself. Identity-preserving through [rederiveRunBehaviors],
/// which answers the same instance when the row already has its shape.
Layer _coveringImageRow(Layer layer, int drawnFrameCount) {
  if (!layer.kind.holdsSingleCel) {
    return layer;
  }
  final block = authoredBlockOf(layer);
  final celId = block?.frameId;
  if (block == null || celId == null) {
    // No block: nothing to hold. The derive drops any ghosts a removed block
    // left behind.
    return rederiveRunBehaviors(layer, drawnFrameCount: drawnFrameCount);
  }
  const holdMark = TimelineRunEdgeMark(mode: TimelineRunEdgeMode.hold);
  var realCount = 0;
  for (final entry in layer.timeline.values) {
    if (!entry.ghost) {
      realCount += 1;
    }
  }
  final zeroEntry = layer.timeline[0];
  final shaped =
      realCount == 1 &&
      zeroEntry != null &&
      !zeroEntry.ghost &&
      zeroEntry.isDrawing &&
      zeroEntry.frameId == celId &&
      zeroEntry.length == 1 &&
      zeroEntry.startEdge.isNone &&
      zeroEntry.endEdge == holdMark;

  var next = layer;
  if (!shaped) {
    // Rebuild THROUGH the block, so its entry-carried metadata (the block
    // memo) survives a reshape. Inbetween dots do NOT survive and cannot:
    // they are offsets INSIDE the block, and a 1-frame block has no inside
    // — a picture row has no inbetweens to lose. Ghosts are dropped here;
    // the derive below re-synthesizes them from the fixed spec.
    next = layer.copyWith(
      timeline: {
        0: block.copyWith(
          length: 1,
          startEdge: TimelineRunEdgeMark.none,
          endEdge: holdMark,
        ),
      },
    );
  }
  return rederiveRunBehaviors(next, drawnFrameCount: drawnFrameCount);
}
