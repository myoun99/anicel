import 'dart:io';

import '../persistence/app_save_settings.dart';

/// How much conform cache is allowed to accumulate before the least
/// recently used entries are dropped.
///
/// A conform is roughly twelve times its source, so an hour of dialogue
/// costs the better part of a gigabyte. Two gigabytes holds a few hours of
/// audio across every project someone is working on, which is more than a
/// cut's worth of reuse and far less than the unbounded pile this replaces.
///
/// Nobody was collecting any of it. On a desktop that is a folder someone
/// can find and delete; on an iPad the app container is neither visible
/// nor reachable, so "it just grows" meant "it grows until the device is
/// full and nothing explains why".
const int conformCacheBudgetBytes = 2 * 1024 * 1024 * 1024;

/// One entry in the cache, and when it was last wanted.
///
/// Last-USED rather than last-built: reuse touches the file, so an mtime
/// is the only stamp needed and there is no index to keep honest. An index
/// would be a second source of truth about a directory that already knows.
typedef ConformCacheEntry = ({String path, int bytes, DateTime lastUsed});

/// Every cached conform under the current root, newest use first.
///
/// Returns an empty list when the root does not exist yet — a cache that
/// has never been written is not an error.
List<ConformCacheEntry> conformCacheEntries() {
  final root = Directory(AppSave.conformRootDirectory);
  if (!root.existsSync()) {
    return const [];
  }
  final entries = <ConformCacheEntry>[];
  try {
    for (final item in root.listSync(followLinks: false)) {
      if (item is! File) {
        continue;
      }
      try {
        final stat = item.statSync();
        entries.add((
          path: item.path.replaceAll('\\', '/'),
          bytes: stat.size,
          lastUsed: stat.modified,
        ));
      } on Object {
        continue; // Vanished mid-scan; the next pass will not see it.
      }
    }
  } on Object {
    return const [];
  }
  entries.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
  return entries;
}

/// What the cache currently occupies, in bytes.
int conformCacheBytes() =>
    conformCacheEntries().fold<int>(0, (sum, entry) => sum + entry.bytes);

/// Drops entries, least recently used first, until the cache fits inside
/// [budgetBytes]. Returns the number of bytes reclaimed.
///
/// Also removes the per-project SUBFOLDERS an older build wrote. Those are
/// unreachable now — the cache is keyed by source, so nothing will ever
/// look inside one again — and leaving them would mean the pile this
/// exists to bound is partly made of entries it cannot even see.
///
/// ⚠️ Called when a project OPENS rather than after every conform, which
/// is the moment a fresh batch is about to be built and the one place the
/// bound is worth enforcing. A single very long session can run over it;
/// the next open settles up. The alternative is a directory scan on the
/// UI isolate every few seconds for a limit measured in gigabytes.
int pruneConformCache({int budgetBytes = conformCacheBudgetBytes}) {
  final root = Directory(AppSave.conformRootDirectory);
  if (!root.existsSync()) {
    return 0;
  }
  var reclaimed = 0;
  try {
    for (final item in root.listSync(followLinks: false)) {
      if (item is! Directory) {
        continue;
      }
      try {
        reclaimed += _directoryBytes(item);
        item.deleteSync(recursive: true);
      } on Object {
        continue;
      }
    }
  } on Object {
    // Fall through: whatever could be listed has been dealt with.
  }

  final entries = conformCacheEntries();
  var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
  // Newest first, so walking backwards drops the coldest first.
  for (var index = entries.length - 1; index >= 0 && total > budgetBytes;
      index -= 1) {
    final entry = entries[index];
    try {
      File(entry.path).deleteSync();
      total -= entry.bytes;
      reclaimed += entry.bytes;
    } on Object {
      continue; // In use on Windows, say. It stays and counts.
    }
  }
  return reclaimed;
}

/// Empties the cache outright — the Preferences button.
///
/// Safe at any time: a conform is derived data, so the cost of being
/// wrong is a re-decode. That is exactly why the button can exist without
/// a confirmation step.
int clearConformCache() => pruneConformCache(budgetBytes: 0);

int _directoryBytes(Directory directory) {
  var bytes = 0;
  try {
    for (final item in directory.listSync(recursive: true, followLinks: false)) {
      if (item is File) {
        try {
          bytes += item.statSync().size;
        } on Object {
          continue;
        }
      }
    }
  } on Object {
    return bytes;
  }
  return bytes;
}
