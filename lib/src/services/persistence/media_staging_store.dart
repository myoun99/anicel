import 'dart:io';
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
      '$directoryPath/${_stagedName(poolPath)}';

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
  StagedMedia? stage(String poolPath) {
    final already = find(poolPath);
    if (already != null) {
      return already;
    }
    final source = File(poolPath);
    if (!source.existsSync()) {
      return null;
    }
    Directory(directoryPath).createSync(recursive: true);
    // 🚨★★★**THE ASSET IS NEVER RESIDENT.** This read the file whole and
    // handed it to the in-memory codec, which built every compressed block
    // beside it before judging the total — a 4GB movie was the file twice
    // over, on the UI isolate, at the moment 품기 is pressed. Streaming is
    // not an optimisation here: it is the difference between carrying a
    // big movie and being killed for trying.
    final handle = source.openSync();
    final ({String path, bool framed}) written;
    try {
      written = writeMediaBlob(
        basePath: _basePathFor(poolPath),
        length: handle.lengthSync(),
        // ONE handle for the whole file. `MediaFileBytes.readIntoSync`
        // opens and closes per call, which a 4GB asset would pay eight
        // thousand times.
        readInto: (buffer, position, size) {
          handle.setPositionSync(position);
          return handle.readIntoSync(buffer, 0, size);
        },
      );
    } finally {
      handle.closeSync();
    }
    return StagedMedia(
      poolPath: poolPath,
      path: written.path,
      framed: written.framed,
      storedLength: File(written.path).lengthSync(),
    );
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
  static String _stagedName(String poolPath) {
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
