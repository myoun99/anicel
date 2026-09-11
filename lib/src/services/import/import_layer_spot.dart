import '../../models/layer_id.dart';

/// Where in the ACTIVE cut a placement lands, when a DROP decided it.
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
}

/// A new layer directly above the active one — a drop on the canvas.
///
/// The slot is Add Layer's own ([LayerController.insertionIndexAboveActiveLayer]),
/// not a second reading of "above".
final class AboveActiveLayerSpot extends ImportLayerSpot {
  const AboveActiveLayerSpot();

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
  bool operator ==(Object other) =>
      other is RowFramesSpot &&
      other.layerId == layerId &&
      other.frameIndex == frameIndex;

  @override
  int get hashCode => Object.hash(layerId, frameIndex);
}
