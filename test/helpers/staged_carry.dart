import 'package:anicel/src/models/media_asset.dart' show MediaCarry;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show projectMediaCarryOf;
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The carry [session]'s pool names at [path] — the one whose bytes every
/// reader and the save take ([projectMediaCarryOf]) — or null when the pool
/// points at the file, or names nothing there.
MediaCarry? carryIn(EditorSessionManager session, String path) =>
    projectMediaCarryOf(session.repository.requireProject(), path);

/// The staged copy of [carryIn], or null when there is no carry or no copy.
///
/// ⚠️Null is NOT「nothing is staged for this path」: an earlier carry of it
/// may still have a copy, for an undo to bring back. That question is
/// [MediaStagingStore.holdsAnyCopyOf].
StagedMedia? stagedCopyIn(EditorSessionManager session, String path) {
  final carry = carryIn(session, path);
  return carry == null ? null : session.mediaStagingStore.find(carry);
}
