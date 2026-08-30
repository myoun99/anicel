import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import 'app_support_path.dart';
import 'media_blob_codec.dart';

/// 🚨★★★**WHAT「품기」MEANS BETWEEN THE IMPORT AND THE FIRST SAVE.**
///
/// Carrying a file used to be a promise the project kept only at save
/// time: the flag said「this travels with the project」and the bytes were
/// still the ones on disk, so editing or deleting the original before the
/// first save changed or emptied what got saved. 유저 2026-08-30 named the
/// behaviour they wanted instead — 「품은 순간 데이터를 가지고있고
/// **불변**이었으면좋겠어서」 — and chose where it lives: 「앱컨테이너에
/// 먼저 넣는거… **저장할때 옮겨가는걸로**」.
///
/// So an import COPIES, compressed, into the app container, and the save
/// moves those bytes into the .anicel and retires the staged copy.
///
/// ⛔**This is not a second copy of the asset.** It is the only copy the
/// project controls until the first save, and it stops being anything the
/// moment the save absorbs it. 유저 08-27: 「사본 남으면 진짜 용서안할게」 —
/// which is what [retire] and [sweepAbandoned] are for.
///
/// ⚠️**It is also not a new category in the container.** `Recovery/`
/// already holds project snapshots and `Conformed/` already holds audio
/// derived from project media; see [appSupportFilePath]. What a new tenant
/// owes is a LIFETIME, and this one's is: retired by the save that
/// absorbs it, swept at launch when its project never came back.
///
/// 🚨**The name is DERIVED, never recorded** — the same rule the conform
/// store follows ("under a name derived by rule from the source path —
/// nothing recorded, nothing to fall out of sync"). A staged file that
/// nothing remembers cannot be remembered wrongly.
class MediaStagingStore {
  MediaStagingStore({String? directoryPath})
    : directoryPath = (directoryPath ?? defaultDirectory()).replaceAll(
        r'\',
        '/',
      );

  /// `<container>/Staged`, beside `Recovery` and `Conformed`.
  static String defaultDirectory() => appSupportFilePath('Staged');

  /// 🚨Separators normalised HERE, once.
  ///
  /// Every method compares a path it BUILT ([pathFor]) against a path the
  /// filesystem LISTED, and on Windows those disagree the moment a caller
  /// hands in a `\`-flavoured directory — `Directory.systemTemp` does. An
  /// earlier keep-set sweep failed to match a single live file that way
  /// and deleted the lot; the sweep is age-based now, but [find] and
  /// [list] still stand on the same comparison, so the normalisation stays
  /// where it cannot be forgotten.
  final String directoryPath;

  /// Where [poolPath]'s staged bytes live, framed or not.
  ///
  /// The suffix carries the same meaning it does inside the archive — see
  /// [mediaFramedEntrySuffix] — so a staged file can be streamed into the
  /// .anicel without being decoded and re-encoded on the way.
  String pathFor(String poolPath, {required bool framed}) =>
      mediaPathFramed(_basePathFor(poolPath), framed: framed);

  String _basePathFor(String poolPath) =>
      '$directoryPath/${stagedNameFor(poolPath)}';

  /// The staged copy of [poolPath], or null when there is none.
  ///
  /// Framed-first, through [mediaFramedOrPlainPaths] — the one place that
  /// knows a file this app wrote may wear either name.
  StagedMedia? find(String poolPath) {
    for (final candidate in mediaFramedOrPlainPaths(_basePathFor(poolPath))) {
      final file = File(candidate);
      if (file.existsSync()) {
        return StagedMedia(
          poolPath: poolPath,
          path: file.path.replaceAll(r'\', '/'),
          framed: mediaEntryIsFramed(candidate),
          storedLength: file.lengthSync(),
        );
      }
    }
    return null;
  }

  /// Copies [poolPath] into the staging area, compressed when that is
  /// worth it, and answers what landed.
  ///
  /// Idempotent: an asset already staged is left alone, because the bytes
  /// it holds are the ones the user asked to keep and the file on disk may
  /// have moved on since.
  ///
  /// 🚨★★★**THE WORK RUNS IN AN ISOLATE AND THE CALLER WAITS FOR IT.**
  ///
  /// Memory stopped being the problem when the write started streaming, but
  /// TIME did not: zstd is a blocking native call, so compressing a carried
  /// movie held the UI thread from the moment 품기 was pressed until the
  /// last block — minutes on a big file, with the app frozen.
  ///
  /// ⛔**Awaited, never fired and forgotten.** 유저 2026-08-30 asked for
  /// exactly one property — 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」 — and the pool must not record an asset whose bytes
  /// are still being secured. Every entrance therefore awaits this before
  /// the command that registers the asset runs, which is what turned four
  /// call sites async. The same shape the .tvpp import already uses:
  /// `Isolate.run` per unit, awaited, nothing registered early.
  Future<StagedMedia?> stage(String poolPath) async =>
      (await stageAll([poolPath])).firstOrNull;

  /// Every path in [poolPaths], in ONE isolate.
  ///
  /// ⚡One, not one each. A folder import can hand this hundreds of files,
  /// and an isolate costs milliseconds to start — spawning per file would
  /// have made the many-small-files case SLOWER than the synchronous
  /// version it replaces, while fixing only the one-big-file case.
  ///
  /// Answers only what actually landed: a path that was already staged
  /// comes back as it sits, and one whose file is gone is absent rather
  /// than null-in-place, because no caller asks "which index failed".
  Future<List<StagedMedia>> stageAll(Iterable<String> poolPaths) async {
    final todo = <String>[];
    final done = <StagedMedia>[];
    for (final path in poolPaths) {
      final already = find(path);
      if (already != null) {
        done.add(already);
      } else if (File(path).existsSync()) {
        todo.add(path);
      }
    }
    if (todo.isEmpty) {
      return done;
    }
    Directory(directoryPath).createSync(recursive: true);
    // Scalars only. The closure crosses an isolate boundary, so it opens
    // its own handles over there rather than capturing any from here.
    final directory = directoryPath;
    final written = await Isolate.run(() => _stageBytes(todo, directory));
    for (final one in written) {
      done.add(
        StagedMedia(
          poolPath: one.poolPath,
          path: one.path,
          framed: one.framed,
          storedLength: one.storedLength,
        ),
      );
    }
    return done;
  }

  /// Follows an asset whose pool path changed — a relink.
  ///
  /// 🚨★★★**THE NAME IS DERIVED, SO IT HAS TO MOVE WHEN THE PATH DOES.**
  /// Deriving the name is what makes a staged file impossible to remember
  /// wrongly, and the price is exactly this: nothing points at it, so a
  /// path change orphans it silently. The asset would then look unstaged —
  /// back to the promise being kept at save time — while the bytes it was
  /// promised sat under the old name waiting for the sweep.
  ///
  /// ⚠️The fingerprints already move this way (`_moveMediaFingerprints`),
  /// and for the same reason. Derived state follows its key or it is not
  /// derived, it is stale.
  void rename(String fromPoolPath, String toPoolPath) {
    final staged = find(fromPoolPath);
    if (staged == null) {
      return;
    }
    final destination = pathFor(toPoolPath, framed: staged.framed);
    if (destination == staged.path) {
      return;
    }
    Directory(directoryPath).createSync(recursive: true);
    // ⛔The destination is emptied first: a rename onto an existing file
    // fails on Windows, and the bytes already there belong to whatever
    // used to hold that pool path — which the caller has just replaced.
    final existing = File(destination);
    if (existing.existsSync()) {
      existing.deleteSync();
    }
    File(staged.path).renameSync(destination);
  }

  /// Drops the staged copy of [poolPath] — the save absorbed it.
  ///
  /// BOTH spellings, because which one is on disk depends on whether the
  /// bytes shrank, and a save must not leave half of an absorbed import
  /// behind (유저 08-27: 「사본 남으면 진짜 용서안할게」).
  void retire(String poolPath) {
    for (final candidate in mediaFramedOrPlainPaths(_basePathFor(poolPath))) {
      final file = File(candidate);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  /// Drops staged files old enough that nothing can still absorb them.
  ///
  /// 🚨★★★**AGE, NOT LIVENESS, AND ONLY AT LAUNCH.** The obvious sweep —
  /// "delete anything no open project claims" — cannot be written safely:
  /// at launch nothing is open yet, so the live set is empty and the sweep
  /// would take everything, including the import a person made a minute
  /// before the app crashed. Being handed a PARTIAL live set is the one
  /// mistake this class cannot make, so it is not asked for one.
  ///
  /// What makes age sound here: a staged file is written once, at import,
  /// and never touched again, and the save that absorbs it retires it on
  /// the spot. So one that is still here after [olderThan] belongs to a
  /// project that was never saved — and an unsaved project is not
  /// reachable again, because the import it holds was never written down
  /// anywhere. There is nothing to offer back.
  ///
  /// ⚠️Called ONCE PER LAUNCH, beside the recovery sweep, and for the same
  /// reason: a session that has been open for longer than the window must
  /// not have its own staged bytes taken out from under it. The default is
  /// the recovery snapshots' 30 days (유저 확정 2026-08-26: 「30일좋고」)
  /// rather than a second number to keep in step.
  int sweepAbandoned({
    Duration olderThan = const Duration(days: 30),
    DateTime? now,
  }) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return 0;
    }
    final cutoff = (now ?? DateTime.now()).subtract(olderThan);
    var removed = 0;
    for (final entity in directory.listSync()) {
      if (entity is! File) {
        continue;
      }
      final stat = FileStat.statSync(entity.path);
      if (stat.type == FileSystemEntityType.notFound ||
          !stat.modified.isBefore(cutoff)) {
        continue;
      }
      entity.deleteSync();
      removed += 1;
    }
    return removed;
  }

  /// Every staged file, for the settings list that shows what the app
  /// container holds.
  List<StagedMedia> list() {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return const [];
    }
    return [
      for (final entity in directory.listSync())
        if (entity is File && !entity.path.endsWith('.part'))
          StagedMedia(
            poolPath: null,
            path: entity.path.replaceAll(r'\', '/'),
            framed: mediaEntryIsFramed(entity.path),
            storedLength: entity.lengthSync(),
          ),
    ];
  }

  /// A stable, filesystem-safe name for [poolPath].
  ///
  /// The basename rides ahead of the hash for the same reason the archive
  /// entry's does: a person looking in the folder should be able to tell
  /// what they are looking at.
  /// The staged file's name for [poolPath] — derived, never recorded.
  ///
  /// Public because [_stageBytes] runs in an isolate and has to derive the
  /// same name over there; a second spelling of this rule is exactly the
  /// drift the derived-name design exists to make impossible.
  static String stagedNameFor(String poolPath) {
    final normalized = poolPath.replaceAll(r'\', '/');
    final slash = normalized.lastIndexOf('/');
    final base = slash < 0 ? normalized : normalized.substring(slash + 1);
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${hash.toRadixString(16).padLeft(8, '0')}-$safe';
  }
}

/// One staged file.
@immutable
class StagedMedia {
  const StagedMedia({
    required this.poolPath,
    required this.path,
    required this.framed,
    required this.storedLength,
  });

  /// The pool path these bytes were staged for, or null when the file was
  /// enumerated rather than looked up.
  final String? poolPath;

  /// Where the staged bytes are.
  final String path;

  /// Whether [path] holds a framed blob rather than the file's own bytes.
  final bool framed;

  /// Bytes on disk — the framed length when [framed], the file's own
  /// otherwise.
  final int storedLength;

  /// The bytes to write into the .anicel, verbatim.
  ///
  /// 🚨Framed or not, they go in AS THEY ARE: decoding a staged blob only
  /// to re-encode it would burn the whole point of having compressed it at
  /// import.
  Uint8List readStoredSync() => File(path).readAsBytesSync();
}

/// [MediaStagingStore.stageAll]'s work, as a top-level function so the
/// isolate closure captures a list of strings and nothing else.
///
/// ONE handle per file: `MediaFileBytes.readIntoSync` opens and closes per
/// call, which a 4GB asset at 512KB blocks would pay eight thousand times.
///
/// ⚠️A file that cannot be opened is SKIPPED, not thrown for. The batch may
/// be a whole folder, and one unreadable asset must not cost the rest their
/// bytes — the pool then simply has no staged copy for it, which is the
/// same state as never having asked.
List<({String poolPath, String path, bool framed, int storedLength})>
_stageBytes(List<String> poolPaths, String directoryPath) {
  final out =
      <({String poolPath, String path, bool framed, int storedLength})>[];
  for (final poolPath in poolPaths) {
    final RandomAccessFile handle;
    try {
      handle = File(poolPath).openSync();
    } on FileSystemException {
      continue;
    }
    try {
      final written = writeMediaBlob(
        basePath: '$directoryPath/${MediaStagingStore.stagedNameFor(poolPath)}',
        length: handle.lengthSync(),
        readInto: (buffer, position, size) {
          handle.setPositionSync(position);
          return handle.readIntoSync(buffer, 0, size);
        },
      );
      out.add((
        poolPath: poolPath,
        path: written.path,
        framed: written.framed,
        storedLength: File(written.path).lengthSync(),
      ));
    } finally {
      handle.closeSync();
    }
  }
  return out;
}
