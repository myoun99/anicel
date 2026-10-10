import 'layer.dart';
import 'layer_kind.dart';
import 'media_asset.dart';
import 'movie_cel.dart';

/// How a REFERENCE row's pictures are made from its file again — when it
/// takes another file in place of the one it shows (I-47, 유저 2026-09-25:
/// 「이미지 레이어의 프레임영역에 떨구면 참조변경 … 기존의 트랜스폼값같은거
/// 안건들이고 진짜 참조대상만 변경하는느낌」), and when its reference fx moves
/// (I-68).
enum ReferenceSwap {
  /// A movie row: its one cel holds no pixels — the movie is decoded as it
  /// is shown — so the reference is all that changes.
  movie,

  /// A row whose cels hold pictures of its file — a still's one, a GIF's
  /// frames, a PDF's pages — each saying which ([Frame.filePicture]): each
  /// is made anew from that picture of the file the row then shows, into
  /// the same cel.
  ///
  /// ↩️It was `still`: until I-68 「가」 (유저 2026-10-10) a still's one cel
  /// was the only one that could be made again — a GIF's or a PDF's cels
  /// said nowhere which picture of the file each was.
  pictures,
}

/// What laying a reference row's pictures from a file again came to — the
/// answer to a swap, and to a move of the reference fx (I-68).
///
/// ↩️It was a `bool`, and `false` said every way it did not land: the drop
/// told a file that read, and only lacked the picture a cel shows, 「could
/// not read the file」 (I-68 「가」 ⓐ — 유저 2026-10-10 「추천대로가자」:
/// 「bg.png에는 2번째 그림이 없습니다」).
sealed class ReferenceRedraw {
  const ReferenceRedraw();
}

/// Laid: the row shows the file where its reference fx stands it.
final class ReferenceLaid extends ReferenceRedraw {
  const ReferenceLaid();
}

/// Nothing laid, and nothing to say of it: the row is not one laid again,
/// it already stands as asked, or it changed while its file was read.
final class ReferenceLeftAlone extends ReferenceRedraw {
  const ReferenceLeftAlone();
}

/// The file did not read — or the movie did not open, or a page did not
/// render.
final class ReferenceUnreadable extends ReferenceRedraw {
  const ReferenceUnreadable();
}

/// The file read, and holds no [picture] — the picture of it a cel shows
/// ([Frame.filePicture]), counted from 0.
final class ReferenceLacksPicture extends ReferenceRedraw {
  const ReferenceLacksPicture(this.picture);

  final int picture;
}

/// How [layer] takes the file at [path] in place of the one it shows — or
/// null when it cannot: a row that points at no file, the file it already
/// shows, or a file that could not stand where its picture stands (a movie
/// row takes a movie, a still row a still). Each cel takes the same picture
/// of the new file — a still's, its one — as a movie row keeps where in the
/// file it starts.
///
/// ⚠️A reference row of any OTHER shape answers null — a sequence, an
/// animated GIF or a PDF's pages as cels. Each of its cels is one picture
/// of the file, and which picture of a new file a cel would take when the
/// two do not have as many is a question nobody has answered; the user
/// asked for an image row (「이미지 레이어의 프레임영역」) and a movie row
/// (Q1's 「참조로 둔 이미지(또는 동영상) 레이어」).
ReferenceSwap? referenceSwapFor(Layer layer, String path) {
  final reference = layer.mediaReference;
  if (reference == null || normalizedMediaPath(path) == reference.assetPath) {
    return null;
  }
  final redraw = referenceRedrawFor(layer);
  final stillRow =
      layer.kind == LayerKind.image &&
      mediaAssetKindForPath(reference.assetPath) == MediaAssetKind.image;
  // A movie row takes a movie, a still row a still.
  final takes = switch (redraw) {
    ReferenceSwap.movie => MediaAssetKind.video,
    ReferenceSwap.pictures when stillRow => MediaAssetKind.image,
    _ => null,
  };
  return takes != null && mediaAssetKindForPath(path) == takes ? redraw : null;
}

/// How [layer]'s pictures are made from its file AGAIN — each cel's own
/// picture laid anew, a movie's decoded anew as it is shown — or null when
/// the row points at no file, or has a cel that does not say which picture
/// of the file it is ([Frame.filePicture]): that one could not be made
/// again. Swapping the file and moving the reference fx both draw it again.
ReferenceSwap? referenceRedrawFor(Layer layer) {
  if (layer.mediaReference == null) {
    return null;
  }
  if (isMovieReference(layer)) {
    return ReferenceSwap.movie;
  }
  return layer.frames.isNotEmpty &&
          layer.frames.every((frame) => frame.filePicture != null)
      ? ReferenceSwap.pictures
      : null;
}
