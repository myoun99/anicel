import 'frame_id.dart';
import 'layer.dart';
import 'media_asset.dart';
import 'media_reference.dart';
import 'timeline_coverage.dart';

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

/// How many PROJECT frames into the movie the position at [positionInBlock]
/// of a movie row's block is: the position plus the head [reference] itself
/// skips ([MediaReference.frameOffset]).
///
/// ⚠️ONE LINE, AND WRITTEN ONCE ON PURPOSE. Three places ask it — the visit
/// every route composes through ([resolveExposedFrameAt]), the bake that
/// turns a row into cels, and the check that asks whether the file is long
/// enough for the row. Were one of them to forget the offset, a trimmed
/// head would show one movie while the other two showed another.
int movieElapsedAt(MediaReference reference, int positionInBlock) =>
    positionInBlock + reference.frameOffset;

/// PROJECT frames [layer]'s blocks ask of its movie: one past the furthest
/// position any of them reaches, and 0 for a row pointing at no file.
///
/// Weigh it against `MovieClock.projectFramesCovering` of the file's own
/// frame count — the very law the placement used to decide the block's
/// length — and a row asking for more than the file covers is a row whose
/// tail has no picture to show.
int movieProjectFramesAskedOf(Layer layer) {
  final reference = layer.mediaReference;
  if (reference == null) {
    return 0;
  }
  var asked = 0;
  for (final block in drawingBlocks(layer.timeline)) {
    final end = movieElapsedAt(reference, block.length - 1) + 1;
    if (end > asked) {
      asked = end;
    }
  }
  return asked;
}
