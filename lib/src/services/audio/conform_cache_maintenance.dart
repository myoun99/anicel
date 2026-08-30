import 'dart:io';
import 'dart:typed_data';

import '../media/media_byte_source.dart';
import '../persistence/app_save_settings.dart';
import '../persistence/media_blob_codec.dart';
import 'conform_pcm_codec.dart';

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

/// 🚨 The cache root is a SETTING, and Preferences invites the user to
/// browse to any folder they like — a fast drive, an SD card, and just as
/// easily the folder their work is in. So the collector only ever touches
/// what it can PROVE is its own.
///
/// ⛔ A name pattern is not proof. The first version of this guard asked
/// for `<something>.<8 hex>.wav` and `<something>.<8 hex>` — and hex
/// digits include decimal ones, so a dated backup folder `씬01.20260813/`
/// matched and was deleted recursively, and a render `믹스.20260813.wav`
/// was counted as cache and evicted. A guess that is usually right is the
/// worst kind of guard, because the case it gets wrong is somebody's work.
///
/// So a FILE is ours only if it says so in its own bytes: a conform opens
/// with [ConformHeader.magic], eight bytes nobody else writes.
///
/// 🆕**That used to be an ASSUMPTION rather than proof.** A conform was a
/// WAV, and the test was `RIFF` + `WAVE` + our own `qacf` chunk landing at
/// offset 36 — which is the claim「no other tool writes that combination」,
/// and the paragraph above is a list of what such claims have cost this
/// file. A private magic is not a guess.
///
/// A DIRECTORY cannot be asked, so the rule there is narrow instead: the
/// exact shape `AppSave.encodeProjectKey` used to write — a project file
/// name, so `.anicel.` literally, plus the hash — AND nothing inside it
/// but conforms of ours. If a folder that matches holds anything else, it
/// is somebody's folder that happens to be named like ours, and it stays.
///
/// The same rule governs the SIZE, not only the deleting: a number that
/// counted the user's own files would promise to reclaim what it must
/// never touch, under a button that looks like it worked.
///
/// 🚨The `.z` is not optional decoration — a conform is written compressed
/// when that is worth it ([writeMediaBlob]), and a pattern that only
/// matched the plain spelling would have made every compressed conform
/// INVISIBLE to this file: uncounted in the size the settings panel shows,
/// and unreachable by the collector, so the pile this exists to bound
/// would have grown without a bound and without a trace.
final RegExp _ourEntryName = RegExp(
  r'\.[0-9a-f]{8}\.wav(' + RegExp.escape(mediaFramedEntrySuffix) + r')?$',
);
final RegExp _ourLegacyFolder = RegExp(r'\.anicel\.[0-9a-f]{8}$');

/// The shape a conform wore before it had a header of its own: `RIFF` at 0,
/// `WAVE` at 8, our `qacf` chunk at 36.
///
/// 🚨★★★**KEPT ONLY SO THE OLD ONES CAN STILL BE COLLECTED.** Nothing
/// writes this any more, and no reader accepts it — an old conform fails
/// [ConformHeader.parse] and is rebuilt. But a file the collector cannot
/// RECOGNISE is a file it never deletes, and every conform on every machine
/// that ran a previous build is one of those. Dropping this check would
/// have left them sitting in the cache for ever, uncounted, which is the
/// exact unbounded pile this file exists to prevent.
///
/// ⇒ Delete this when those are gone. It is a collector, not a reader:
/// recognising a legacy conform means「take it away」, never「play it」.
const List<int> _legacyRiff = [0x52, 0x49, 0x46, 0x46]; // RIFF
const List<int> _legacyWave = [0x57, 0x41, 0x56, 0x45]; // WAVE
const List<int> _legacyQacf = [0x71, 0x61, 0x63, 0x66]; // qacf

bool _tagAt(List<int> bytes, int offset, List<int> tag) {
  if (bytes.length < offset + tag.length) {
    return false;
  }
  for (var index = 0; index < tag.length; index += 1) {
    if (bytes[offset + index] != tag[index]) {
      return false;
    }
  }
  return true;
}

/// Whether [path] is a conform THIS app wrote — decided by reading its
/// first forty bytes rather than by looking at its name.
bool _isOurConform(String path) {
  if (!_ourEntryName.hasMatch(path)) {
    return false; // Cheap reject; the read below is the actual answer.
  }
  try {
    // 🚨Through [mediaAppFileSource], which is where「the name says whether
    // it is framed」lives. For a compressed conform that decompresses the
    // FIRST BLOCK and nothing else — 512KB, under a millisecond — so the
    // proof stays exactly as strong as it was when the bytes were plain.
    // Reading the file raw instead would see a block index where it wanted
    // the magic and quietly answer「not ours」to every file this app writes.
    final head = Uint8List(40);
    final got = mediaAppFileSource(path).readIntoSync(head, 0, head.length);
    if (got < ConformHeader.magic.length) {
      return false;
    }
    if (looksLikeConform(head)) {
      return true;
    }
    return got >= 40 &&
        _tagAt(head, 0, _legacyRiff) &&
        _tagAt(head, 8, _legacyWave) &&
        _tagAt(head, 36, _legacyQacf);
  } on Object {
    return false; // Unreadable is not ours as far as deleting goes.
  }
}

/// Every cached conform under the current root, newest use first.
///
/// OURS only — see [_isOurConform]. Returns an empty list when the root
/// does not exist yet; a cache that has never been written is not an error.
List<ConformCacheEntry> conformCacheEntries() {
  final root = Directory(AppSave.conformRootDirectory);
  if (!root.existsSync()) {
    return const [];
  }
  final entries = <ConformCacheEntry>[];
  try {
    for (final item in root.listSync(followLinks: false)) {
      if (item is! File || !_isOurConform(item.path)) {
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
/// Also removes the per-project SUBFOLDERS an older build wrote — the ones
/// it can recognise as such ([_ourLegacyFolder]). Those are unreachable
/// now, since the cache is keyed by source and nothing will ever look
/// inside one again, and leaving them would mean the pile this exists to
/// bound is partly made of entries it cannot even see.
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
      if (item is! Directory || !_ourLegacyFolder.hasMatch(item.path)) {
        continue;
      }
      reclaimed += _collectLegacyFolder(item);
    }
  } on Object {
    // Fall through: whatever could be listed has been dealt with.
  }

  final entries = conformCacheEntries();
  var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
  // Newest first, so walking backwards drops the coldest first.
  for (
    var index = entries.length - 1;
    index >= 0 && total > budgetBytes;
    index -= 1
  ) {
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
/// 🚨 The SESSION has to stand down first. A conform longer than the
/// streaming threshold is kept in `AudioConformStore` with `samples: null`
/// and the file as the copy of record, so deleting that file behind a live
/// entry does not cost a re-decode — the store goes on believing it has a
/// usable conform, the reader opens nothing, and the clip is silent for
/// the rest of the session and silent in the export.
///
/// 🪦Windows used to have a mirror of this — an open reader blocked the
/// delete, so the biggest entries survived the emptying meant to reclaim
/// them. `ConformPcmStreamReader` holds no handle now, so that half is
/// gone. The silence half is not, which is why this stays mandatory.
///
/// ⛔ So never call this without `AudioConformStore.releaseDiskBacked()`
/// first. "Derived data, worst case a re-decode" is only true once the
/// session has let go.
int clearConformCache() => pruneConformCache(budgetBytes: 0);

/// Removes one `<project>.anicel.<hash>` folder an older build wrote, and
/// returns what it reclaimed. Zero when the folder is not entirely ours.
///
/// ⛔ NOT a recursive delete. The folder name matching is a strong hint,
/// not proof — so the contents have to agree: every file directly inside
/// must be a `.wav`, and there must be no subfolders. An old conform cache
/// is exactly that and nothing else. A folder that happens to be named
/// like one of ours but holds anything else is somebody's, and it stays,
/// whole.
int _collectLegacyFolder(Directory directory) {
  final files = <File>[];
  var bytes = 0;
  try {
    for (final item in directory.listSync(followLinks: false)) {
      if (item is! File || !item.path.toLowerCase().endsWith('.wav')) {
        return 0; // Not entirely ours. Leave the whole thing alone.
      }
      files.add(item);
      bytes += item.statSync().size;
    }
  } on Object {
    return 0;
  }
  try {
    for (final file in files) {
      file.deleteSync();
    }
    directory.deleteSync();
  } on Object {
    return 0; // Half-removed is fine; the next prune finishes it.
  }
  return bytes;
}
