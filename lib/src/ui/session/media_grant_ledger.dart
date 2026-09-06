// The OS's permission to read the media this project only REFERENCES —
// what the session holds this launch, and what the file should keep.
//
// Its own object since round 8 (G1, 2026-09-06): two lists and the four
// verbs over them were host members that touched nothing else of the
// session, and the pair of lists only means anything together.

import 'package:flutter/foundation.dart';

import '../../services/persistence/anicel_project_archive.dart'
    show projectMediaPaths;
import '../../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker;
import 'session_roles.dart';

/// The project's security-scoped tokens: the ones usable NOW and the ones
/// the next save writes down. They are two answers to two questions and
/// they disagree on purpose — see [debugStoredGrants].
class MediaGrantLedger {
  MediaGrantLedger({required ProjectAccess project}) : _project = project;

  final ProjectAccess _project;

  /// Security-scoped tokens for media the project REFERENCES, held beside
  /// the project rather than inside it.
  ///
  /// 🚨 Outside [Project] on purpose. Apple re-issues a bookmark on every
  /// resolve, so a grant in the model would mark the film dirty simply for
  /// having been opened — an edit the user never made, and a "save your
  /// changes?" they cannot account for. Keeping them here costs one
  /// argument at the save call and buys that.
  ///
  /// Empty on Windows, Linux and Android, where a recorded path keeps
  /// working on its own.
  List<FolderGrant> _mediaGrants = const [];

  /// 🚨 What the FILE should keep, which is not the same question as what
  /// this launch can USE.
  ///
  /// A bookmark that will not resolve right now is unusable today and
  /// perfectly good tomorrow: the volume is unmounted, the provider is
  /// signed out, the phone is in a different country. Keeping only what
  /// resolved would mean the next save writes the survivors and DELETES
  /// the rest — so plugging the drive back in would no longer help,
  /// because the token that named the file is gone from the only place it
  /// was written down.
  ///
  /// Android makes that concrete without any failure at all: it reports
  /// scoped grants, and its `resolveBookmark` answers `unavailable`
  /// unconditionally — so a project authored on an iPad, opened once on an
  /// Android tablet and saved, would come back to the iPad stripped of
  /// every bookmark it had.
  ///
  /// So resolution narrows [_mediaGrants]; it never narrows this.
  List<FolderGrant> _storedGrants = const [];

  /// What the session is holding, for tests. There is no production reader
  /// — grants leave through the save argument and arrive through the open
  /// result — so without this the round trip has no observer at all.
  @visibleForTesting
  List<FolderGrant> get debugMediaGrants => List.unmodifiable(_mediaGrants);

  /// What the next save would write down, for tests. Distinct from
  /// [debugMediaGrants] exactly where it matters: a grant the OS refused
  /// today is absent there and present here.
  @visibleForTesting
  List<FolderGrant> get debugStoredGrants => List.unmodifiable(_storedGrants);

  /// Adds what a picker just granted, replacing any grant for the same
  /// path. Newest wins: Apple hands back a fresh token every time, and the
  /// old one is the stale copy.
  ///
  /// ⛔ Does NOT touch the session's unsaved-changes flag. This is OS
  /// bookkeeping, not the user's work — it rides along on the next save
  /// they were going to make anyway (그쪽 확정 ⑩).
  void rememberMediaGrants(Iterable<FolderGrant> grants) {
    final incoming = [
      for (final grant in grants)
        if (grant.isGranted && grant.bookmark != null) grant,
    ];
    if (incoming.isEmpty) {
      return;
    }
    final replaced = {for (final grant in incoming) grant.path};
    _mediaGrants = [
      for (final grant in _mediaGrants)
        if (!replaced.contains(grant.path)) grant,
      ...incoming,
    ];
    _storedGrants = [
      for (final grant in _storedGrants)
        if (!replaced.contains(grant.path)) grant,
      ...incoming,
    ];
  }

  /// Hands every stored bookmark back to the OS, so the session may read
  /// the media this project only REFERENCES.
  ///
  /// Resolved ALL AT ONCE on open rather than lazily at each read. There
  /// is no single point where media bytes are asked for — audio decode,
  /// image decode and thumbnails each reach for a file — so a lazy scheme
  /// would need that point built first. References are few by design (the
  /// kind rule keeps everything but video inside the archive), which is
  /// what makes the simple answer affordable.
  ///
  /// 🚨 The answer REPLACES what was stored. Apple re-issues a bookmark on
  /// every resolve, and a bookmark tracks the file rather than the path —
  /// so this is also how a referenced movie that was moved or renamed is
  /// followed instead of lost. Dropping the new token is a bug this
  /// codebase has already had once (`_openRecent` overwrote a fresh
  /// bookmark with the stale one it had in hand).
  ///
  /// ⛔ Never dirties the project. The re-issue is the OS's bookkeeping,
  /// not an edit, and it rides along on the next save.
  ///
  /// ⛔ A grant that will not resolve is unusable THIS LAUNCH and is not
  /// forgotten: it stays in [_storedGrants] so the next save writes it back
  /// unchanged. Dropping it from the file would turn "the drive is
  /// unplugged" into "the permission is gone", and plugging the drive back
  /// in would no longer help.
  ///
  /// Returns {old path: new path} for every bookmark that came back
  /// pointing somewhere else, so the caller can take the project with it.
  Future<Map<String, String>> resolveMediaGrants(
    List<Map<String, Object?>> stored,
  ) async {
    final parsed = [for (final json in stored) ?FolderGrant.fromJson(json)];
    _storedGrants = parsed;
    if (parsed.isEmpty || !FolderPicker.grantsAreScoped) {
      // Nothing to hold, or a platform where a path is durable on its own
      // — Windows and Linux never minted these in the first place.
      _mediaGrants = parsed;
      return const {};
    }
    final resolved = <FolderGrant>[];
    final stillStored = <FolderGrant>[];
    final moved = <String, String>{};
    for (final grant in parsed) {
      final answer = await FolderPicker.resolveBookmark(
        grant.bookmark!,
        kind: grant.kind,
      );
      if (!answer.isGranted || answer.path == null) {
        stillStored.add(grant); // Unusable today. Not gone.
        continue;
      }
      final fresh = FolderGrant.granted(
        path: answer.path!,
        // The freshly issued token, never the one we arrived with.
        bookmark: answer.bookmark ?? grant.bookmark,
        kind: grant.kind,
      );
      if (fresh.path != grant.path) {
        moved[grant.path!] = fresh.path!;
      }
      resolved.add(fresh);
      stillStored.add(fresh);
    }
    _mediaGrants = resolved;
    _storedGrants = stillStored;
    return moved;
  }

  /// The grants worth writing into this save, as JSON.
  ///
  /// Filtered HERE rather than in the writer, which runs in an isolate and
  /// has no business knowing what a grant is. A token for a file the pool
  /// no longer holds is a permission record for something nobody uses, and
  /// a project file that accumulates those is the shape that reads as an
  /// app hoarding access.
  List<Map<String, Object?>> grantsToStore() {
    if (_storedGrants.isEmpty) {
      return const [];
    }
    final referenced = projectMediaPaths(_project.repository.requireProject());
    return [
      for (final grant in _storedGrants)
        if (referenced.any(grant.covers)) ?grant.toJson(),
    ];
  }
}
