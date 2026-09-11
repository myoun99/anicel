import 'frame_id.dart';
import 'layer.dart';
import 'media_asset.dart';

/// A MOVIE kept as a reference is ONE cel exposed over its span — the block
/// the timeline draws — yet every position of that span shows a different
/// picture (미디어 배치 라운드 6). Its "movie cels" are the per-position cels
/// the compositor asks for: the held cel's id plus how many PROJECT frames
/// into the movie the position is, [MediaReference.frameOffset] included,
/// so moving the block or trimming its head leaves every key where it was.
///
/// ⚠️The key names a POSITION on the sound's clock, not a frame of the file:
/// which frame a position shows depends on the file's own rate, and only the
/// decoder knows that exactly (`MovieClock`) — the hydrator reads it there,
/// and positions that show one movie frame share one decoded picture.
const String _movieCelMark = '@m';

/// The movie cel [elapsed] project frames into the movie [held] holds.
FrameId movieCelFrameId(FrameId held, int elapsed) =>
    FrameId('${held.value}$_movieCelMark$elapsed');

/// [id]'s held cel and position when it names a movie cel; null otherwise.
({FrameId held, int elapsed})? movieCelOf(FrameId id) {
  final at = id.value.lastIndexOf(_movieCelMark);
  if (at <= 0) {
    return null;
  }
  final elapsed = int.tryParse(id.value.substring(at + _movieCelMark.length));
  if (elapsed == null || elapsed < 0) {
    return null;
  }
  return (held: FrameId(id.value.substring(0, at)), elapsed: elapsed);
}

/// Whether [layer] is a MOVIE kept as a reference: its one cel has no pixels
/// of its own, and every position of it is a movie cel.
bool isMovieReference(Layer layer) {
  final reference = layer.mediaReference;
  return reference != null &&
      mediaAssetKindForPath(reference.assetPath) == MediaAssetKind.video;
}
