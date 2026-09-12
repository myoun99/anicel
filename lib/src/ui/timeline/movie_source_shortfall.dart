import '../../models/layer.dart';
import '../../models/movie_cel.dart';
import '../../models/movie_clock.dart';
import '../editor_session_manager.dart';

/// PROJECT frames [layer]'s row asks of its movie BEYOND what the file can
/// show — 0 when the file covers the row, and 0 while nothing is known yet.
///
/// 🚨★★★THE DATA IS NOT TOUCHED (유저 2026-09-12, `video-place` Q3: 「참조버튼을
/// 빨갛게 만들고, 그걸 누르면 팝오버 항목중 하나로 내용 띄우도록」). The row
/// keeps the IN point and the length it was placed with, so a source that
/// grows back fills its own tail in again; what this buys is only that the
/// row SAYS so. ⛔Do not "fix" it by clamping the block — the clamp is the
/// option the user did not choose.
///
/// ⚠️IT ASKS THE HYDRATOR, NOT THE POOL. `MediaAsset.sourceFps` is a
/// `double`, and 30000/1001 is not 29.97 — a clock built from it would be a
/// second, rounder law for the very question [MovieClock] exists to answer
/// exactly, and the pool's `frameCount` was written at registration rather
/// than about the file that is there now.
///
/// ⚠️0 UNTIL THE DECODER HAS ANSWERED, on purpose: a guess would paint the
/// button red on a file that is fine. The hydrator opens every movie row of
/// the cut it hydrates and announces when one lands, so the answer arrives
/// within a frame of the row being on screen.
int movieSourceShortfall(EditorSessionManager session, Layer layer) {
  if (!isMovieReference(layer)) {
    return 0;
  }
  final info = session.movieCels.factsFor(layer.mediaReference!.assetPath);
  if (info == null) {
    return 0;
  }
  // The SAME law the placement used to decide the block's length, so a row
  // that was placed whole is never called short by a rounding of its own.
  final covered = movieClockFor(
    projectRate: session.projectSettings.projectFrameRate,
    audioSpeed: session.repository.requireProject().audioSpeed,
    movie: info,
  ).projectFramesCovering(info.frameCount);
  final asked = movieProjectFramesAskedOf(layer);
  return asked > covered ? asked - covered : 0;
}
