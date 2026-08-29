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
/// which is what [retire] and [sweepOrphans] are for.
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
  /// [sweepOrphans] compares the paths it builds against the paths the
  /// filesystem lists, and on Windows those disagree the moment a caller
  /// hands in a `\`-flavoured directory: `Directory.systemTemp` does. Every
  /// live file then failed to match the keep-set and the sweep deleted the
  /// lot — the one mistake this class must not make, caught by its own
  /// test before it ever ran.
  final String directoryPath;

  /// Where [poolPath]'s staged bytes live, framed or not.
  ///
  /// The suffix carries the same meaning it does inside the archive — see
  /// [mediaFramedEntrySuffix] — so a staged file can be streamed into the
  /// .anicel without being decoded and re-encoded on the way.
  String pathFor(String poolPath, {required bool framed}) =>
      '$directoryPath/${_stagedName(poolPath)}'
      '${framed ? mediaFramedEntrySuffix : ''}';

  /// The staged copy of [poolPath], or null when there is none.
  StagedMedia? find(String poolPath) {
    for (final framed in [true, false]) {
      final file = File(pathFor(poolPath, framed: framed));
      if (file.existsSync()) {
        return StagedMedia(
          poolPath: poolPath,
          path: file.path.replaceAll(r'\', '/'),
          framed: framed,
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
    final bytes = source.readAsBytesSync();
    final framed = compressMediaBlob(bytes);
    final path = pathFor(poolPath, framed: framed != null);
    // ⛔Written to a neighbour and renamed, so a staged file is either
    // complete or absent. A half-written one would be indistinguishable
    // from a whole one, and the whole point is that these bytes are the
    // ones the project keeps.
    final temp = File('$path.part');
    temp.writeAsBytesSync(framed ?? bytes, flush: true);
    temp.renameSync(path);
    return StagedMedia(
      poolPath: poolPath,
      path: path,
      framed: framed != null,
      storedLength: (framed ?? bytes).length,
    );
  }

  /// Drops the staged copy of [poolPath] — the save absorbed it.
  void retire(String poolPath) {
    for (final framed in [true, false]) {
      final file = File(pathFor(poolPath, framed: framed));
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  /// Drops staged files that no live pool path claims.
  ///
  /// 🚨Called with the paths of every asset the OPEN projects still hold.
  /// A staged file whose import was undone, or whose project was closed
  /// without ever being saved, has nothing left to absorb it — and unlike
  /// a recovery snapshot it is not offered back to anyone, so there is
  /// nothing to wait for.
  ///
  /// ⚠️[keep] must be the whole live set. Sweeping against a partial one
  /// would delete bytes a project is still counting on, which is the one
  /// mistake this class cannot make.
  int sweepOrphans({required Set<String> keep}) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return 0;
    }
    final live = {
      for (final path in keep)
        for (final framed in [true, false]) pathFor(path, framed: framed),
    };
    var removed = 0;
    for (final entity in directory.listSync()) {
      if (entity is! File || live.contains(entity.path.replaceAll(r'\', '/'))) {
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
