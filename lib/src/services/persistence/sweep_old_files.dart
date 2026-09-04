import 'dart:io';

/// Deletes every FILE directly in [directory] whose mtime is older than
/// [olderThan], and answers how many went.
///
/// ⛔TWO LAUNCH SWEEPS, ONE LAW — and they had already drifted. The
/// recovery sweep swallowed a failed delete ("locked by a sync client or
/// an open handle: next launch retries") and the staged sweep did not, so
/// one locked file threw out of the launch sweep and left everything
/// after it unswept.
///
/// ⚠️`followLinks: false` — a link pointing into the user's own folders is
/// not this container's to delete.
///
/// ⚠️Called ONCE PER LAUNCH: a session open for longer than the window
/// must not have its own bytes taken out from under it.
int sweepFilesOlderThan(
  Directory directory, {
  required Duration olderThan,
  DateTime? now,
}) {
  if (!directory.existsSync()) {
    return 0;
  }
  final cutoff = (now ?? DateTime.now()).subtract(olderThan);
  var swept = 0;
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final stat = FileStat.statSync(entity.path);
    if (stat.type == FileSystemEntityType.notFound ||
        !stat.modified.isBefore(cutoff)) {
      continue;
    }
    try {
      entity.deleteSync();
      swept += 1;
    } on Object catch (_) {
      // Locked by a sync client or an open handle: next launch retries.
    }
  }
  return swept;
}
