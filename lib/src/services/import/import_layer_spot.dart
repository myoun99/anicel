import '../../models/layer_id.dart';
import 'media_import_planner.dart' show ImportDestination;

/// Where a placement lands, when a DROP decided it: a place in the ACTIVE
/// cut, or a NEW cut's place on the track.
///
/// "Where does this go" is two questions. Which cut — the active one or a
/// new one — is [ImportDestination], and the window asks it. Where in that
/// cut is this, and only a drop answers it: the place the file was let go
/// decides (유저 2026-09-11, 미디어 배치 라운드: 「떨어뜨린 자리가 곧 답」),
/// and the window shows that answer locked rather than asking again.
///
/// No spot at all is the import menu's answer: a new layer on top.
sealed class ImportLayerSpot {
  const ImportLayerSpot();

  /// Which cut the drop answered as well as where in it — or null when the
  /// drop left that question to the window, which then asks it.
  ///
  /// The ACTIVE cut for a place only the active cut has — a row's frames, an
  /// SE row's cell, a gap between its rows — so the window shows the
  /// destination locked and the settings hold that one answer.
  ///
  /// ⚠️Null for the canvas ([AboveActiveLayerSpot]). Its first words were a
  /// DEFAULT, not an answer (「놓으면 활성 레이어 바로 위를 기본값으로 채운
  /// 배치 창이 열린다」), and 유저 2026-09-12: 「풀에서 캔버스에 배치시 새
  /// 레이어 고정이아니라 새 레이어/새 컷 고를수있게. 왜냐하면
  /// 스토리보드패널에서 캔버스에 떨굴때도 새 레이어 고정으로 되니까. 액티브
  /// 컷이 없는 상태에서 캔버스 떨구면 새 컷 고정이고, 있으면 새 레이어/새 컷
  /// 지정가능」.
  ImportDestination? get answeredDestination;
}

/// A new layer directly above the active one — a drop on the canvas.
///
/// The slot is Add Layer's own ([LayerController.insertionIndexAboveActiveLayer]),
/// not a second reading of "above".
final class AboveActiveLayerSpot extends ImportLayerSpot {
  const AboveActiveLayerSpot();

  @override
  ImportDestination? get answeredDestination => null;

  @override
  bool operator ==(Object other) => other is AboveActiveLayerSpot;

  @override
  int get hashCode => (AboveActiveLayerSpot).hashCode;
}

/// New frames on [layerId] from [frameIndex] on — a drop on a picture
/// row's frame area. Always baked: a row's cells are its own pixels, so
/// they cannot stay a reference to a file (08-14 「셀에 떨어뜨리면 항상
/// 굽기」, the same law).
final class RowFramesSpot extends ImportLayerSpot {
  const RowFramesSpot({required this.layerId, required this.frameIndex});

  final LayerId layerId;

  /// The cell the file was dropped on, zero-based.
  final int frameIndex;

  @override
  ImportDestination? get answeredDestination =>
      ImportDestination.activeCutLayer;

  @override
  bool operator ==(Object other) =>
      other is RowFramesSpot &&
      other.layerId == layerId &&
      other.frameIndex == frameIndex;

  @override
  int get hashCode => Object.hash(layerId, frameIndex);
}

/// A SOUND let go on an SE row's empty cell: a new block on [layerId] from
/// [frameIndex] on, as long as the sound or up to the row's next block
/// (유저 2026-09-11, 미디어 배치 라운드: 「SE 행의 빈 칸 → 새 블록」).
final class SeCellSpot extends ImportLayerSpot {
  const SeCellSpot({required this.layerId, required this.frameIndex});

  final LayerId layerId;

  /// The cell the sound was let go on, in the CUT's frames — as the row
  /// showed it. The track's frame is [TrackSeWindow]'s to work out.
  final int frameIndex;

  @override
  ImportDestination? get answeredDestination =>
      ImportDestination.activeCutLayer;

  @override
  bool operator ==(Object other) =>
      other is SeCellSpot &&
      other.layerId == layerId &&
      other.frameIndex == frameIndex;

  @override
  int get hashCode => Object.hash(SeCellSpot, layerId, frameIndex);
}

/// A new layer at a gap between two rows of the layer area — where the
/// rail's own caret showed the line (유저 2026-09-11, 미디어 배치 라운드:
/// 「레이어 영역(가로선) → 새 레이어」). [insertionIndex] is the model index
/// that line named; `newRowPlacement` still says which folder the row
/// joins, as it does for every new row.
final class LayerSlotSpot extends ImportLayerSpot {
  const LayerSlotSpot(this.insertionIndex);

  final int insertionIndex;

  @override
  ImportDestination? get answeredDestination =>
      ImportDestination.activeCutLayer;

  @override
  bool operator ==(Object other) =>
      other is LayerSlotSpot && other.insertionIndex == insertionIndex;

  @override
  int get hashCode => Object.hash(LayerSlotSpot, insertionIndex);
}

/// A NEW cut on the active track, where Create Cut would put one at the
/// frame the drop stood on — a drop on the storyboard's frame area (유저
/// 2026-09-12: 「타임라인이랑 같은 법으로 프레임영역에 떨구면 프레임 블록
/// 만들듯이 컷 만들어지도록」). The place is Create Cut's own arithmetic
/// asked at that frame (`CutPlacement.cutCreationPlanAt`), not a second rule
/// for where a cut goes.
final class NewCutSpot extends ImportLayerSpot {
  const NewCutSpot({required this.index, required this.leadingGapFrames});

  /// The slot the new cut takes in the track's cut sequence.
  final int index;

  /// The walk-in distance into the gap the drop stood in — 0 on a cut.
  final int leadingGapFrames;

  @override
  ImportDestination? get answeredDestination => ImportDestination.newCut;

  @override
  bool operator ==(Object other) =>
      other is NewCutSpot &&
      other.index == index &&
      other.leadingGapFrames == leadingGapFrames;

  @override
  int get hashCode => Object.hash(NewCutSpot, index, leadingGapFrames);
}
