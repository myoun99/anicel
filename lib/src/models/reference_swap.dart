import 'layer.dart';
import 'layer_kind.dart';
import 'media_asset.dart';
import 'movie_cel.dart';

/// How a REFERENCE row takes another file in place of the one it shows
/// (I-47, 유저 2026-09-25: 「이미지 레이어의 프레임영역에 떨구면 참조변경 …
/// 기존의 트랜스폼값같은거 안건들이고 진짜 참조대상만 변경하는느낌」).
enum ReferenceSwap {
  /// A movie row: its one cel holds no pixels — the movie is decoded as it
  /// is shown — so the reference is all that changes.
  movie,

  /// A still on an image row: its cel holds the picture the file was baked
  /// into, so the picture is baked again from the new file, into the same
  /// cel.
  still,
}

/// How [layer] takes the file at [path] in place of the one it shows — or
/// null when it cannot: a row that points at no file, the file it already
/// shows, or a file that could not stand where its picture stands (a movie
/// row takes a movie, a still row a still).
///
/// ⚠️A reference row of any OTHER shape answers null — a sequence, an
/// animated GIF or a PDF's pages as cels. Each of its cels is one picture
/// of the file in order, and which picture of a new file a cel would take
/// when the two do not have as many is a question nobody has answered; the
/// user asked for an image row (「이미지 레이어의 프레임영역」) and a movie
/// row (Q1's 「참조로 둔 이미지(또는 동영상) 레이어」).
ReferenceSwap? referenceSwapFor(Layer layer, String path) {
  final reference = layer.mediaReference;
  if (reference == null || normalizedMediaPath(path) == reference.assetPath) {
    return null;
  }
  final redraw = referenceRedrawFor(layer);
  // A movie row takes a movie, a still row a still.
  final takes = switch (redraw) {
    ReferenceSwap.movie => MediaAssetKind.video,
    ReferenceSwap.still => MediaAssetKind.image,
    null => null,
  };
  return takes != null && mediaAssetKindForPath(path) == takes ? redraw : null;
}

/// How [layer]'s pictures are made from its file AGAIN — a still's baked
/// anew, a movie's decoded anew as it is shown — or null when the row
/// points at no file or is of another shape ([referenceSwapFor] says why
/// such a row is not drawn again). Swapping the file and moving its
/// reference fx (I-68) both draw it again.
ReferenceSwap? referenceRedrawFor(Layer layer) {
  final reference = layer.mediaReference;
  if (reference == null) {
    return null;
  }
  if (isMovieReference(layer)) {
    return ReferenceSwap.movie;
  }
  final stillRow =
      layer.kind == LayerKind.image &&
      mediaAssetKindForPath(reference.assetPath) == MediaAssetKind.image;
  return stillRow ? ReferenceSwap.still : null;
}
